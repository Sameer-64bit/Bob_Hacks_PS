import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/models/models.dart';
import 'package:kaksha/services/board_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardSlide slideWith(List<Offset> points) => BoardSlide(
        index: 0,
        strokes: [
          Stroke(id: 's1', color: 0xFF000000, width: 4, tool: 'pen', points: points),
        ],
      );

  test('exports only non-empty slides as a valid PDF', () async {
    final slides = [
      slideWith(const [Offset(100, 100), Offset(500, 400)]),
      BoardSlide(index: 1), // empty — must be skipped
      slideWith(const [Offset(10, 10), Offset(60, 60)]),
    ];
    final bytes = await BoardPdf.build(slides: slides, title: 'Test board');
    expect(bytes, isNotNull);
    // PDF magic header: %PDF
    expect(String.fromCharCodes(bytes!.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('returns null when every slide is empty', () async {
    final bytes = await BoardPdf.build(
      slides: [BoardSlide(index: 0), BoardSlide(index: 1)],
      title: 'Empty',
    );
    expect(bytes, isNull);
  });
}
