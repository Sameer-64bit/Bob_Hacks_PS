import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/languages.dart';
import '../../models/models.dart';
import '../../models/models3.dart';
import '../../screens/board/board_painter.dart';
import '../../services/notes_pdf.dart';
import '../../services/repository.dart';
import '../../services/repository3.dart';
import '../../services/repository4.dart';
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

  /// Live language override — switching here retranslates immediately,
  /// no need to reopen the notes.
  String? _langOverride;
  String get _lang => _langOverride ?? widget.languageCode;

  ClassNotes get _shown => _translated ?? widget.notes;

  @override
  void initState() {
    super.initState();
    // Slides come from the exact board session this class used.
    final sessionId = widget.notes.sessionId;
    (sessionId != null
            ? repo.loadSessionSlides(sessionId)
            : repo.loadSlides(widget.classroom.id))
        .then((s) => mounted ? setState(() => _slides = s) : null)
        .catchError((_) {});
    _translate();
  }

  Future<void> _translate() async {
    final code = _lang;
    if (code == 'en') {
      setState(() => _translated = null);
      return;
    }

    // Translated once already? Use the cached copy — instant.
    final cached = widget.notes.translations[code];
    if (cached is Map) {
      setState(() => _translated =
          widget.notes.withNotesJson(cached.cast<String, dynamic>()));
      return;
    }

    setState(() => _translating = true);
    try {
      final n = widget.notes;

      // Bounded concurrency + per-field fallback: the free translator
      // rate-limits bursts, and one failed call must not leave the whole
      // page in English.
      final inputs = <String>[
        n.overview,
        n.simplifiedSummary,
        for (final c in n.keyConcepts) c.definition,
        for (final c in n.technicalTerms) c.definition,
        for (final s in n.perSlide) s.summary,
      ];
      final results = await Translator.translateAll(inputs, code);
      final allOk = () {
        var ok = 0;
        for (var i = 0; i < inputs.length; i++) {
          if (inputs[i].trim().isEmpty || results[i] != inputs[i]) ok++;
        }
        return ok >= inputs.length - 1; // tolerate one stubborn field
      }();
      if (_lang != code) return; // user switched again mid-flight
      var cursor = 0;
      String next() => results[cursor++];

      final overview = next();
      final simplified = next();
      final translated = ClassNotes(
        id: n.id,
        classroomId: n.classroomId,
        sessionId: n.sessionId,
        status: n.status,
        progress: n.progress,
        stage: n.stage,
        createdAt: n.createdAt,
        title: n.title,
        overview: overview,
        simplifiedSummary: simplified,
        keyConcepts: [
          for (final c in n.keyConcepts)
            ConceptNote(
                term: c.term,
                definition: next(),
                imageUrl: c.imageUrl,
                wiki: c.wiki),
        ],
        technicalTerms: [
          for (final c in n.technicalTerms)
            ConceptNote(
                term: c.term,
                definition: next(),
                imageUrl: c.imageUrl,
                wiki: c.wiki),
        ],
        perSlide: [
          for (final s in n.perSlide)
            SlideNote(
              index: s.index,
              title: s.title,
              summary: next(),
              transcript: s.transcript, // spoken words stay as spoken
              snippetUrl: s.snippetUrl,
            ),
        ],
      );
      if (mounted) setState(() => _translated = translated);
      // Cache for everyone — but only a fully-translated copy, never a
      // half-English one.
      if (allOk) {
        try {
          await repo.saveNotesTranslation(
              widget.notes.id, code, translated.notesJson());
        } catch (_) {}
      }
    } catch (_) {
      // Translation is best-effort — English notes still show.
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _openPdf() async {
    final code = _lang;
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
    final language = languageByCode(_lang);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class notes'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Notes language',
            icon: const Icon(Icons.translate, size: 20),
            initialValue: _lang,
            onSelected: (code) {
              setState(() {
                _langOverride = code;
                _translated = null;
              });
              _translate();
            },
            itemBuilder: (_) => [
              for (final l in kLanguages)
                PopupMenuItem(value: l.code, child: Text(l.native)),
            ],
          ),
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
              const SizedBox(height: 14),
              _StatRow(notes: notes),
              if (notes.simplifiedSummary.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('In one line'),
                const SizedBox(height: 8),
                Text(notes.simplifiedSummary, style: text.bodyLarge),
              ],
              if (_talkWords(notes).any((w) => w > 0)) ...[
                const SizedBox(height: 20),
                const SectionTitle('Where the class time went'),
                const SizedBox(height: 8),
                _TalkTimeChart(notes: notes),
              ],
              if (notes.perSlide.length > 1) ...[
                const SizedBox(height: 20),
                const SectionTitle('Lecture flow'),
                const SizedBox(height: 8),
                _LectureFlow(notes: notes),
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

List<int> _talkWords(ClassNotes notes) => [
      for (final s in notes.perSlide)
        s.transcript.trim().isEmpty
            ? 0
            : s.transcript.trim().split(RegExp(r'\s+')).length,
    ];

/// Headline numbers for the class, tile style.
class _StatRow extends StatelessWidget {
  final ClassNotes notes;
  const _StatRow({required this.notes});

  @override
  Widget build(BuildContext context) {
    final words = _talkWords(notes).fold<int>(0, (a, b) => a + b);
    final minutes = (words / 130).ceil(); // ~130 spoken words per minute
    final concepts =
        notes.keyConcepts.length + notes.technicalTerms.length;

    Widget tile(String value, String label, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.line),
            ),
            child: Column(
              children: [
                Icon(icon, size: 16, color: Palette.faint),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Palette.dark)),
                const SizedBox(height: 2),
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: Palette.faint)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('${notes.perSlide.length}', 'slides', Icons.layers_outlined),
        const SizedBox(width: 10),
        tile(words == 0 ? '—' : '~$minutes min', 'spoken',
            Icons.record_voice_over_outlined),
        const SizedBox(width: 10),
        tile('$concepts', 'concepts', Icons.lightbulb_outline),
      ],
    );
  }
}

