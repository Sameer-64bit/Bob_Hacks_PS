import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../models/models2.dart';
import '../../models/models3.dart';
import '../../services/board_pdf.dart';
import '../../services/repository.dart';
import '../../services/repository4.dart';
import '../../theme.dart';
import 'board_controller.dart';
import 'board_join.dart';
import 'board_painter.dart';

const _chrome = Color(0xFF20242B);
const _chromeLight = Color(0xFF2B313B);
const _chromeLine = Color(0xFF3A414D);

/// Bottom sheet listing every board session of a classroom by date.
/// Tapping one opens it read-only — works for students and teachers.
Future<void> showBoardHistory(BuildContext context, Classroom classroom) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: _chromeLight,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: FutureBuilder<List<BoardSession>>(
        future: repo.classroomSessions(classroom.id),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 220,
              child: Center(
                  child: CircularProgressIndicator(color: Palette.marigold)),
            );
          }
          final sessions = snapshot.data!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
                child: Text('Boards · ${classroom.code}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 30),
                  child: Text('No boards yet.',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final session in sessions)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 2),
                          leading: Icon(
                            session.isActive
                                ? Icons.podcasts
                                : Icons.history_edu_outlined,
                            color: session.isActive
                                ? const Color(0xFF7FB98A)
                                : Colors.white54,
                          ),
                          title: Text(
                            shortWhen(session.startedAt),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            session.isActive
                                ? 'Live now'
                                : 'Ended ${shortWhen(session.endedAt!)}',
                            style: TextStyle(
                                color: session.isActive
                                    ? const Color(0xFF7FB98A)
                                    : Colors.white38,
                                fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: Colors.white38),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SessionBoardViewer(
                                  classroom: classroom, session: session),
                            ));
                          },
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    ),
  );
}

/// Read-only view of one past board session, slide by slide.
class SessionBoardViewer extends StatefulWidget {
  final Classroom classroom;
  final BoardSession session;

  const SessionBoardViewer(
      {super.key, required this.classroom, required this.session});

  @override
  State<SessionBoardViewer> createState() => _SessionBoardViewerState();
}

class _SessionBoardViewerState extends State<SessionBoardViewer> {
  List<BoardSlide> _slides = [];
  bool _loading = true;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    repo.loadSessionSlides(widget.session.id).then((slides) {
      if (mounted) {
        setState(() {
          _slides = slides;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _sharePdf() async {
    final ok = await BoardPdf.share(
      slides: _slides,
      title:
          'Kaksha · ${classroomLabel(widget.classroom)} · ${shortWhen(widget.session.startedAt)}',
      fileName: 'kaksha-board-${widget.classroom.code.toLowerCase()}.pdf',
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This board is empty.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chrome,
      appBar: AppBar(
        backgroundColor: _chromeLight,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(classroomLabel(widget.classroom),
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            Text(shortWhen(widget.session.startedAt),
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11.5)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share as PDF',
            onPressed: _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Palette.marigold))
          : _slides.isEmpty
              ? const Center(
                  child: Text('This board is empty.',
                      style: TextStyle(color: Colors.white54)))
              : Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: InteractiveViewer(
                          maxScale: 8,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: kCanvasSize.aspectRatio,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: kCanvasSize.width,
                                  height: kCanvasSize.height,
                                  child: SlideView(slide: _slides[_current]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        color: _chromeLight,
                        border: Border(top: BorderSide(color: _chromeLine)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _current > 0
                                ? () => setState(() => _current--)
                                : null,
                            icon: Icon(Icons.chevron_left,
                                color: _current > 0
                                    ? Colors.white70
                                    : Colors.white24),
                          ),
                          Text('${_current + 1} / ${_slides.length}',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600)),
                          IconButton(
                            onPressed: _current < _slides.length - 1
                                ? () => setState(() => _current++)
                                : null,
                            icon: Icon(Icons.chevron_right,
                                color: _current < _slides.length - 1
                                    ? Colors.white70
                                    : Colors.white24),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
