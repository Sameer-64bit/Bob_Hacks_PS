import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'board_controller.dart';

Path _strokePath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 2) {
    path.lineTo(pts[1].dx, pts[1].dy);
    return path;
  }
  // Midpoint quadratic smoothing — keeps fast handwriting rounded.
  for (var i = 1; i + 1 < pts.length; i++) {
    final mid = Offset(
      (pts[i].dx + pts[i + 1].dx) / 2,
      (pts[i].dy + pts[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

void paintStroke(Canvas canvas, Stroke s) {
  final paint = Paint()
    ..color = Color(s.color)
    ..strokeWidth = s.width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (s.points.length == 1) {
    canvas.drawCircle(
        s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
    return;
  }
  canvas.drawPath(_strokePath(s.points), paint);
}

/// Paints one slide: white sheet, strokes, in-progress stroke, selection.
class SlidePainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? active;
  final Set<String> selected;
  final Rect? marquee;
  final Rect? selectionBounds;
  final int revision;

  SlidePainter({
    required this.strokes,
    this.active,
    this.selected = const {},
    this.marquee,
    this.selectionBounds,
    this.revision = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = Offset.zero & size;
    canvas.drawRect(sheet, Paint()..color = Colors.white);
    canvas.clipRect(sheet);

    for (final s in strokes) {
      paintStroke(canvas, s);
      if (selected.contains(s.id)) {
        final b = s.bounds.inflate(6);
        canvas.drawRect(
          b,
          Paint()
            ..color = const Color(0xFF1D6A96).withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    if (active != null) paintStroke(canvas, active!);

    if (selectionBounds != null) {
      canvas.drawRect(
        selectionBounds!,
        Paint()
          ..color = const Color(0xFF1D6A96)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawRect(
        selectionBounds!,
        Paint()..color = const Color(0xFF1D6A96).withValues(alpha: 0.06),
      );
    }

    if (marquee != null) {
      canvas.drawRect(
        marquee!,
        Paint()..color = const Color(0xFF1D6A96).withValues(alpha: 0.10),
      );
      canvas.drawRect(
        marquee!,
        Paint()
          ..color = const Color(0xFF1D6A96)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(SlidePainter old) =>
      old.revision != revision ||
      old.strokes != strokes ||
      old.active != active ||
      old.marquee != marquee ||
      old.selectionBounds != selectionBounds ||
      old.selected != selected;
}

/// Small thumbnail used in the slides sidebar.
class SlideThumbnail extends StatelessWidget {
  final BoardSlide slide;
  final int revision;
  const SlideThumbnail({super.key, required this.slide, this.revision = 0});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kCanvasSize.aspectRatio,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: kCanvasSize.width,
          height: kCanvasSize.height,
          child: CustomPaint(
            painter: SlidePainter(strokes: slide.strokes, revision: revision),
          ),
        ),
      ),
    );
  }
}
