import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/models/models.dart';
import 'package:kaksha/screens/board/board_controller.dart';

void main() {
  BoardController draw(BoardController b, List<Offset> pts) {
    b.startStroke(pts.first);
    for (final p in pts.skip(1)) {
      b.extendStroke(p);
    }
    b.endStroke();
    return b;
  }

  test('drawing commits a stroke and supports undo/redo', () {
    final b = BoardController();
    draw(b, const [Offset(0, 0), Offset(50, 50), Offset(100, 0)]);
    expect(b.slide.strokes.length, 1);
    expect(b.canUndo, isTrue);

    b.undo();
    expect(b.slide.strokes, isEmpty);
    expect(b.canRedo, isTrue);

    b.redo();
    expect(b.slide.strokes.length, 1);
  });

  test('two-finger pinch cancels the active stroke', () {
    final b = BoardController();
    b.startStroke(const Offset(10, 10));
    b.extendStroke(const Offset(20, 20));
    b.cancelStroke();
    expect(b.active, isNull);
    expect(b.slide.strokes, isEmpty);
  });

  test('eraser removes only strokes near the touch point', () {
    final b = BoardController();
    draw(b, const [Offset(0, 0), Offset(100, 0)]);
    draw(b, const [Offset(0, 500), Offset(100, 500)]);
    expect(b.slide.strokes.length, 2);

    b.eraseBegin();
    b.eraseAt(const Offset(50, 2), 10);
    b.eraseEnd();

    expect(b.slide.strokes.length, 1);
    expect(b.slide.strokes.single.points.first.dy, 500);

    b.undo();
    expect(b.slide.strokes.length, 2);
  });

  test('marquee selection, move, copy/paste and cut', () {
    final b = BoardController();
    draw(b, const [Offset(10, 10), Offset(20, 20)]);
    draw(b, const [Offset(900, 900), Offset(950, 950)]);

    b.selectInRect(const Rect.fromLTRB(0, 0, 100, 100));
    expect(b.selected.length, 1);

    // Move the selected stroke.
    b.moveBegin();
    b.moveBy(const Offset(5, 0));
    b.moveEnd();
    final moved =
        b.slide.strokes.firstWhere((s) => b.selected.contains(s.id));
    expect(moved.points.first, const Offset(15, 10));

    // Copy + paste duplicates it with an offset and new id.
    b.copySelection();
    b.paste();
    expect(b.slide.strokes.length, 3);
    expect(b.selected.length, 1);

    // Cut removes the pasted copy but keeps it on the clipboard.
    b.cutSelection();
    expect(b.slide.strokes.length, 2);
    expect(b.hasClipboard, isTrue);
  });

  test('delete selection can be undone', () {
    final b = BoardController();
    draw(b, const [Offset(10, 10), Offset(20, 20)]);
    b.selectInRect(const Rect.fromLTRB(0, 0, 100, 100));
    b.deleteSelection();
    expect(b.slide.strokes, isEmpty);
    b.undo();
    expect(b.slide.strokes.length, 1);
  });

  test('slides can be added, switched and removed with reindexing', () {
    final b = BoardController();
    draw(b, const [Offset(1, 1), Offset(2, 2)]);
    b.addSlide();
    expect(b.slides.length, 2);
    expect(b.current, 1);

    draw(b, const [Offset(5, 5), Offset(6, 6)]);
    b.goTo(0);
    expect(b.slide.strokes.length, 1);

    expect(b.removeSlide(0), isTrue);
    expect(b.slides.length, 1);
    expect(b.slides.first.index, 0);
    expect(b.current, 0);

    // The last slide can never be removed.
    expect(b.removeSlide(0), isFalse);
  });

  test('clear slide wipes strokes but undo restores them', () {
    final b = BoardController();
    draw(b, const [Offset(0, 0), Offset(9, 9)]);
    b.clearSlide();
    expect(b.slide.strokes, isEmpty);
    b.undo();
    expect(b.slide.strokes.length, 1);
  });

  test('onSlideChanged fires for committed changes only', () {
    final b = BoardController();
    var calls = 0;
    b.onSlideChanged = (_) => calls++;

    b.startStroke(const Offset(0, 0));
    b.extendStroke(const Offset(10, 10));
    expect(calls, 0); // in-progress strokes are not persisted
    b.endStroke();
    expect(calls, 1);

    b.setColor(kPenColors[2]);
    b.setTool(BoardTool.eraser);
    expect(calls, 1); // tool/color changes don't persist anything
  });

  test('highlighter strokes are wider and translucent', () {
    final b = BoardController();
    b.setTool(BoardTool.highlighter);
    b.setWidth(4);
    draw(b, const [Offset(0, 0), Offset(10, 0)]);
    final s = b.slide.strokes.single;
    expect(s.tool, 'highlighter');
    expect(s.width, 16);
    final alpha = (s.color >> 24) & 0xFF;
    expect(alpha, lessThan(0xFF));
  });

  test('empty board always starts with one slide', () {
    final b = BoardController(slides: []);
    expect(b.slides.length, 1);
    expect(BoardController(slides: [BoardSlide(index: 0)]).slides.length, 1);
  });
}
