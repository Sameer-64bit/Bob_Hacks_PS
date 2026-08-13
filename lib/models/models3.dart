/// Class-notes models (v4): the row the AI proxy fills in while it turns the
/// ended class into structured notes.
library;

class SlideNote {
  final int index;
  final String title;
  final String summary;
  final String transcript;

  /// A frame from the lecture video taken while this slide was on screen.
  final String? snippetUrl;

  const SlideNote({
    required this.index,
    required this.title,
    required this.summary,
    required this.transcript,
    this.snippetUrl,
  });

  factory SlideNote.fromMap(Map<String, dynamic> m) => SlideNote(
        index: (m['index'] as num?)?.toInt() ?? 0,
        title: m['title'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        transcript: m['transcript'] as String? ?? '',
        snippetUrl: m['snippet_url'] as String?,
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

/// One live-transcribed caption line from the lecture.
class LiveCaption {
  final String id;
  final int slideIndex;
  final double startS;
  final double endS;
  final String text;

  const LiveCaption({
    required this.id,
    required this.slideIndex,
    required this.startS,
    required this.endS,
    required this.text,
  });

  factory LiveCaption.fromMap(Map<String, dynamic> m) => LiveCaption(
        id: m['id'] as String,
        slideIndex: (m['slide_index'] as num?)?.toInt() ?? 0,
        startS: (m['start_s'] as num?)?.toDouble() ?? 0,
        endS: (m['end_s'] as num?)?.toDouble() ?? 0,
        text: m['text'] as String? ?? '',
      );
}

/// Teacher-uploaded media: stored compressed + encrypted, decrypted only
/// inside the app.
class ClassMedia {
  final String id;
  final String classroomId;
  final String? sessionId; // set when this is the class lecture recording
  final String? scheduleId; // which subject (schedule entry) this belongs to
  final String transcriptStatus; // none | processing | ready | failed
  final String title;
  final String mime;
  final int bytesOriginal;
  final int bytesStored;
  final String path;
  final String iv;
  final DateTime createdAt;

  const ClassMedia({
    required this.id,
    required this.classroomId,
    this.sessionId,
    this.scheduleId,
    this.transcriptStatus = 'none',
    required this.title,
    required this.mime,
    required this.bytesOriginal,
    required this.bytesStored,
    required this.path,
    required this.iv,
    required this.createdAt,
  });

  bool get hasSubtitles => transcriptStatus == 'ready';

  bool get isVideo => mime.startsWith('video/');
  bool get isAudio => mime.startsWith('audio/');
  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  factory ClassMedia.fromMap(Map<String, dynamic> m) => ClassMedia(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        sessionId: m['session_id'] as String?,
        scheduleId: m['schedule_id'] as String?,
        transcriptStatus: m['transcript_status'] as String? ?? 'none',
        title: m['title'] as String? ?? 'Untitled',
        mime: m['mime'] as String? ?? 'application/octet-stream',
        bytesOriginal: (m['bytes_original'] as num?)?.toInt() ?? 0,
        bytesStored: (m['bytes_stored'] as num?)?.toInt() ?? 0,
        path: m['path'] as String,
        iv: m['iv'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// One whiteboard session — a single teaching period's board, tied to
/// its date and time. A classroom accumulates many of these.
class BoardSession {
  final String id;
  final String classroomId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Slide-change timestamps recorded during class, kept so a lecture
  /// video uploaded later can still be aligned slide-by-slide.
  final List<Map<String, dynamic>> slideMarks;

  const BoardSession({
    required this.id,
    required this.classroomId,
    required this.startedAt,
    this.endedAt,
    this.slideMarks = const [],
  });

  bool get isActive => endedAt == null;

  factory BoardSession.fromMap(Map<String, dynamic> m) => BoardSession(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.parse(m['ended_at'] as String).toLocal(),
        slideMarks: [
          for (final mark in (m['slide_marks'] as List? ?? const []))
            (mark as Map).cast<String, dynamic>(),
        ],
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

  /// Cached translations by language code — translate once, read forever.
  final Map<String, dynamic> translations;

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
    this.translations = const {},
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
      translations:
          (m['translations'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// The display fields serialised back to the pipeline's JSON shape —
  /// used to store a translation in the cache.
  Map<String, dynamic> notesJson() => {
        'title': title,
        'lecture_overview': overview,
        'simplified_summary': simplifiedSummary,
        'key_concepts': [
          for (final c in keyConcepts)
            {
              'concept': c.term,
              'explanation': c.definition,
              if (c.imageUrl != null) 'image': c.imageUrl,
              if (c.wiki != null) 'wiki': c.wiki,
            },
        ],
        'technical_terms': [
          for (final c in technicalTerms)
            {
              'term': c.term,
              'definition': c.definition,
              if (c.imageUrl != null) 'image': c.imageUrl,
              if (c.wiki != null) 'wiki': c.wiki,
            },
        ],
        'per_slide': [
          for (final s in perSlide)
            {
              'index': s.index,
              'title': s.title,
              'summary': s.summary,
              'transcript': s.transcript,
              if (s.snippetUrl != null) 'snippet_url': s.snippetUrl,
            },
        ],
      };

  /// A copy of this row whose display fields come from [json] (e.g. a
  /// cached or freshly-made translation).
  ClassNotes withNotesJson(Map<String, dynamic> json) => ClassNotes.fromMap({
        'id': id,
        'classroom_id': classroomId,
        'session_id': sessionId,
        'status': status,
        'progress': progress,
        'stage': stage,
        'error': error,
        'created_at': createdAt.toUtc().toIso8601String(),
        'notes': json,
        'translations': translations,
      });
}
