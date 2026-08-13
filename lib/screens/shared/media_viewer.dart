import 'dart:io' show File;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';

import '../../models/models3.dart';
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

  // Lecture subtitles
  List<LiveCaption> _captions = [];
  final Map<String, String> _subtitleCache = {};
  double _positionS = 0;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.media.sessionId != null) {
      repo
          .listMediaCaptions(widget.media.id)
          .then((c) => mounted ? setState(() => _captions = c) : null)
          .catchError((_) {});
    }
    _audio.onPositionChanged.listen((p) {
      if (mounted && widget.media.isAudio) {
        setState(() => _positionS = p.inMilliseconds / 1000.0);
      }
    });
  }

  LiveCaption? get _currentCaption {
    for (final c in _captions) {
      if (_positionS >= c.startS && _positionS <= c.endS + 0.4) return c;
    }
    return null;
  }

  @override
  void dispose() {
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
          if (mounted) {
            setState(() => _positionS =
                controller.value.position.inMilliseconds / 1000.0);
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq, size: 56, color: Palette.navy),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                if (_audioPlaying) {
                  await _audio.stop();
                  setState(() => _audioPlaying = false);
                } else {
                  await _audio.play(BytesSource(bytes));
                  setState(() => _audioPlaying = true);
                  _audio.onPlayerComplete.first.then((_) {
                    if (mounted) setState(() => _audioPlaying = false);
                  });
                }
              },
              icon: Icon(_audioPlaying ? Icons.stop : Icons.play_arrow),
              label: Text(_audioPlaying ? 'Stop' : 'Play'),
            ),
            if (_captions.isNotEmpty || media.sessionId != null) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _SubtitleBar(
                  caption: _currentCaption,
                  status: media.transcriptStatus,
                  languageCode: widget.languageCode,
                  cache: _subtitleCache,
                ),
              ),
            ],
          ],
        ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
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
                        status: media.transcriptStatus,
                        languageCode: widget.languageCode,
                        cache: _subtitleCache,
                        onDark: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => setState(() {
                video.value.isPlaying ? video.pause() : video.play();
              }),
              icon: Icon(
                  video.value.isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(video.value.isPlaying ? 'Pause' : 'Play'),
            ),
          ],
        ),
      );
    }
    return const Center(child: Text('Unsupported media type.'));
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
