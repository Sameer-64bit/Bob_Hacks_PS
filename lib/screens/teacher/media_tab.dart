import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../models/models2.dart';
import '../../models/models3.dart';
import '../../services/ai.dart';
import '../../services/repository.dart';
import '../../services/repository3.dart';
import '../../services/repository4.dart';
import '../../services/repository5.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/media_viewer.dart';

/// Teacher uploads class media (videos, audio, PDFs, images). Files are
/// gzip-compressed and AES-encrypted before they reach Supabase, so the
/// stored blob only plays inside the app.
class TeacherMediaTab extends StatefulWidget {
  final Teacher teacher;
  final List<Classroom> classrooms;

  const TeacherMediaTab(
      {super.key, required this.teacher, required this.classrooms});

  @override
  State<TeacherMediaTab> createState() => _TeacherMediaTabState();
}

class _TeacherMediaTabState extends State<TeacherMediaTab> {
  static const _maxBytes = 50 * 1024 * 1024; // keep well under the 1 GB pool

  Classroom? _classroom;
  List<ClassMedia> _media = [];
  bool _loading = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.classrooms.isNotEmpty) {
      _classroom = widget.classrooms.first;
      _load();
    }
  }

  Future<void> _load() async {
    final classroom = _classroom;
    if (classroom == null) return;
    setState(() => _loading = true);
    try {
      final list = await repo.listClassMedia(classroom.id);
      if (!mounted) return;
      setState(() {
        _media = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  static String _mimeFor(String? extension) => switch (extension) {
        'mp4' || 'mov' || 'm4v' => 'video/mp4',
        'mp3' => 'audio/mpeg',
        'm4a' || 'aac' => 'audio/mp4',
        'wav' => 'audio/wav',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };

  /// For lecture recordings: which class period does this video belong to?
  Future<BoardSession?> _pickSession(Classroom classroom) async {
    final sessions = (await repo.classroomSessions(classroom.id))
        .where((s) => !s.isActive)
        .toList();
    if (sessions.isEmpty) {
      if (mounted) {
        showError(context,
            'No ended class sessions yet — end a class first, then upload its recording.');
      }
      return null;
    }
    if (!mounted) return null;
    return showDialog<BoardSession>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Which class is this recording from?'),
        children: [
          for (final s in sessions.take(8))
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(s),
              child: Text(shortWhen(s.startedAt)),
            ),
        ],
      ),
    );
  }

  Future<void> _upload() async {
    final classroom = _classroom;
    if (classroom == null || _uploading) return;
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      final file = picked?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      if (bytes.length > _maxBytes) {
        if (mounted) {
          showError(context,
              'Keep files under 50 MB — compress the video before uploading.');
        }
        return;
      }
      final mime = _mimeFor(file.extension?.toLowerCase());
      final isPlayable =
          mime.startsWith('video/') || mime.startsWith('audio/');

      // A video/audio file can be THE lecture recording: then its audio is
      // transcribed once (player subtitles) and the class notes are
      // synthesised from that transcript + the session's slides.
      BoardSession? session;
      if (isPlayable && mounted) {
        final asLecture = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Is this the class lecture recording?'),
            content: const Text(
                'Lecture recordings get subtitles in every student\'s '
                'language, and the class notes are generated from their '
                'audio + the board slides.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Just media')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Lecture recording')),
            ],
          ),
        );
        if (asLecture == true) {
          session = await _pickSession(classroom);
          if (session == null) return; // cancelled / no sessions
        }
      }

      setState(() => _uploading = true);

      // Visible progress the whole way — encrypting a big video takes a
      // few seconds and used to look like a hang.
      final stage = ValueNotifier<String>('Compressing & encrypting…');
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: ValueListenableBuilder<String>(
              valueListenable: stage,
              builder: (_, value, __) => Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Palette.navy),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
          ),
        );
      }

      try {
        final mediaId = await repo.uploadClassMedia(
          classroomId: classroom.id,
          teacherId: widget.teacher.id,
          title: file.name,
          mime: mime,
          bytes: bytes,
          sessionId: session?.id,
          transcriptStatus: session != null ? 'processing' : 'none',
        );

        if (session != null) {
          // A lecture video UPDATES the notes that End class already made
          // for this session (or creates them if the class had none).
          stage.value = 'Preparing the class notes update…';
          var noteId = await repo.latestNoteIdForSession(session.id);
          if (noteId != null) {
            await repo.resetClassNotes(noteId);
          } else {
            noteId = await repo.createClassNotes(
              classroomId: classroom.id,
              language: 'en',
              sessionId: session.id,
            );
          }

          stage.value = 'Rendering the session slides…';
          final slides = await repo.loadSessionSlides(session.id);
          final pngs = <String>[];
          final strokeCounts = <int>[];
          for (final slide in slides) {
            pngs.add(await SlideAi.renderSlideBase64(slide));
            strokeCounts
                .add(slide.backgroundUrl != null ? 999 : slide.strokes.length);
            await Future<void>.delayed(Duration.zero); // keep the UI breathing
          }

          stage.value = 'Sending the lecture to the AI server…';
          await repo.startLectureMediaJob(
            mediaId: mediaId,
            noteId: noteId,
            language: 'en',
            title: 'Class notes · ${branchByKey(classroom.branch).short} · '
                '${shortWhen(session.startedAt)}',
            mediaBytes: bytes,
            mediaExt: file.extension?.toLowerCase() ?? 'mp4',
            slidePngsB64: pngs,
            strokeCounts: strokeCounts,
            slideMarks: session.slideMarks,
          );
        }
      } finally {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(session != null
                ? 'Lecture uploaded 🔒 — subtitles are being prepared and the '
                    'class notes are updating.'
                : 'Uploaded — compressed & encrypted, in-app only. 🔒')));
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (widget.classrooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyNote(
            icon: Icons.perm_media_outlined,
            title: 'No classrooms yet',
            body: 'Add classes to your weekly schedule first.',
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Classroom>(
                    // ignore: deprecated_member_use
                    value: _classroom,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classroom'),
                    items: [
                      for (final c in widget.classrooms)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                              '${branchByKey(c.branch).short} · ${yearName(c.year)} · ${c.code}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (c) {
                      setState(() => _classroom = c);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload, size: 18),
                  label: Text(_uploading ? 'Encrypting…' : 'Upload'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.navy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Files are compressed and AES-encrypted before upload — the '
                'stored copy cannot be played outside Kaksha. Max 50 MB per '
                'file; pre-compress videos.',
                style: text.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(color: Palette.navy)),
              )
            else if (_media.isEmpty)
              const EmptyNote(
                icon: Icons.perm_media_outlined,
                title: 'No media yet',
                body:
                    'Upload lecture videos, audio, PDFs or images — students '
                    'open them safely inside the app.',
              )
            else
              for (final media in _media) ...[
                Material(
                  color: Palette.card,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MediaViewerScreen(media: media))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            media.isVideo
                                ? Icons.movie_outlined
                                : media.isAudio
                                    ? Icons.audiotrack_outlined
                                    : media.isPdf
                                        ? Icons.picture_as_pdf_outlined
                                        : Icons.image_outlined,
                            color: Palette.slate,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(media.title,
                                    style: text.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text(
                                  '${_size(media.bytesOriginal)} · stored ${_size(media.bytesStored)} 🔒 · ${shortWhen(media.createdAt)}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () async {
                              try {
                                await repo.deleteClassMedia(media.id);
                                _load();
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Palette.faint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
