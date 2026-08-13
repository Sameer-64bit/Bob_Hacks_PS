import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/languages.dart';
import '../../models/models.dart';
import '../../models/models3.dart';
import '../../screens/board/board_painter.dart';
import '../../services/notes_pdf.dart';
import '../../services/repository.dart';
import '../../services/translator.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The generated class notes: overview, key concepts, and one card per
/// slide with its image, summary and "view slide summary" expansion.
/// Notes are shown in the student's default language (translated from the
/// English the pipeline produces) and can be opened as a PDF in-app.
class NotesScreen extends StatefulWidget {
  final ClassNotes notes;
  final Classroom classroom;
  final String languageCode;

  const NotesScreen({
    super.key,
    required this.notes,
    required this.classroom,
    required this.languageCode,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<BoardSlide> _slides = [];
  ClassNotes? _translated;
  bool _translating = false;

  ClassNotes get _shown => _translated ?? widget.notes;

  @override
  void initState() {
    super.initState();
    repo
        .loadSlides(widget.classroom.id)
        .then((s) => mounted ? setState(() => _slides = s) : null)
        .catchError((_) {});
    _translate();
  }

  Future<void> _translate() async {
    final code = widget.languageCode;
    if (code == 'en') return;
    setState(() => _translating = true);
    try {
      final n = widget.notes;
      Future<String> t(String s) => Translator.translate(s, code);
      final translated = ClassNotes(
        id: n.id,
        classroomId: n.classroomId,
        status: n.status,
        progress: n.progress,
        stage: n.stage,
        createdAt: n.createdAt,
        title: n.title,
        overview: await t(n.overview),
        simplifiedSummary: await t(n.simplifiedSummary),
        keyConcepts: [
          for (final c in n.keyConcepts)
            ConceptNote(term: c.term, definition: await t(c.definition)),
        ],
        technicalTerms: [
          for (final c in n.technicalTerms)
            ConceptNote(term: c.term, definition: await t(c.definition)),
        ],
        perSlide: [
          for (final s in n.perSlide)
            SlideNote(
              index: s.index,
              title: s.title,
              summary: await t(s.summary),
              transcript: s.transcript, // spoken words stay as spoken
            ),
        ],
      );
      if (mounted) setState(() => _translated = translated);
    } catch (_) {
      // Translation is best-effort — English notes still show.
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _openPdf() async {
    final code = widget.languageCode;
    // Use translated text when we have a font for the script, else English.
    final forPdf =
        (NotesPdf.needsCustomFont(code) && _translated == null) || code == 'en'
            ? widget.notes
            : (_translated ?? widget.notes);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(_shown.title, overflow: TextOverflow.ellipsis)),
        body: PdfPreview(
          build: (_) => NotesPdf.build(
            notes: forPdf,
            slides: _slides,
            languageCode: identical(forPdf, widget.notes) ? 'en' : code,
          ),
          canChangeOrientation: false,
          canChangePageFormat: false,
          pdfFileName:
              'kaksha-notes-${widget.classroom.code.toLowerCase()}.pdf',
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notes = _shown;
    final language = languageByCode(widget.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class notes'),
        actions: [
          if (_translating)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Palette.faint),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Open PDF'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Palette.navy,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notes.title,
                        style: text.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(notes.overview,
                        style: text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 10),
                    PillBadge(
                      label:
                          '${language.native} · ${shortWhenFromDate(notes.createdAt)}',
                      color: Colors.white.withValues(alpha: 0.12),
                      textColor: Colors.white,
                    ),
                  ],
                ),
              ),
              if (notes.simplifiedSummary.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('In one line'),
                const SizedBox(height: 8),
                Text(notes.simplifiedSummary, style: text.bodyLarge),
              ],
              if (notes.keyConcepts.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('Key concepts'),
                const SizedBox(height: 8),
                for (final c in notes.keyConcepts) _ConceptTile(concept: c),
              ],
              if (notes.technicalTerms.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('Technical terms'),
                const SizedBox(height: 8),
                for (final c in notes.technicalTerms) _ConceptTile(concept: c),
              ],
              const SizedBox(height: 20),
              const SectionTitle('Slides'),
              const SizedBox(height: 8),
              for (final slide in notes.perSlide) ...[
                _SlideNoteCard(
                  note: slide,
                  boardSlide:
                      slide.index < _slides.length ? _slides[slide.index] : null,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

String shortWhenFromDate(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${t.day} ${months[t.month - 1]}';
}

class _ConceptTile extends StatelessWidget {
  final ConceptNote concept;
  const _ConceptTile({required this.concept});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: Palette.marigold, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: text.bodyMedium,
                children: [
                  TextSpan(
                      text: '${concept.term} — ',
                      style: text.titleMedium?.copyWith(fontSize: 14)),
                  TextSpan(text: concept.definition),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideNoteCard extends StatefulWidget {
  final SlideNote note;
  final BoardSlide? boardSlide;
  const _SlideNoteCard({required this.note, required this.boardSlide});

  @override
  State<_SlideNoteCard> createState() => _SlideNoteCardState();
}

class _SlideNoteCardState extends State<_SlideNoteCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final slide = widget.boardSlide;
    return Container(
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slide != null && slide.strokes.isNotEmpty)
            SlideThumbnail(slide: slide),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child:
                            Text(widget.note.title, style: text.titleMedium)),
                    TextButton.icon(
                      onPressed: () => setState(() => _open = !_open),
                      icon: Icon(
                          _open ? Icons.expand_less : Icons.notes_outlined,
                          size: 18),
                      label: Text(_open ? 'Hide summary' : 'View summary'),
                    ),
                  ],
                ),
                if (_open) ...[
                  Text(widget.note.summary, style: text.bodyLarge),
                  if (widget.note.transcript.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.paper,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHAT THE TEACHER SAID',
                              style: text.bodySmall?.copyWith(
                                  fontSize: 10, letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          Text(widget.note.transcript,
                              style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
