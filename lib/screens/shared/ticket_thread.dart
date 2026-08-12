import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// One doubt ticket's 1-to-1 chat — used by both the student and the
/// teacher. Messages stream in live; supports text, images, voice notes
/// and scheduled video-call cards.
class TicketThreadScreen extends StatefulWidget {
  final Ticket ticket;
  final bool asTeacher;
  final String senderName;

  const TicketThreadScreen({
    super.key,
    required this.ticket,
    required this.asTeacher,
    required this.senderName,
  });

  @override
  State<TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends State<TicketThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _sending = false;
  bool _recording = false;
  String? _playingUrl;
  late String _status = widget.ticket.status;

  String get _role => widget.asTeacher ? 'teacher' : 'student';

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _send({
    required String kind,
    String body = '',
    String? mediaPath,
  }) async {
    setState(() => _sending = true);
    try {
      await repo.sendTicketMessage(
        ticketId: widget.ticket.id,
        senderRole: _role,
        senderName: widget.senderName,
        kind: kind,
        body: body,
        mediaPath: mediaPath,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    await _send(kind: 'text', body: body);
  }

  Future<void> _sendImage() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final path = await repo.uploadMedia(
          bytes: bytes, extension: 'jpg', contentType: 'image/jpeg');
      await _send(kind: 'image', mediaPath: path);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        setState(() => _recording = false);
        if (path == null) return;
        final bytes = await XFile(path).readAsBytes();
        final storagePath = await repo.uploadMedia(
          bytes: bytes,
          extension: kIsWeb ? 'webm' : 'm4a',
          contentType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        );
        await _send(kind: 'voice', mediaPath: storagePath);
      } else {
        if (!await _recorder.hasPermission()) {
          if (mounted) showError(context, 'Microphone permission was denied.');
          return;
        }
        await _recorder.start(
          RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
          path: 'voice-note.m4a',
        );
        setState(() => _recording = true);
      }
    } catch (e) {
      setState(() => _recording = false);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _togglePlay(String url) async {
    if (_playingUrl == url) {
      await _player.stop();
      setState(() => _playingUrl = null);
      return;
    }
    await _player.stop();
    setState(() => _playingUrl = url);
    await _player.play(UrlSource(url));
    _player.onPlayerComplete.first.then((_) {
      if (mounted && _playingUrl == url) setState(() => _playingUrl = null);
    });
  }

  Future<void> _resolve() async {
    final next = _status == 'open' ? 'resolved' : 'open';
    try {
      await repo.setTicketStatus(widget.ticket.id, next);
      setState(() => _status = next);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _scheduleCall() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await repo.scheduleMeeting(
        ticketId: widget.ticket.id,
        at: at,
        teacherName: widget.senderName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('1-to-1 video call scheduled — the link is in the chat.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final resolved = _status == 'resolved';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.ticket.title,
                style: text.titleLarge, overflow: TextOverflow.ellipsis),
            Text(
              widget.asTeacher
                  ? 'Doubt from ${widget.ticket.studentName ?? 'a student'}'
                  : 'Your 1-to-1 doubt session',
              style: text.bodySmall,
            ),
          ],
        ),
        actions: [
          if (widget.asTeacher) ...[
            IconButton(
              tooltip: 'Schedule 1-to-1 video call',
              onPressed: _scheduleCall,
              icon: const Icon(Icons.video_call_outlined),
            ),
            TextButton.icon(
              onPressed: _resolve,
              icon: Icon(resolved ? Icons.replay : Icons.check_circle_outline,
                  size: 18),
              label: Text(resolved ? 'Reopen' : 'Resolve'),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: PillBadge(
                  label: resolved ? 'Resolved' : 'Open',
                  color: resolved
                      ? Palette.sage.withValues(alpha: 0.15)
                      : const Color(0xFFFDF1DC),
                  textColor:
                      resolved ? Palette.sage : const Color(0xFF8A5A13),
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (resolved)
            Container(
              width: double.infinity,
              color: Palette.sage.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Text(
                'This doubt has been marked resolved.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Palette.sage),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<TicketMessage>>(
              stream: repo.streamTicketMessages(widget.ticket.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: Palette.navy));
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: EmptyNote(
                      icon: Icons.forum_outlined,
                      title: 'No messages yet',
                      body: 'Say hello — messages arrive here instantly.',
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: messages[i],
                    mine: messages[i].senderRole == _role,
                    playingUrl: _playingUrl,
                    onPlayVoice: _togglePlay,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Palette.card,
                border: Border(top: BorderSide(color: Palette.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send an image',
                    onPressed: _sending ? null : _sendImage,
                    icon: const Icon(Icons.image_outlined, color: Palette.faint),
                  ),
                  IconButton(
                    tooltip: _recording ? 'Stop & send' : 'Record a voice note',
                    onPressed: _sending ? null : _toggleRecording,
                    icon: Icon(
                      _recording ? Icons.stop_circle : Icons.mic_none,
                      color: _recording ? Palette.red : Palette.faint,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Recording… tap stop to send'
                            : 'Type a message',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(backgroundColor: Palette.dark),
                    onPressed: _sending ? null : _sendText,
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TicketMessage message;
  final bool mine;
  final String? playingUrl;
  final void Function(String url) onPlayVoice;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.playingUrl,
    required this.onPlayVoice,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (message.kind == 'meeting') return _MeetingCard(message: message);

    final bubbleColor = mine ? Palette.navy : Palette.card;
    final fg = mine ? Colors.white : Palette.dark;

    Widget content;
    switch (message.kind) {
      case 'image':
        content = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
            child: Image.network(
              repo.mediaUrl(message.mediaPath ?? ''),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 100,
                alignment: Alignment.center,
                color: Palette.paper,
                child: const Text('Image unavailable',
                    style: TextStyle(color: Palette.faint, fontSize: 12)),
              ),
            ),
          ),
        );
      case 'voice':
        final url = repo.mediaUrl(message.mediaPath ?? '');
        final playing = playingUrl == url;
        content = InkWell(
          onTap: () => onPlayVoice(url),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(playing ? Icons.stop_circle : Icons.play_circle_fill,
                  color: mine ? Palette.marigold : Palette.navy, size: 32),
              const SizedBox(width: 8),
              Text(playing ? 'Playing…' : 'Voice note',
                  style: TextStyle(color: fg, fontSize: 14)),
            ],
          ),
        );
      default:
        content = Text(message.body,
            style: TextStyle(color: fg, fontSize: 14.5, height: 1.4));
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 3),
            bottomRight: Radius.circular(mine ? 3 : 14),
          ),
          border: mine ? null : Border.all(color: Palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 4),
            Text(
              '${message.senderName.isEmpty ? message.senderRole : message.senderName} · ${shortWhen(message.createdAt)}',
              style: text.bodySmall?.copyWith(
                fontSize: 10.5,
                color: mine ? Colors.white.withValues(alpha: 0.6) : Palette.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final TicketMessage message;
  const _MeetingCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String url = '';
    DateTime? at;
    try {
      final data = jsonDecode(message.body) as Map<String, dynamic>;
      url = data['url'] as String? ?? '';
      if (data['at'] != null) at = DateTime.parse(data['at'] as String).toLocal();
    } catch (_) {}

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Palette.slate,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.videocam_outlined, color: Palette.marigold, size: 28),
            const SizedBox(height: 8),
            Text('1-to-1 video call',
                style: text.titleMedium?.copyWith(color: Colors.white)),
            if (at != null) ...[
              const SizedBox(height: 2),
              Text(shortWhen(at),
                  style: text.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Palette.marigold,
                foregroundColor: Palette.dark,
                minimumSize: const Size(0, 42),
              ),
              onPressed: url.isEmpty
                  ? null
                  : () => launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.video_call, size: 20),
              label: const Text('Join call'),
            ),
          ],
        ),
      ),
    );
  }
}
