import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/models/models3.dart';

void main() {
  test('parses a processing row without notes', () {
    final n = ClassNotes.fromMap({
      'id': 'n1',
      'classroom_id': 'c1',
      'status': 'processing',
      'progress': 42,
      'stage': 'Reading slide 2 of 3…',
      'notes': null,
      'created_at': '2026-08-13T10:00:00+00:00',
    });
    expect(n.isProcessing, isTrue);
    expect(n.progress, 42);
    expect(n.perSlide, isEmpty);
    expect(n.title, 'Class notes');
  });

  test('parses a ready row with the pipeline schema', () {
    final n = ClassNotes.fromMap({
      'id': 'n2',
      'classroom_id': 'c1',
      'status': 'ready',
      'progress': 100,
      'stage': 'Ready',
      'created_at': '2026-08-13T10:05:00+00:00',
      'notes': {
        'title': 'DSA Class',
        'lecture_overview': 'We covered linked lists.',
        'simplified_summary': 'Linked lists 101.',
        'key_concepts': [
          {'concept': 'Linked list', 'explanation': 'A chain of nodes.'},
        ],
        'technical_terms': [
          {'term': 'Pointer', 'definition': 'Reference to the next node.'},
        ],
        'per_slide': [
          {
            'index': 0,
            'title': 'Slide 1',
            'summary': 'Definition of a linked list.',
            'transcript': 'A linked list is a chain of nodes.',
          },
        ],
      },
    });
    expect(n.isReady, isTrue);
    expect(n.title, 'DSA Class');
    expect(n.keyConcepts.single.term, 'Linked list');
    expect(n.technicalTerms.single.definition, 'Reference to the next node.');
    expect(n.perSlide.single.transcript, contains('chain of nodes'));
  });

  test('failed row exposes the error', () {
    final n = ClassNotes.fromMap({
      'id': 'n3',
      'classroom_id': 'c1',
      'status': 'failed',
      'progress': 20,
      'stage': 'Failed',
      'error': 'whisper crashed',
      'created_at': '2026-08-13T10:05:00+00:00',
    });
    expect(n.isFailed, isTrue);
    expect(n.error, 'whisper crashed');
  });
}
