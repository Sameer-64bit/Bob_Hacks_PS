import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../screens/board/board_controller.dart';
import '../screens/board/board_painter.dart';

/// Rasterises a slide to pixels the same way the app displays it:
/// white sheet -> optional background image (imported PDF page) -> strokes.
/// Shared by the PDF exports and the AI pipeline so what the model reads is
/// exactly what students see.
class SlideRaster {
  static final Map<String, ui.Image> _bgCache = {};

  static Future<ui.Image?> _background(String? url) async {
    if (url == null || url.isEmpty) return null;
    final cached = _bgCache[url];
    if (cached != null) return cached;
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      _bgCache[url] = frame.image;
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// PNG bytes of the composited slide at [scale] × the logical canvas size.
  static Future<Uint8List> png(BoardSlide slide, {double scale = 0.75}) async {
    final background = await _background(slide.backgroundUrl);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    final sheet =
        ui.Rect.fromLTWH(0, 0, kCanvasSize.width, kCanvasSize.height);
    canvas.drawRect(sheet, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    if (background != null) {
      canvas.drawImageRect(
        background,
        ui.Rect.fromLTWH(0, 0, background.width.toDouble(),
            background.height.toDouble()),
        sheet,
        ui.Paint(),
      );
    }
    for (final stroke in slide.strokes) {
      paintStroke(canvas, stroke);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (kCanvasSize.width * scale).round(),
      (kCanvasSize.height * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// Base64 of a rendered slide — encoded off the UI thread, with a frame
  /// yield so long multi-slide loops can't freeze the app.
  static Future<String> pngBase64(BoardSlide slide, {double scale = 0.5}) async {
    final bytes = await png(slide, scale: scale);
    await Future<void>.delayed(Duration.zero); // let a frame through
    return compute(_encodeBase64, bytes);
  }
}

String _encodeBase64(Uint8List bytes) => base64Encode(bytes);
