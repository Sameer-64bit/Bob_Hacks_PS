import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/languages.dart';
import '../../models/models.dart';
import '../../models/models3.dart';
import '../../services/ai.dart';
import '../../services/board_pdf.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../services/repository4.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'board_controller.dart';
import 'board_history.dart';
import 'board_join.dart';
import 'board_painter.dart';

const _chrome = Color(0xFF20242B);
const _chromeLight = Color(0xFF2B313B);
const _chromeLine = Color(0xFF3A414D);

/// Student view of the class smart board: slides stream in live and are
/// strictly read-only. Students can raise a hand on a slide, send a chat
/// that pops up on the teacher's board, and ask AI to translate or
/// describe the current slide in their language.
class LiveBoardView extends StatefulWidget {
  final Classroom classroom;
  final Student student;

  const LiveBoardView(
      {super.key, required this.classroom, required this.student});

  @override
  State<LiveBoardView> createState() => _LiveBoardViewState();
}

class _LiveBoardViewState extends State<LiveBoardView> {
  int _current = 0;
  String _language = 'en';
  bool _handCooldown = false;
  final _chat = TextEditingController();
  List<BoardSlide> _slides = [];

  Future<void> _sharePdf() async {
    try {
      final ok = await BoardPdf.share(
        slides: _slides,
        title: 'Kaksha · ${classroomLabel(widget.classroom)}',
        fileName: 'kaksha-board-${widget.classroom.code.toLowerCase()}.pdf',
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nothing to export yet — the board is empty.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void initState() {
    super.initState();
    repo
        .languageOf(isTeacher: false, id: widget.student.id)
        .then((code) => mounted ? setState(() => _language = code) : null)
        .catchError((_) {});
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  Future<void> _raiseHand() async {
    if (_handCooldown) return;
    setState(() => _handCooldown = true);
    try {
      await repo.sendClassEvent(
        classroomId: widget.classroom.id,
        studentId: widget.student.id,
        studentName: widget.student.name,
        kind: 'hand',
        slideIndex: _current,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✋ Hand raised on slide ${_current + 1} — your teacher can see it.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _handCooldown = false);
    });
  }

  Future<void> _sendChat() async {
    final body = _chat.text.trim();
    if (body.isEmpty) return;
    _chat.clear();
    try {
      await repo.sendClassEvent(
        classroomId: widget.classroom.id,
        studentId: widget.student.id,
        studentName: widget.student.name,
        kind: 'chat',
        slideIndex: _current,
        body: body,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _runAi(BoardSlide slide, {required bool translateMode}) async {
    final language = languageByCode(_language);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _chromeLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AiSheet(
        title: translateMode
            ? 'Translated to ${language.name}'
            : 'Slide described',
        future: translateMode
            ? SlideAi.translate(slide, language)
            : SlideAi.describe(slide, language),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chrome,
      body: SafeArea(
        // Follow the classroom's latest board session — when the teacher
        // starts a new board after ending a class, students switch to it
        // automatically. Past boards live under the history button.
        child: StreamBuilder<BoardSession?>(
          stream: repo.streamLatestSession(widget.classroom.id),
          builder: (context, sessionSnap) {
            final session = sessionSnap.data;
            if (sessionSnap.connectionState == ConnectionState.waiting &&
                session == null) {
              return const Center(
                  child: CircularProgressIndicator(color: Palette.marigold));
            }
            if (session == null) return _emptyState();
            return _buildSlides(session);
          },
        ),
      ),
    );
  }

  Widget _buildSlides(BoardSession session) {
    return StreamBuilder<List<BoardSlide>>(
          key: ValueKey(session.id),
          stream: repo.streamSessionSlides(session.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Could not connect to the live board.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: Palette.marigold));
            }
            final slides = snapshot.data!;
            _slides = slides;
            if (slides.isEmpty) {
              return _emptyState();
            }
            if (_current >= slides.length) _current = slides.length - 1;
            final slide = slides[_current];

            return Column(
              children: [
                _topBar(slide),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: kCanvasSize.aspectRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: kCanvasSize.width,
                              height: kCanvasSize.height,
                              child: CustomPaint(
                                painter: SlidePainter(
                                  strokes: slide.strokes,
                                  revision: slide.strokes.length,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _bottomBar(slides.length),
              ],
            );
          },
        );
  }

  Widget _emptyState() {
    return Column(
      children: [
        _topBar(null),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.draw_outlined, color: Colors.white24, size: 44),
                const SizedBox(height: 12),
                Text('The board is empty',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Slides appear here live once your teacher starts writing.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(BoardSlide? slide) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: _chromeLight,
        border: Border(bottom: BorderSide(color: _chromeLine)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(classroomLabel(widget.classroom),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const Text('Live · view only',
                    style: TextStyle(color: Color(0xFF7FB98A), fontSize: 11)),
              ],
            ),
          ),
          if (slide != null) ...[
            TextButton.icon(
              onPressed: AppConfig.hasAi
                  ? () => _runAi(slide, translateMode: true)
                  : () => showError(context,
                      'Add a Gemini API key in lib/config.dart to enable AI.'),
              icon: const Icon(Icons.translate, size: 18, color: Palette.marigold),
              label: Text(languageByCode(_language).native,
                  style: const TextStyle(color: Palette.marigold, fontSize: 13)),
            ),
            IconButton(
              tooltip: 'Describe this slide (AI)',
              onPressed: AppConfig.hasAi
                  ? () => _runAi(slide, translateMode: false)
                  : () => showError(context,
                      'Add a Gemini API key in lib/config.dart to enable AI.'),
              icon: const Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
            ),
            IconButton(
              tooltip: 'Share board as PDF',
              onPressed: _sharePdf,
              icon: const Icon(Icons.picture_as_pdf_outlined,
                  color: Colors.white70, size: 20),
            ),
          ],
          IconButton(
            tooltip: 'Past boards (by date)',
            onPressed: () => showBoardHistory(context, widget.classroom),
            icon: const Icon(Icons.history, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _bottomBar(int slideCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: _chromeLight,
        border: Border(top: BorderSide(color: _chromeLine)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous slide',
            onPressed: _current > 0 ? () => setState(() => _current--) : null,
            icon: Icon(Icons.chevron_left,
                color: _current > 0 ? Colors.white70 : Colors.white24),
          ),
          Text('${_current + 1} / $slideCount',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Next slide',
            onPressed: _current < slideCount - 1
                ? () => setState(() => _current++)
                : null,
            icon: Icon(Icons.chevron_right,
                color:
                    _current < slideCount - 1 ? Colors.white70 : Colors.white24),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _chat,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendChat(),
              decoration: InputDecoration(
                hintText: 'Ask in class — pops up on the board…',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Palette.marigold),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Send to class',
            onPressed: _sendChat,
            icon: const Icon(Icons.send, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _handCooldown ? _chromeLine : Palette.marigold,
              foregroundColor: _handCooldown ? Colors.white38 : _chrome,
              minimumSize: const Size(0, 42),
            ),
            onPressed: _handCooldown ? null : _raiseHand,
            icon: const Icon(Icons.back_hand_outlined, size: 18),
            label: const Text('Raise hand'),
          ),
        ],
      ),
    );
  }
}

class _AiSheet extends StatelessWidget {
  final String title;
  final Future<String> future;
  const _AiSheet({required this.title, required this.future});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: FutureBuilder<String>(
        future: future,
        builder: (context, snapshot) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: Palette.marigold, size: 20),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: switch (snapshot) {
                  AsyncSnapshot(hasError: true) => Text(
                      snapshot.error
                          .toString()
                          .replaceFirst('Exception: ', ''),
                      style: const TextStyle(color: Color(0xFFE09999))),
                  AsyncSnapshot(hasData: true) => SingleChildScrollView(
                      child: SelectableText(
                        snapshot.data!,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            height: 1.55),
                      ),
                    ),
                  _ => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                          child: Column(
                        children: [
                          CircularProgressIndicator(color: Palette.marigold),
                          SizedBox(height: 14),
                          Text('Reading the slide…',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      )),
                    ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
