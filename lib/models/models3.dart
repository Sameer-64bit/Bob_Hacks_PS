/// Class-notes models (v4): the row the AI proxy fills in while it turns the
/// ended class into structured notes.
library;

class SlideNote {
  final int index;
  final String title;
  final String summary;
  final String transcript;

  const SlideNote({
    required this.index,
    required this.title,
    required this.summary,
    required this.transcript,
  });

  factory SlideNote.fromMap(Map<String, dynamic> m) => SlideNote(
        index: (m['index'] as num?)?.toInt() ?? 0,
        title: m['title'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        transcript: m['transcript'] as String? ?? '',
      );
}

class ConceptNote {
  final String term;
  final String definition;
  final String? imageUrl; // Wikipedia thumbnail, when one was found
  final String? wiki; // one-line encyclopedia extract

  const ConceptNote({
    required this.term,
    required this.definition,
    this.imageUrl,
    this.wiki,
  });

  factory ConceptNote.fromMap(Map<String, dynamic> m) => ConceptNote(
        term: m['concept'] as String? ?? m['term'] as String? ?? '',
        definition:
            m['explanation'] as String? ?? m['definition'] as String? ?? '',
        imageUrl: m['image'] as String?,
        wiki: m['wiki'] as String?,
      );
}

/// One whiteboard session — a single teaching period's board, tied to
/// its date and time. A classroom accumulates many of these.
class BoardSession {
  final String id;
  final String classroomId;
  final DateTime startedAt;
  final DateTime? endedAt;

  const BoardSession({
    required this.id,
    required this.classroomId,
    required this.startedAt,
    this.endedAt,
  });

  bool get isActive => endedAt == null;

  factory BoardSession.fromMap(Map<String, dynamic> m) => BoardSession(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.parse(m['ended_at'] as String).toLocal(),
      );
}

class ClassNotes {
  final String id;
  final String classroomId;
  final String? sessionId; // which board session these notes came from
  final String status; // processing | ready | failed
  final int progress;
  final String stage;
  final String? error;
  final DateTime createdAt;

  final String title;
  final String overview;
  final String simplifiedSummary;
  final List<ConceptNote> keyConcepts;
  final List<ConceptNote> technicalTerms;
  final List<SlideNote> perSlide;

  const ClassNotes({
    required this.id,
    required this.classroomId,
    this.sessionId,
    required this.status,
    required this.progress,
    required this.stage,
    this.error,
    required this.createdAt,
    required this.title,
    required this.overview,
    required this.simplifiedSummary,
    required this.keyConcepts,
    required this.technicalTerms,
    required this.perSlide,
  });

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing';
  bool get isFailed => status == 'failed';

  factory ClassNotes.fromMap(Map<String, dynamic> m) {
    final notes = (m['notes'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<ConceptNote> concepts(String key) => [
          for (final c in (notes[key] as List? ?? const []))
            ConceptNote.fromMap((c as Map).cast<String, dynamic>()),
        ];
    return ClassNotes(
      id: m['id'] as String,
      classroomId: m['classroom_id'] as String,
      sessionId: m['session_id'] as String?,
      status: m['status'] as String? ?? 'processing',
      progress: (m['progress'] as num?)?.toInt() ?? 0,
      stage: m['stage'] as String? ?? '',
      error: m['error'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      title: notes['title'] as String? ?? 'Class notes',
      overview: notes['lecture_overview'] as String? ?? '',
      simplifiedSummary: notes['simplified_summary'] as String? ?? '',
      keyConcepts: concepts('key_concepts'),
      technicalTerms: concepts('technical_terms'),
      perSlide: [
        for (final s in (notes['per_slide'] as List? ?? const []))
          SlideNote.fromMap((s as Map).cast<String, dynamic>()),
      ],
    );
  }
}
