import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';

import '../../data/languages.dart';
import '../../models/models3.dart';
import '../../services/ai.dart';
import '../../services/repository.dart';
import '../../services/repository5.dart';
import '../../services/translator.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Downloads, decrypts and plays class media strictly inside the app —
/// the blob in storage is AES ciphertext, useless outside Kaksha.
/// Lecture recordings show subtitles in [languageCode] while playing.
class MediaViewerScreen extends StatefulWidget {
  final ClassMedia media;
  final String languageCode;
  const MediaViewerScreen(
      {super.key, required this.media, this.languageCode = 'en'});

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  VideoPlayerController? _video;
  final _audio = AudioPlayer();
  bool _audioPlaying = false;

  bool _wasPlaying = false;

  // Lecture subtitles + dubbing
  List<LiveCaption> _captions = [];
  final Map<String, String> _subtitleCache = {};
  double _positionS = 0;
  final FlutterTts _tts = FlutterTts();
  bool _dubbing = false;
  String? _lastSpokenId;
  String _notesContext = '';
  late String _status = widget.media.transcriptStatus;
  Timer? _captionPoll;
  bool _regenerating = false;

  /// Re-runs transcription for this media (e.g. an upload from before the
  /// subtitles table existed, or a failed job). Uses the already-decrypted
  /// bytes; captions appear via the poll when the server finishes.
  Future<void> _generateSubtitles() async {
    final bytes = _bytes;
    if (bytes == null || _regenerating) return;
    setState(() {
      _regenerating = true;
      _status = 'processing';
    });
    try {
      await repo.startLectureMediaJob(
        mediaId: widget.media.id,
        noteId: null,
        language: 'en',
        title: widget.media.title,
        mediaBytes: bytes,
        mediaExt: widget.media.mime.startsWith('audio/') ? 'm4a' : 'mp4',
      );
      _startCaptionPoll();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'failed');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not start subtitles: $e')));
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  void _startCaptionPoll() {
    _captionPoll?.cancel();
    _captionPoll = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final captions = await repo.listMediaCaptions(widget.media.id);
        if (captions.isNotEmpty && mounted) {
          setState(() {
            _captions = captions;
            _status = 'ready';
          });
          _captionPoll?.cancel();
        }
      } catch (_) {}
    });
  }

  static const _ttsLocales = {
    'hi': 'hi-IN', 'bn': 'bn-IN', 'ta': 'ta-IN', 'te': 'te-IN',
    'mr': 'mr-IN', 'gu': 'gu-IN', 'pa': 'pa-IN', 'kn': 'kn-IN',
    'ml': 'ml-IN', 'ur': 'ur-PK', 'ne': 'ne-NP', 'es': 'es-ES',
    'fr': 'fr-FR', 'de': 'de-DE', 'ar': 'ar-SA', 'zh-CN': 'zh-CN',
    'ja': 'ja-JP', 'en': 'en-IN',
  };

  Future<void> _toggleDub() async {
    final video = _video;
    if (_dubbing) {
      await _tts.stop();
      await video?.setVolume(1);
      setState(() => _dubbing = false);
      return;
    }
    await _tts.setLanguage(
        _ttsLocales[widget.languageCode] ?? widget.languageCode);
    await _tts.setSpeechRate(0.5);
    await video?.setVolume(0); // mute the original — the dub speaks instead
    setState(() => _dubbing = true);
  }

  /// Speaks the current caption (translated) when dubbing is on.
  Future<void> _maybeSpeak() async {
    if (!_dubbing) return;
    final caption = _currentCaption;
    if (caption == null || caption.id == _lastSpokenId) return;
    _lastSpokenId = caption.id;
    final key = '${caption.id}:${widget.languageCode}';
    final text = _subtitleCache[key] ??
        await Translator.translateSafe(caption.text, widget.languageCode);
    _subtitleCache[key] = text;
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.media.sessionId != null) {
      repo.listMediaCaptions(widget.media.id).then((c) {
        if (!mounted) return;
        setState(() {
          _captions = c;
          if (c.isNotEmpty) _status = 'ready';
        });
        // Still transcribing on the server? Keep checking until they land.
        if (c.isEmpty && _status == 'processing') _startCaptionPoll();
      }).catchError((_) {});
    }
    _audio.onPositionChanged.listen((p) {
      final s = p.inMilliseconds / 1000.0;
      // Throttle: rebuilding the whole screen on every tick causes jank.
      if (mounted && widget.media.isAudio && (s - _positionS).abs() >= 0.25) {
        setState(() => _positionS = s);
        _maybeSpeak();
      }
    });
    // The chatbot teaches from the class notes too, not just the audio.
    final sessionId = widget.media.sessionId;
    if (sessionId != null) {
      repo.notesForSession(sessionId).then((notes) {
        if (notes == null || !mounted) return;
        setState(() => _notesContext = [
              notes.overview,
              for (final s in notes.perSlide) '${s.title}: ${s.summary}',
            ].join('\n'));
      }).catchError((_) {});
    }
  }

  LiveCaption? get _currentCaption {
    for (final c in _captions) {
      if (_positionS >= c.startS && _positionS <= c.endS + 0.4) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _captionPoll?.cancel();
    _tts.stop();
    _video?.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await repo.fetchClassMedia(widget.media);
      if (!mounted) return;
      if (widget.media.isVideo && !kIsWeb) {
        // video_player needs a file — write the decrypted bytes to the
        // app's private cache (removed on app-data clear).
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/kaksha-media-${widget.media.id}.mp4');
        await file.writeAsBytes(bytes, flush: true);
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        controller.addListener(() {
          final s = controller.value.position.inMilliseconds / 1000.0;
          // The video reports position ~60x/second; rebuilding the whole
          // screen (subtitles + chat) that often froze low-end phones.
          if (mounted &&
              ((s - _positionS).abs() >= 0.25 ||
                  controller.value.isPlaying != _wasPlaying)) {
            _wasPlaying = controller.value.isPlaying;
            setState(() => _positionS = s);
            _maybeSpeak();
          }
        });
        _video = controller;
      }
      if (mounted) setState(() => _bytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Scaffold(
      appBar: AppBar(
        title: Text(media.title, overflow: TextOverflow.ellipsis),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: PillBadge(
                label: 'Encrypted · in-app only',
                icon: Icons.lock_outline,
              ),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not open media: $_error',
                    textAlign: TextAlign.center),
              ),
            )
          : _bytes == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Palette.navy),
                      SizedBox(height: 14),
                      Text('Decrypting…'),
                    ],
                  ),
                )
              : _content(),
    );
  }

  Widget _content() {
    final media = widget.media;
    final bytes = _bytes!;

    if (media.isImage) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.memory(bytes)),
      );
    }
    if (media.isPdf) {
      return PdfPreview(
        build: (_) async => bytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: false,
        allowSharing: false, // stays inside the app
        canDebug: false,
      );
    }
    if (media.isAudio) {
      return Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.graphic_eq, size: 56, color: Palette.navy),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back 10 seconds',
                onPressed: () => _audio.seek(Duration(
                    seconds: (_positionS - 10).clamp(0, 1e9).toInt())),
                icon: const Icon(Icons.replay_10, color: Palette.dark),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Palette.navy),
                onPressed: () async {
                  if (_audioPlaying) {
                    await _audio.pause();
                    setState(() => _audioPlaying = false);
                  } else {
                    await _audio.play(BytesSource(bytes));
                    setState(() => _audioPlaying = true);
                    _audio.onPlayerComplete.first.then((_) {
                      if (mounted) setState(() => _audioPlaying = false);
                    });
                  }
                },
                icon: Icon(
                    _audioPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Forward 10 seconds',
                onPressed: () => _audio
                    .seek(Duration(seconds: (_positionS + 10).toInt())),
                icon: const Icon(Icons.forward_10, color: Palette.dark),
              ),
            ],
          ),
          if (_captions.isNotEmpty || media.sessionId != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SubtitleBar(
                caption: _currentCaption,
                status: _status,
                languageCode: widget.languageCode,
                cache: _subtitleCache,
              ),
            ),
            if (_captions.isEmpty && _status != 'processing')
              TextButton.icon(
                onPressed: _regenerating ? null : _generateSubtitles,
                icon: const Icon(Icons.subtitles_outlined, size: 16),
                label: const Text('Generate subtitles'),
              ),
          ],
          if (media.sessionId != null)
            Expanded(
              child: _LectureChat(
                captions: _captions,
                languageCode: widget.languageCode,
                title: media.title,
                notesContext: _notesContext,
              ),
            )
          else
            const Spacer(),
        ],
      );
    }
    if (media.isVideo) {
      final video = _video;
      if (video == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Video playback works in the Android/iOS app — open Kaksha on '
              'your phone to watch this.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Column(
        children: [
          ConstrainedBox(
            // Cap the video height so controls + chat always fit on screen
            // (landscape videos were overflowing the phone display).
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42),
            child: AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(video),
                  if (_captions.isNotEmpty || media.sessionId != null)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: _SubtitleBar(
                        caption: _currentCaption,
                        status: _status,
                        languageCode: widget.languageCode,
                        cache: _subtitleCache,
                        onDark: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _VideoControls(
            video: video,
            dubbing: _dubbing,
            onToggleDub:
                media.sessionId != null && widget.languageCode != 'en'
                    ? _toggleDub
                    : null,
          ),
          if (media.sessionId != null &&
              _captions.isEmpty &&
              _status != 'processing')
            TextButton.icon(
              onPressed: _regenerating ? null : _generateSubtitles,
              icon: const Icon(Icons.subtitles_outlined, size: 16),
              label: Text(_regenerating
                  ? 'Starting…'
                  : 'Generate subtitles (transcribe this lecture)'),
            ),
          if (media.sessionId != null)
            Expanded(
              child: _LectureChat(
                captions: _captions,
                languageCode: widget.languageCode,
                title: media.title,
                notesContext: _notesContext,
              ),
            )
          else
            const Spacer(),
        ],
      );
    }
    return const Center(child: Text('Unsupported media type.'));
  }
}

