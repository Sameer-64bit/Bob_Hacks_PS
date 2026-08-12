import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Logical canvas size — strokes are stored in this coordinate space so a
/// slide looks identical on a phone and on a 86" People's Link panel.
const Size kCanvasSize = Size(1920, 1080);

enum BoardTool { pen, highlighter, eraser, select, pan }

const List<Color> kPenColors = [
  Color(0xFF191817), // ink
  Color(0xFF16324F), // navy
  Color(0xFF1D6A96), // blue
  Color(0xFF2F7D4F), // green
  Color(0xFFC0392B), // red
  Color(0xFFE8A33D), // marigold
  Color(0xFF7A5C9E), // violet
  Color(0xFFC26D4C), // terracotta
];

String _rid() {
  final r = Random();
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final s = r.nextInt(0xFFFFFF).toRadixString(36);
  return '$t-$s';
}

/// All drawing state for one board session. Pure state + geometry — no
/// network code in here (the screen persists slides when [onSlideChanged]
/// fires), which also makes it unit-testable.
class BoardController extends ChangeNotifier {
  BoardController({List<BoardSlide>? slides})
      : slides = (slides == null || slides.isEmpty)
            ? [BoardSlide(index: 0)]
            : slides;

  final List<BoardSlide> slides;
  int current = 0;

  BoardTool tool = BoardTool.pen;
  Color color = kPenColors.first;
  double strokeWidth = 4;

  /// Called after any committed change to a slide (stroke finished, erase,
  /// paste, clear…) so the owner can persist it.
  void Function(BoardSlide slide)? onSlideChanged;

  BoardSlide get slide => slides[current];

  // In-progress stroke ------------------------------------------------------
  Stroke? active;

  // Selection ---------------------------------------------------------------
  final Set<String> selected = {};
  Rect? marquee;
  List<Stroke> _clipboard = [];
  bool get hasSelection => selected.isNotEmpty;
  bool get hasClipboard => _clipboard.isNotEmpty;

  // Undo / redo (per slide) -------------------------------------------------
  final Map<int, List<List<Stroke>>> _undo = {};
  final Map<int, List<List<Stroke>>> _redo = {};
  bool get canUndo => (_undo[current] ?? const []).isNotEmpty;
  bool get canRedo => (_redo[current] ?? const []).isNotEmpty;

  void _snapshot() {
    final stack = _undo.putIfAbsent(current, () => []);
    stack.add(List.of(slide.strokes));
    if (stack.length > 50) stack.removeAt(0);
    _redo[current]?.clear();
  }

  void undo() {
    final stack = _undo[current];
    if (stack == null || stack.isEmpty) return;
    _redo.putIfAbsent(current, () => []).add(List.of(slide.strokes));
    slide.strokes = stack.removeLast();
    selected.clear();
    _changed();
  }

  void redo() {
    final stack = _redo[current];
    if (stack == null || stack.isEmpty) return;
    _undo.putIfAbsent(current, () => []).add(List.of(slide.strokes));
    slide.strokes = stack.removeLast();
    selected.clear();
    _changed();
  }

  void _changed() {
    onSlideChanged?.call(slide);
    notifyListeners();
  }

  // Drawing -----------------------------------------------------------------

  void startStroke(Offset p) {
    active = Stroke(
      id: _rid(),
      color: tool == BoardTool.highlighter
          ? color.withValues(alpha: 0.4).toARGB32()
          : color.toARGB32(),
      width: tool == BoardTool.highlighter ? strokeWidth * 4 : strokeWidth,
      tool: tool == BoardTool.highlighter ? 'highlighter' : 'pen',
      points: [p],
    );
    notifyListeners();
  }

  void extendStroke(Offset p) {
    final a = active;
    if (a == null) return;
    if (a.points.isNotEmpty && (a.points.last - p).distance < 1.2) return;
    active = a.copyWith(points: [...a.points, p]);
    notifyListeners();
  }

  void endStroke() {
    final a = active;
    active = null;
    if (a == null || a.points.isEmpty) return;
    _snapshot();
    slide.strokes = [...slide.strokes, a];
    _changed();
  }

  void cancelStroke() {
    active = null;
    notifyListeners();
  }

  // Eraser ------------------------------------------------------------------

  bool _erasing = false;
  bool _erasedAny = false;

