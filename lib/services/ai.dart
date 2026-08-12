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
  // The `-latest` alias always resolves to the current flash model, so this
  // keeps working when Google retires older versions.
  static const _model = 'gemini-flash-latest';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

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
          'AI is not configured yet — add a Gemini API key in lib/config.dart.');
    }
    final imageB64 = await renderSlideBase64(slide);
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'image/png', 'data': imageB64},
            },
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {'maxOutputTokens': 2048},
    });

    // Free-tier Gemini throws transient 503/429 under load — retry twice.
    http.Response response;
    var attempt = 0;
    do {
      response = await http.post(
        Uri.parse('$_endpoint?key=${AppConfig.geminiApiKey}'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      if (response.statusCode == 200) break;
      attempt++;
      if (attempt <= 2 &&
          (response.statusCode == 503 || response.statusCode == 429)) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      final detail = switch (response.statusCode) {
        400 || 401 || 403 => 'the API key was rejected',
        429 || 503 => 'the AI is busy right now — try again in a moment',
        _ => 'HTTP ${response.statusCode}',
      };
      throw Exception('Could not reach the AI service ($detail).');
    } while (true);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('The AI returned no answer — try again.');
    }
    final parts =
        (candidates.first['content']?['parts'] as List?) ?? const [];
    final text = parts
        .map((p) => (p as Map)['text'] as String? ?? '')
        .join('\n')
        .trim();
    if (text.isEmpty) {
      throw Exception('The AI returned no answer — try again.');
    }
    return text;
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
