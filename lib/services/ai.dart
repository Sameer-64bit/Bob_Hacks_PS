import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import '../screens/board/board_controller.dart';
import '../screens/board/board_painter.dart';

/// Claude-powered slide helpers: translate the writing on a slide into the
/// student's language, or describe what's on it.
class SlideAi {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-5';

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

  static Future<String> _ask(BoardSlide slide, String prompt) async {
    if (!AppConfig.hasAi) {
      throw Exception(
          'AI is not configured yet — add an Anthropic API key in lib/config.dart.');
    }
    final imageB64 = await renderSlideBase64(slide);
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': AppConfig.anthropicApiKey,
        'anthropic-version': '2023-06-01',
        // Required for calls made directly from a browser build.
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 1024,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': imageB64,
                },
              },
              {'type': 'text', 'text': prompt},
            ],
          }
        ],
      }),
    );
    if (response.statusCode != 200) {
      final detail = switch (response.statusCode) {
        401 => 'the API key was rejected',
        429 => 'rate limited — try again in a moment',
        _ => 'HTTP ${response.statusCode}',
      };
      throw Exception('Could not reach the AI service ($detail).');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['content'] as List;
    return content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n')
        .trim();
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