  void eraseBegin() {
    _erasing = false;
    _erasedAny = false;
  }

  void eraseAt(Offset p, double radius) {
    final hit = slide.strokes.where((s) => _strokeHit(s, p, radius)).toList();
    if (hit.isEmpty) return;
    if (!_erasing) {
      _snapshot();
      _erasing = true;
    }
    _erasedAny = true;
    final ids = hit.map((s) => s.id).toSet();
    slide.strokes =
        slide.strokes.where((s) => !ids.contains(s.id)).toList();
    notifyListeners();
  }

  void eraseEnd() {
    if (_erasedAny) _changed();
    _erasing = false;
    _erasedAny = false;
  }

  static bool _strokeHit(Stroke s, Offset p, double radius) {
    final pts = s.points;
    if (pts.length == 1) return (pts.first - p).distance <= radius + s.width;
    for (var i = 0; i + 1 < pts.length; i++) {
      if (_segmentDistance(p, pts[i], pts[i + 1]) <= radius + s.width / 2) {
        return true;
      }
    }
    return false;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // Selection ---------------------------------------------------------------

  void setMarquee(Rect? r) {
    marquee = r;
    notifyListeners();
  }

  void selectInRect(Rect r) {
    selected
      ..clear()
      ..addAll(slide.strokes
          .where((s) => s.points.any(r.contains))
          .map((s) => s.id));
    marquee = null;
    notifyListeners();
  }

  void clearSelection() {
    selected.clear();
    marquee = null;
    notifyListeners();
  }

  Rect? selectionBounds() {
    Rect? acc;
    for (final s in slide.strokes) {
      if (!selected.contains(s.id)) continue;
      acc = acc == null ? s.bounds : acc.expandToInclude(s.bounds);
    }
    return acc?.inflate(12);
  }

  bool _moving = false;

  void moveBegin() {
    if (!hasSelection) return;
    _snapshot();
    _moving = true;
  }

  void moveBy(Offset delta) {
    if (!_moving) return;
    slide.strokes = [
      for (final s in slide.strokes)
        selected.contains(s.id) ? s.translated(delta) : s,
    ];
    notifyListeners();
  }

  void moveEnd() {
    if (!_moving) return;
    _moving = false;
    _changed();
  }

  void copySelection() {
    _clipboard = [
      for (final s in slide.strokes)
        if (selected.contains(s.id)) s,
    ];
    notifyListeners();
  }

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  void deleteSelection() {
    if (!hasSelection) return;
    _snapshot();
    slide.strokes =
        slide.strokes.where((s) => !selected.contains(s.id)).toList();
    selected.clear();
    _changed();
  }

  void paste() {
    if (_clipboard.isEmpty) return;
    _snapshot();
    final pasted = [
      for (final s in _clipboard)
        s.translated(const Offset(32, 32)).copyWith(id: _rid()),
    ];
    slide.strokes = [...slide.strokes, ...pasted];
    selected
      ..clear()
      ..addAll(pasted.map((s) => s.id));
    _clipboard = pasted; // repeated paste keeps stepping down-right
    _changed();
  }

  void clearSlide() {
    if (slide.strokes.isEmpty) return;
    _snapshot();
    slide.strokes = [];
    selected.clear();
    _changed();
  }

  // Slides ------------------------------------------------------------------

  void addSlide() {
    slides.add(BoardSlide(index: slides.length));
    current = slides.length - 1;
    selected.clear();
    _changed();
  }

  void goTo(int index) {
    if (index < 0 || index >= slides.length) return;
    current = index;
    selected.clear();
    active = null;
    notifyListeners();
  }

  /// Removes the slide and reindexes. Returns false when it's the only one.
  bool removeSlide(int index) {
    if (slides.length <= 1) return false;
    slides.removeAt(index);
    for (var i = 0; i < slides.length; i++) {
      slides[i].index = i;
    }
    _undo.clear();
    _redo.clear();
    if (current >= slides.length) current = slides.length - 1;
    selected.clear();
    notifyListeners();
    return true;
  }

  // Tool selection ----------------------------------------------------------

  void setTool(BoardTool t) {
    tool = t;
    if (t != BoardTool.select) clearSelection();
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  void setWidth(double w) {
    strokeWidth = w;
    notifyListeners();
  }
}
