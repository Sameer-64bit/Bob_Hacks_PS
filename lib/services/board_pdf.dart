import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../screens/board/board_controller.dart';
import '../screens/board/board_painter.dart';

/// Turns the whiteboard into a shareable PDF — one page per non-empty
/// slide — and opens the platform share/download dialog.
class BoardPdf {
  /// Renders one slide's strokes to a PNG at 3/4 canvas resolution
  /// (1440×810 — crisp in a PDF without bloating the file).
  static Future<Uint8List> slidePng(BoardSlide slide) => _slidePng(slide);

  static Future<Uint8List> _slidePng(BoardSlide slide) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const scale = 0.75;
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
    return bytes!.buffer.asUint8List();
  }

  /// Builds the PDF from every non-empty slide. Returns null when there is
  /// nothing to export.
  static Future<Uint8List?> build({
    required List<BoardSlide> slides,
    required String title,
  }) async {
    final nonEmpty = slides.where((s) => s.strokes.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return null;

    final doc = pw.Document(title: title);
    // 16:9 pages matching the board, with a slim footer.
    const pageFormat = PdfPageFormat(
        1920 * PdfPageFormat.point / 2, 1080 * PdfPageFormat.point / 2);

    for (var i = 0; i < nonEmpty.length; i++) {
      final png = await _slidePng(nonEmpty[i]);
      final image = pw.MemoryImage(png);
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
              pw.Positioned(
                bottom: 10,
                left: 16,
                child: pw.Text(
                  title,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColor.fromInt(0xFF8A857C)),
                ),
              ),
              pw.Positioned(
                bottom: 10,
                right: 16,
                child: pw.Text(
                  'Slide ${i + 1} of ${nonEmpty.length}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColor.fromInt(0xFF8A857C)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Builds and opens the native share sheet (mobile) / download (web).
  /// Returns false when every slide was empty.
  static Future<bool> share({
    required List<BoardSlide> slides,
    required String title,
    required String fileName,
  }) async {
    final bytes = await build(slides: slides, title: title);
    if (bytes == null) return false;
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    return true;
  }
}
