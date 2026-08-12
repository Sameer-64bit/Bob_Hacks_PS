import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import '../screens/board/board_controller.dart';
import '../screens/board/board_painter.dart';

/// Gemini-powered slide helpers: translate the writing on a slide into the
/// student's language, or describe what's on it.
class SlideAi {
  static const _endpoint = 'http://172.18.7.129:5000/generate';

  /// Renders a slide's strokes to a PNG (half canvas resolution keeps the
  /// payload small while staying readable).
  static Future<String> renderSlideBase64(BoardSlide slide) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const scale = 0.5;
    canvas.scale(scale);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, kCanvasSize.width, kCanvasSize.height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    for (final stroke in slide.strokes) {
      paintStroke(canvas, stroke);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (kCanvasSize.width * scale).round(),
      (kCanvasSize.height * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(bytes!.buffer.asUint8List());
  }

  /// The raw HTTP call to the proxy — reusable for translation, description, etc.
  static Future<String> _ask(BoardSlide slide, String prompt) async {
    final imageB64 = await renderSlideBase64(slide);
    final body = jsonEncode({
      'image_b64': imageB64,
      'prompt': prompt,
    });

    http.Response response;
    var attempt = 0;
    do {
      response = await http.post(
        Uri.parse(_endpoint),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      if (response.statusCode == 200) break;
      attempt++;
      if (attempt <= 2 && response.statusCode >= 500) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      throw Exception('Python proxy error (${response.statusCode}): ${response.body}');
    } while (true);
    
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['text'] as String;
  }

  /// Translates whatever is written on the slide into [languageName].
  static Future<String> translate(BoardSlide slide, String languageName) {
    return _ask(
      slide,
      'This is a photo of a classroom whiteboard slide. Read everything '
      'written on it and translate it into $languageName. Keep the layout '
      'sense (headings, lists, formulas) and keep math/symbols as they are. '
      'Reply with ONLY the translation. If there is no readable text, say '
      'so briefly in $languageName.',
    );
  }

  /// Describes the slide's content in [languageName].
  static Future<String> describe(BoardSlide slide, String languageName) {
    return _ask(
      slide,
      'This is a classroom whiteboard slide. Describe clearly for a student '
      'what is drawn and written on it — the topic, any diagrams, and the '
      'key points. Be concise (under 150 words). Reply in $languageName.',
    );
  }
}