/// How much the teacher spoke on each slide — single-hue horizontal bars,
/// baseline-anchored with rounded data ends and direct value labels.
class _TalkTimeChart extends StatelessWidget {
  final ClassNotes notes;
  const _TalkTimeChart({required this.notes});

  @override
  Widget build(BuildContext context) {
    final words = _talkWords(notes);
    final maxWords = words.fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < words.length; i++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: i == words.length - 1 ? 0 : 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text('Slide ${i + 1}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Palette.faint)),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: Palette.paper,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            height: 12,
                            width: words[i] == 0
                                ? 0
                                : (constraints.maxWidth *
                                        words[i] /
                                        maxWords)
                                    .clamp(4.0, constraints.maxWidth),
                            decoration: const BoxDecoration(
                              color: Palette.navy,
                              borderRadius: BorderRadius.horizontal(
                                  right: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      words[i] == 0 ? 'quiet' : '${words[i]} words',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 10.5, color: Palette.faint),
                    ),
                  ),
                ],
              ),
            ),
        ],
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

/// A visual map of the class: numbered steps through the slides.
class _LectureFlow extends StatelessWidget {
  final ClassNotes notes;
  const _LectureFlow({required this.notes});

  @override
  Widget build(BuildContext context) {
    final steps = notes.perSlide;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Palette.navy.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: Palette.navy.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 8,
                    backgroundColor: Palette.navy,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _stepLabel(steps[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Palette.navy),
                    ),
                  ),
                ],
              ),
            ),
            if (i < steps.length - 1)
              const Icon(Icons.arrow_forward,
                  size: 14, color: Palette.faint),
          ],
        ],
      ),
    );
  }

  String _stepLabel(SlideNote s) {
    final words = s.summary.split(RegExp(r'\s+'));
    final short = words.take(5).join(' ');
    return short.isEmpty ? s.title : short;
  }
}

class _ConceptTile extends StatelessWidget {
  final ConceptNote concept;
  const _ConceptTile({required this.concept});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Concepts that got a Wikipedia illustration render as image cards;
    // the rest stay compact bullets.
    if (concept.imageUrl != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              concept.imageUrl!,
              width: 86,
              height: 86,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 86,
                height: 86,
                color: Palette.paper,
                child: const Icon(Icons.image_not_supported_outlined,
                    color: Palette.faint),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(concept.term,
                        style: text.titleMedium?.copyWith(fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(concept.definition, style: text.bodyMedium),
                    if (concept.wiki != null &&
                        concept.wiki != concept.definition) ...[
                      const SizedBox(height: 4),
                      Text('📖 ${concept.wiki}',
                          style: text.bodySmall?.copyWith(fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
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
          if (widget.note.snippetUrl != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF20242B),
              child: Column(
                children: [
                  Image.network(
                    widget.note.snippetUrl!,
                    height: 130,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('🎬 from the lecture video',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ],
              ),
            ),
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
