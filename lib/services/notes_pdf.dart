import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../models/models3.dart';
import 'board_pdf.dart';

/// Builds the class-notes PDF: cover page (overview, key concepts, terms)
/// followed by one page per slide with its image and generated summary.
class NotesPdf {
  /// Best-effort Noto font for the language so Indic scripts render.
  /// Returns null when the script isn't covered — caller falls back to
  /// the untranslated (English) text.
  static Future<pw.Font?> _fontFor(String code) async {
    try {
      switch (code) {
        case 'hi' || 'mr' || 'ne':
          return await PdfGoogleFonts.notoSansDevanagariRegular();
        case 'bn' || 'as':
          return await PdfGoogleFonts.notoSansBengaliRegular();
        case 'ta':
          return await PdfGoogleFonts.notoSansTamilRegular();
        case 'te':
          return await PdfGoogleFonts.notoSansTeluguRegular();
        case 'gu':
          return await PdfGoogleFonts.notoSansGujaratiRegular();
        case 'pa':
          return await PdfGoogleFonts.notoSansGurmukhiRegular();
        case 'kn':
          return await PdfGoogleFonts.notoSansKannadaRegular();
        case 'ml':
          return await PdfGoogleFonts.notoSansMalayalamRegular();
        case 'ur' || 'ar':
          return await PdfGoogleFonts.notoSansArabicRegular();
        case 'en' || 'es' || 'fr' || 'de':
          return await PdfGoogleFonts.notoSansRegular();
        default:
          return null;
      }
    } catch (_) {
      return null; // offline / unsupported — use built-in font + English
    }
  }

  static bool needsCustomFont(String code) =>
      !{'en', 'es', 'fr', 'de'}.contains(code);

  static Future<Uint8List> build({
    required ClassNotes notes,
    required List<BoardSlide> slides,
    required String languageCode,
  }) async {
    final font = await _fontFor(languageCode);
    final theme = font == null
        ? null
        : pw.ThemeData.withFont(base: font, bold: font);

    final doc = pw.Document(title: notes.title, theme: theme);

    pw.Widget heading(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF16324F))),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Text(notes.title,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Generated class notes · Kaksha',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColor.fromInt(0xFF8A857C))),
          heading('Overview'),
          pw.Text(notes.overview, style: const pw.TextStyle(fontSize: 11)),
          if (notes.simplifiedSummary.isNotEmpty) ...[
            heading('In one line'),
            pw.Text(notes.simplifiedSummary,
                style: const pw.TextStyle(fontSize: 11)),
          ],
          if (notes.keyConcepts.isNotEmpty) ...[
            heading('Key concepts'),
            for (final c in notes.keyConcepts)
              pw.Bullet(
                  text: '${c.term}: ${c.definition}',
                  style: const pw.TextStyle(fontSize: 10.5)),
          ],
          if (notes.technicalTerms.isNotEmpty) ...[
            heading('Technical terms'),
            for (final t in notes.technicalTerms)
              pw.Bullet(
                  text: '${t.term}: ${t.definition}',
                  style: const pw.TextStyle(fontSize: 10.5)),
          ],
        ],
      ),
    );

    for (final note in notes.perSlide) {
      pw.MemoryImage? image;
      if (note.index < slides.length &&
          (slides[note.index].strokes.isNotEmpty ||
              slides[note.index].backgroundUrl != null)) {
        image = pw.MemoryImage(await BoardPdf.slidePng(slides[note.index]));
      }
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(note.title,
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              if (image != null)
                pw.Container(
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: const PdfColor.fromInt(0xFFE6E1D6))),
                  child: pw.Image(image,
                      height: 250, fit: pw.BoxFit.contain),
                ),
              heading('Summary'),
              pw.Text(note.summary, style: const pw.TextStyle(fontSize: 11)),
              if (note.transcript.isNotEmpty) ...[
                heading('What the teacher said'),
                pw.Expanded(
                  child: pw.Text(note.transcript,
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColor.fromInt(0xFF4A4640)),
                      overflow: pw.TextOverflow.clip),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return doc.save();
  }
}
