import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/models/models.dart';
import 'package:kaksha/models/models3.dart';

void main() {
  final readyRow = {
    'id': 'n1',
    'classroom_id': 'c1',
    'session_id': 's1',
    'status': 'ready',
    'progress': 100,
    'stage': 'Ready',
    'created_at': '2026-08-13T10:00:00+00:00',
    'notes': {
      'title': 'DSA',
      'lecture_overview': 'Lists.',
      'simplified_summary': 'Lists 101.',
      'key_concepts': [
        {'concept': 'List', 'explanation': 'chain', 'image': 'https://i/x.png', 'wiki': 'A list.'},
      ],
      'technical_terms': [],
      'per_slide': [
        {'index': 0, 'title': 'Slide 1', 'summary': 'def', 'transcript': 'one two three'},
      ],
    },
    'translations': {
      'hi': {
        'title': 'DSA',
        'lecture_overview': 'सूचियाँ।',
        'simplified_summary': 'x',
        'key_concepts': [],
        'technical_terms': [],
        'per_slide': [],
      },
    },
  };

  test('concept imagery fields parse', () {
    final n = ClassNotes.fromMap(readyRow);
    expect(n.keyConcepts.single.imageUrl, 'https://i/x.png');
    expect(n.keyConcepts.single.wiki, 'A list.');
    expect(n.sessionId, 's1');
  });

  test('cached translation round-trips through withNotesJson', () {
    final n = ClassNotes.fromMap(readyRow);
    final cached = n.translations['hi'] as Map;
    final hi = n.withNotesJson(cached.cast<String, dynamic>());
    expect(hi.overview, 'सूचियाँ।');
    expect(hi.id, n.id);
    expect(hi.sessionId, n.sessionId);
  });

  test('notesJson serialises display fields back to pipeline shape', () {
    final n = ClassNotes.fromMap(readyRow);
    final json = n.notesJson();
    expect(json['lecture_overview'], 'Lists.');
    expect((json['key_concepts'] as List).single['image'], 'https://i/x.png');
    expect((json['per_slide'] as List).single['transcript'], 'one two three');
  });

  test('slides keep order and background url', () {
    final slide = BoardSlide(index: 3, backgroundUrl: 'https://i/p1.png');
    expect(slide.backgroundUrl, isNotNull);
    final list = [BoardSlide(index: 2), slide, BoardSlide(index: 0)]
      ..sort((a, b) => a.index.compareTo(b.index));
    expect([for (final s in list) s.index], [0, 2, 3]);
  });
}
