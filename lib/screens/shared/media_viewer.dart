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
import '../../theme.dart';
import '../../widgets/common.dart';

/// Downloads, decrypts and plays class media strictly inside the app —
/// the blob in storage is AES ciphertext, useless outside Kaksha.
class MediaViewerScreen extends StatefulWidget {
  final ClassMedia media;
  const MediaViewerScreen({super.key, required this.media});

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  VideoPlayerController? _video;
  final _audio = AudioPlayer();
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _load();
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
              child: VideoPlayer(video),
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