/// Play/pause, ±10 s, and a scrubber with elapsed/total time.
class _VideoControls extends StatelessWidget {
  final VideoPlayerController video;
  final bool dubbing;
  final VoidCallback? onToggleDub;
  const _VideoControls(
      {required this.video, this.dubbing = false, this.onToggleDub});

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = video.value;
    final duration = value.duration;
    final position = value.position;
    return Container(
      color: Palette.card,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_fmt(position),
                  style: const TextStyle(fontSize: 11, color: Palette.faint)),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds
                      .clamp(0, duration.inMilliseconds)
                      .toDouble(),
                  max: duration.inMilliseconds.toDouble().clamp(1, 1e12),
                  activeColor: Palette.navy,
                  inactiveColor: Palette.line,
                  onChanged: (ms) =>
                      video.seekTo(Duration(milliseconds: ms.round())),
                ),
              ),
              Text(_fmt(duration),
                  style: const TextStyle(fontSize: 11, color: Palette.faint)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back 10 seconds',
                onPressed: () => video.seekTo(
                    position - const Duration(seconds: 10)),
                icon: const Icon(Icons.replay_10, color: Palette.dark),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Palette.navy),
                tooltip: value.isPlaying ? 'Pause' : 'Play',
                onPressed: () =>
                    value.isPlaying ? video.pause() : video.play(),
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Forward 10 seconds',
                onPressed: () => video.seekTo(
                    position + const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10, color: Palette.dark),
              ),
              if (onToggleDub != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: dubbing
                      ? 'Stop dubbed audio (original sound returns)'
                      : 'Dub the lecture into your language (spoken aloud)',
                  child: IconButton(
                    onPressed: onToggleDub,
                    icon: Icon(
                      dubbing
                          ? Icons.record_voice_over
                          : Icons.voice_over_off_outlined,
                      color:
                          dubbing ? Palette.marigold : Palette.faint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "Ask about this lecture" — an AI assistant grounded in the lecture's
/// transcript; answers arrive in the student's language.
class _LectureChat extends StatefulWidget {
  final List<LiveCaption> captions;
  final String languageCode;
  final String title;
  final String notesContext;

  const _LectureChat({
    required this.captions,
    required this.languageCode,
    required this.title,
    this.notesContext = '',
  });

  @override
  State<_LectureChat> createState() => _LectureChatState();
}

class _LectureChatState extends State<_LectureChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool me, String text})> _messages = [];
  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add((me: true, text: question));
      _thinking = true;
    });
    try {
      final transcript =
          widget.captions.map((c) => c.text).join(' ');
      final answer = await SlideAi.askLecture(
        transcript: transcript.isEmpty ? widget.title : transcript,
        question: question,
        target: languageByCode(widget.languageCode),
        notesContext: widget.notesContext,
        // Follow-up questions keep their thread: send the recent turns.
        history: [
          for (final m
              in _messages.sublist(0, _messages.length - 1).reversed.take(4).toList().reversed)
            {'role': m.me ? 'user' : 'assistant', 'text': m.text},
        ],
      );
      if (mounted) setState(() => _messages.add((me: false, text: answer)));
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(
            (me: false, text: e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: Palette.marigold),
                const SizedBox(width: 8),
                Text('Ask about this lecture',
                    style: text.titleMedium?.copyWith(fontSize: 13.5)),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask anything — answers come from this lecture\'s audio.',
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: [
                      for (final m in _messages)
                        Align(
                          alignment: m.me
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            constraints: const BoxConstraints(maxWidth: 420),
                            decoration: BoxDecoration(
                              color: m.me ? Palette.navy : Palette.paper,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              m.text,
                              style: TextStyle(
                                color: m.me ? Colors.white : Palette.dark,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      if (_thinking)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Palette.faint),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. What did sir say about recursion?',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style:
                        IconButton.styleFrom(backgroundColor: Palette.dark),
                    onPressed: _thinking ? null : _send,
                    icon: const Icon(Icons.arrow_upward,
                        color: Colors.white, size: 20),
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

/// One subtitle line, translated into the viewer's language on the fly
/// (each line is translated once and cached).
class _SubtitleBar extends StatefulWidget {
  final LiveCaption? caption;
  final String status;
  final String languageCode;
  final Map<String, String> cache;
  final bool onDark;

  const _SubtitleBar({
    required this.caption,
    required this.status,
    required this.languageCode,
    required this.cache,
    this.onDark = false,
  });

  @override
  State<_SubtitleBar> createState() => _SubtitleBarState();
}

class _SubtitleBarState extends State<_SubtitleBar> {
  String? _shown;

  @override
  void didUpdateWidget(covariant _SubtitleBar old) {
    super.didUpdateWidget(old);
    if (old.caption?.id != widget.caption?.id) _resolve();
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final caption = widget.caption;
    if (caption == null) {
      setState(() => _shown = null);
      return;
    }
    if (widget.languageCode == 'en') {
      setState(() => _shown = caption.text);
      return;
    }
    final key = '${caption.id}:${widget.languageCode}';
    final cached = widget.cache[key];
    if (cached != null) {
      setState(() => _shown = cached);
      return;
    }
    setState(() => _shown = caption.text); // original until translated
    try {
      final t = await Translator.translate(caption.text, widget.languageCode);
      widget.cache[key] = t;
      if (mounted && widget.caption?.id == caption.id) {
        setState(() => _shown = t);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final text = _shown ??
        (widget.status == 'processing'
            ? 'Subtitles are being prepared…'
            : widget.status == 'failed'
                ? 'Subtitles unavailable.'
                : '');
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: widget.onDark
            ? Colors.black.withValues(alpha: 0.65)
            : Palette.paper,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: widget.onDark ? Colors.white : Palette.dark,
          fontSize: 14.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
