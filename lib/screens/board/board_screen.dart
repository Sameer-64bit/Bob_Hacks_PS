import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:record/record.dart';

import '../../models/models.dart';
import '../../models/models2.dart';
import '../../models/models3.dart';
import '../../services/ai.dart';
import '../../services/board_pdf.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../services/repository3.dart';
import '../../services/repository4.dart';
import '../../theme.dart';
import 'board_controller.dart';
import 'board_history.dart';
import 'board_join.dart';
import 'board_painter.dart';

const _chrome = Color(0xFF20242B);
const _chromeLight = Color(0xFF2B313B);
const _chromeLine = Color(0xFF3A414D);

class BoardScreen extends StatefulWidget {
  final Classroom? classroom;

  /// With a [classroom] the board loads and autosaves that class's slides.
  /// Without one it runs as a practice board — nothing is persisted.
  const BoardScreen({super.key, this.classroom});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  BoardController? _board;
  String? _loadError;

  // View transform: screen = _offset + canvasPoint * _scale
  double _scale = 0.5;
  Offset _offset = Offset.zero;
  bool _fitted = false;

  // Active pointers on the canvas (screen-local positions).
  final Map<int, Offset> _pointers = {};
  // Single-pointer gesture state
  int? _gesturePointer;
  Offset? _gestureStartCanvas;
  Offset? _lastCanvas;
  Offset? _lastScreen;
  bool _movingSelection = false;
  // Pinch state
  Offset? _pinchA, _pinchB;
  double _pinchBaseScale = 1;
  Offset _pinchBaseOffset = Offset.zero;

  // Persistence
  final Set<int> _dirty = {};
  Timer? _saveTimer;
  String _saveStatus = 'Saved';
  int _revision = 0;

  // Live class events (raised hands / chats from students)
  StreamSubscription<List<ClassEvent>>? _eventsSub;
  final DateTime _joinedAt = DateTime.now();
  final Set<String> _seenEvents = {};
  final List<ClassEvent> _popups = [];

  // Lecture recording + slide-change timestamps for the notes pipeline
  final AudioRecorder _lectureRecorder = AudioRecorder();
  bool _lectureRecording = false;
  DateTime? _audioStart;
  final List<Map<String, dynamic>> _slideMarks = [];
  int _lastSlideIndex = 0;
  bool _endingClass = false;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToClassEvents();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _saveTimer?.cancel();
    _flushSaves();
    _lectureRecorder.dispose();
    _board?.dispose();
    super.dispose();
  }

  Future<void> _toggleLectureRecording() async {
    try {
      if (_lectureRecording) {
        // Stop only pauses conceptually — bytes are collected in _endClass.
        return;
      }
      if (!await _lectureRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Microphone permission was denied.')));
        }
        return;
      }
      await _lectureRecorder.start(
        RecordConfig(
            encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: 'lecture.m4a',
      );
      setState(() {
        _lectureRecording = true;
        _audioStart = DateTime.now();
        _slideMarks
          ..clear()
          ..add({'index': _board?.current ?? 0, 'at': 0.0});
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '🎙️ Recording the lecture — it becomes class notes when you end the class.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not record: $e')));
      }
    }
  }

  void _subscribeToClassEvents() {
    final classroom = widget.classroom;
    if (classroom == null) return;
    _eventsSub = repo.streamClassEvents(classroom.id).listen((events) {
      for (final event in events) {
        if (event.createdAt.isBefore(_joinedAt)) continue;
        if (!_seenEvents.add(event.id)) continue;
        setState(() => _popups.add(event));
        Timer(const Duration(seconds: 8), () {
          if (mounted) setState(() => _popups.remove(event));
        });
      }
    }, onError: (_) {});
  }

  Classroom? get _classroom => widget.classroom;
  BoardSession? _session;

  Future<void> _load() async {
    try {
      final classroom = _classroom;
      List<BoardSlide> slides = [];
      if (classroom != null) {
        // Every teaching period gets its own board (session).
        _session = await repo.activeSession(classroom.id);
        slides = await repo.loadSessionSlides(_session!.id);
      }
      final board = BoardController(slides: slides);
      board.onSlideChanged = _markDirty;
      board.addListener(() {
        _revision++;
        // Timestamp slide changes while the lecture is being recorded so
        // the transcript can be aligned slide-by-slide.
        if (_lectureRecording && board.current != _lastSlideIndex) {
          _slideMarks.add({
            'index': board.current,
            'at': DateTime.now()
                    .difference(_audioStart ?? DateTime.now())
                    .inMilliseconds /
                1000.0,
          });
        }
        _lastSlideIndex = board.current;
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      setState(() {
        _board = board;
        if (classroom == null) _saveStatus = 'Practice board';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the board: $e');
    }
  }

  // ------------------------------------------------------------------ saving

  void _markDirty(BoardSlide slide) {
    if (_classroom == null) return; // practice board — nothing to persist
    _dirty.add(slide.index);
    _saveStatus = 'Saving…';
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _flushSaves);
  }

  Future<void> _flushSaves() async {
    final board = _board;
    final classroom = _classroom;
    final session = _session;
    if (board == null || classroom == null || session == null || _dirty.isEmpty) {
      return;
    }
    final indexes = _dirty.toList();
    _dirty.clear();
    try {
      for (final i in indexes) {
        if (i < board.slides.length) {
          await repo.saveSessionSlide(classroom.id, session.id, board.slides[i]);
        }
      }
      if (mounted) setState(() => _saveStatus = 'Saved');
    } catch (_) {
      if (mounted) setState(() => _saveStatus = 'Offline — retrying');
      _dirty.addAll(indexes);
      _saveTimer = Timer(const Duration(seconds: 4), _flushSaves);
    }
  }

  Future<void> _deleteSlide(int index) async {
    final board = _board!;
    final classroom = _classroom;
    final session = _session;
    final oldCount = board.slides.length;
    if (!board.removeSlide(index)) return;
    if (classroom == null || session == null) return;
    try {
      for (final slide in board.slides) {
        await repo.saveSessionSlide(classroom.id, session.id, slide);
      }
      await repo.deleteSessionSlide(session.id, oldCount - 1);
    } catch (_) {
      if (mounted) setState(() => _saveStatus = 'Offline — retrying');
    }
  }

  // --------------------------------------------------------------- transform

  Offset _toCanvas(Offset screen) => (screen - _offset) / _scale;

  Size _viewport = const Size(1280, 720);

  void _fit() {
    final sx = _viewport.width / kCanvasSize.width;
    final sy = _viewport.height / kCanvasSize.height;
    _scale = ((sx < sy ? sx : sy) * 0.94).clamp(0.05, 4.0).toDouble();
    _offset = Offset(
      (_viewport.width - kCanvasSize.width * _scale) / 2,
      (_viewport.height - kCanvasSize.height * _scale) / 2,
    );
  }

  void _zoomAt(Offset focal, double factor) {
    final canvasPt = _toCanvas(focal);
    setState(() {
      _scale = (_scale * factor).clamp(0.15, 6.0);
      _offset = focal - canvasPt * _scale;
    });
  }

  // ---------------------------------------------------------------- pointers

  void _pointerDown(PointerDownEvent e) {
    final board = _board!;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      // Second finger: abandon the single-pointer gesture, start pinch.
      if (_gesturePointer != null) {
        board.cancelStroke();
        board.setMarquee(null);
        if (_movingSelection) board.moveEnd();
        if (board.tool == BoardTool.eraser) board.eraseEnd();
        _gesturePointer = null;
        _movingSelection = false;
      }
      final pts = _pointers.values.toList();
      _pinchA = pts[0];
      _pinchB = pts[1];
      _pinchBaseScale = _scale;
      _pinchBaseOffset = _offset;
      return;
    }
    if (_pointers.length > 2) return;

    _gesturePointer = e.pointer;
    final canvasPt = _toCanvas(e.localPosition);
    _gestureStartCanvas = canvasPt;
    _lastCanvas = canvasPt;
    _lastScreen = e.localPosition;

    switch (board.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        board.startStroke(canvasPt);
      case BoardTool.eraser:
        board.eraseBegin();
        board.eraseAt(canvasPt, 14 / _scale + 8);
      case BoardTool.select:
        final bounds = board.selectionBounds();
        if (bounds != null && bounds.contains(canvasPt)) {
          _movingSelection = true;
          board.moveBegin();
        } else {
          board.setMarquee(Rect.fromPoints(canvasPt, canvasPt));
        }
      case BoardTool.pan:
        break;
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final board = _board!;
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    // Pinch zoom + pan
    if (_pointers.length >= 2 && _pinchA != null && _pinchB != null) {
      final pts = _pointers.values.toList();
      final baseDist = (_pinchA! - _pinchB!).distance;
      final curDist = (pts[0] - pts[1]).distance;
      if (baseDist > 1) {
        final rawScale = _pinchBaseScale * (curDist / baseDist);
        final newScale = rawScale.clamp(0.15, 6.0).toDouble();
        final baseMid = (_pinchA! + _pinchB!) / 2;
        final curMid = (pts[0] + pts[1]) / 2;
        final canvasMid = (baseMid - _pinchBaseOffset) / _pinchBaseScale;
        setState(() {
          _scale = newScale;
          _offset = curMid - canvasMid * newScale;
        });
      }
      return;
    }

    if (e.pointer != _gesturePointer) return;
    final canvasPt = _toCanvas(e.localPosition);

    switch (board.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        board.extendStroke(canvasPt);
      case BoardTool.eraser:
        board.eraseAt(canvasPt, 14 / _scale + 8);
      case BoardTool.select:
        if (_movingSelection) {
          board.moveBy(canvasPt - _lastCanvas!);
        } else if (_gestureStartCanvas != null) {
          board.setMarquee(Rect.fromPoints(_gestureStartCanvas!, canvasPt));
        }
      case BoardTool.pan:
        setState(() => _offset += e.localPosition - _lastScreen!);
    }
    _lastCanvas = canvasPt;
    _lastScreen = e.localPosition;
  }

  void _pointerUp(int pointer) {
    final board = _board!;
    _pointers.remove(pointer);
    if (_pointers.length < 2) {
      _pinchA = null;
      _pinchB = null;
    }
    if (pointer != _gesturePointer) return;
    _gesturePointer = null;

    switch (board.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        board.endStroke();
      case BoardTool.eraser:
        board.eraseEnd();
      case BoardTool.select:
        if (_movingSelection) {
          board.moveEnd();
          _movingSelection = false;
        } else if (board.marquee != null) {
          final m = board.marquee!;
          if (m.width < 6 && m.height < 6) {
            board.clearSelection();
          } else {
            board.selectInRect(m);
          }
        }
      case BoardTool.pan:
        break;
    }
  }

  void _pointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _zoomAt(e.localPosition, e.scrollDelta.dy > 0 ? 0.92 : 1.08);
    }
  }

  /// Ends the class: uploads the lecture audio (if recorded) and every
  /// slide to the AI proxy, which turns them into class notes. Students
  /// watch a live progress bar until the notes are ready.
  Future<void> _endClass() async {
    final classroom = widget.classroom;
    final board = _board;
    if (classroom == null || board == null || _endingClass) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End this class?'),
        content: Text(_lectureRecording
            ? 'The lecture recording and every slide will be turned into '
                'class notes for your students.'
            : 'Every slide will be turned into class notes for your '
                'students. (Tip: record the lecture next time for richer notes.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End class'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _endingClass = true);
    String? noteId;
    try {
      await _flushSaves();

      // 1. Collect the lecture audio, if the teacher recorded one.
      String? audioUrl;
      if (_lectureRecording) {
        final path = await _lectureRecorder.stop();
        _lectureRecording = false;
        if (path != null) {
          final bytes = await XFile(path).readAsBytes();
          audioUrl = await repo.uploadLectureAudio(
              bytes, kIsWeb ? 'webm' : 'm4a');
        }
      }

      // 2. Create the notes row students will watch, then render the slides.
      noteId = await repo.createClassNotes(
        classroomId: classroom.id,
        language: 'en',
        sessionId: _session?.id,
      );
      final slides = <String>[];
      final strokeCounts = <int>[];
      for (final slide in board.slides) {
        slides.add(await SlideAi.renderSlideBase64(slide));
        // Imported PDF pages carry real content even with zero strokes —
        // report them as dense so the VLM reads them.
        strokeCounts.add(
            slide.backgroundUrl != null ? 999 : slide.strokes.length);
      }

      // 3. Hand everything to the proxy — it updates progress from here on.
      await repo.startClassNotesJob(
        noteId: noteId,
        language: 'en',
        title: 'Class notes · ${classroomLabel(classroom)}',
        slidePngsB64: slides,
        strokeCounts: strokeCounts,
        slideMarks: _slideMarks,
        audioUrl: audioUrl,
        audioExt: kIsWeb ? 'webm' : 'm4a',
      );

      // 4. Close this session — its board stays in history under today's date.
      if (_session != null) await repo.endSession(_session!.id);

      if (!mounted) return;
      await _offerNewBoard(classroom);
    } catch (e) {
      if (noteId != null) {
        try {
          await repo.markClassNotesFailed(noteId, e.toString());
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _endingClass = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start the notes: $e')));
      }
    }
  }

  /// After ending a class the teacher can spin up a fresh board for the
  /// next period — same classroom code, blank slides, new session.
  Future<void> _offerNewBoard(Classroom classroom) async {
    final startNew = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Class ended 🎉'),
        content: const Text(
            'Notes are being prepared for your students. This board is saved '
            'in history under today\'s date. Start a new board for the next '
            'class?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Leave board')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('New board')),
        ],
      ),
    );
    if (!mounted) return;
    if (startNew != true) {
      Navigator.of(context).pop();
      return;
    }
    try {
      final session = await repo.newSession(classroom.id);
      final fresh = BoardController();
      fresh.onSlideChanged = _markDirty;
      fresh.addListener(() {
        _revision++;
        if (_lectureRecording && fresh.current != _lastSlideIndex) {
          _slideMarks.add({
            'index': fresh.current,
            'at': DateTime.now()
                    .difference(_audioStart ?? DateTime.now())
                    .inMilliseconds /
                1000.0,
          });
        }
        _lastSlideIndex = fresh.current;
        if (mounted) setState(() {});
      });
      _board?.dispose();
      setState(() {
        _session = session;
        _board = fresh;
        _endingClass = false;
        _lastSlideIndex = 0;
        _slideMarks.clear();
        _dirty.clear();
        _saveStatus = 'Saved';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fresh board ready — same classroom code.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _endingClass = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start a new board: $e')));
      }
    }
  }

  /// Imports a PDF from storage: each page becomes a slide background the
  /// teacher can draw on top of.
  Future<void> _importPdf() async {
    final classroom = widget.classroom;
    final session = _session;
    final board = _board;
    if (classroom == null || session == null || board == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Importing PDF pages onto the board…')));

      var imported = 0;
      await for (final page in Printing.raster(bytes, dpi: 110)) {
        if (imported >= 40) break; // sanity cap
        final png = await page.toPng();
        final path = await repo.uploadMedia(
            bytes: png, extension: 'png', contentType: 'image/png');
        final slide = BoardSlide(
          index: board.slides.length,
          backgroundUrl: repo.mediaUrl(path),
        );
        board.appendSlide(slide);
        await repo.saveSessionSlide(classroom.id, session.id, slide);
        imported++;
        if (mounted) setState(() {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(imported == 0
                ? 'Could not read any pages from that PDF.'
                : '$imported PDF pages added — draw right on top of them.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF import failed: $e')));
      }
    }
  }

  Future<void> _sharePdf() async {
    final board = _board;
    if (board == null) return;
    final classroom = widget.classroom;
    final label =
        classroom == null ? 'Practice board' : classroomLabel(classroom);
    final fileName =
        'kaksha-board-${classroom?.code.toLowerCase() ?? 'practice'}.pdf';
    try {
      final ok = await BoardPdf.share(
        slides: board.slides,
        title: 'Kaksha · $label',
        fileName: fileName,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nothing to export yet — the board is empty.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not build PDF: $e')));
      }
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _chrome,
        appBar: AppBar(backgroundColor: _chrome, foregroundColor: Colors.white),
        body: Center(
          child: Text(_loadError!,
              style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
        ),
      );
    }
    if (board == null) {
      return const Scaffold(
        backgroundColor: _chrome,
        body: Center(child: CircularProgressIndicator(color: Palette.marigold)),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: _chrome,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                board.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                board.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ,
                control: true, shift: true): board.redo,
            const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true, shift: true): board.redo,
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                board.copySelection,
            const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                board.copySelection,
            const SingleActivator(LogicalKeyboardKey.keyX, control: true):
                board.cutSelection,
            const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
                board.cutSelection,
            const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                board.paste,
            const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                board.paste,
            const SingleActivator(LogicalKeyboardKey.delete):
                board.deleteSelection,
            const SingleActivator(LogicalKeyboardKey.backspace):
                board.deleteSelection,
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                _TopBar(
                  board: board,
                  classroom: widget.classroom,
                  saveStatus: _saveStatus,
                  onZoomIn: () => _zoomAt(
                      Offset(_viewport.width / 2, _viewport.height / 2), 1.2),
                  onZoomOut: () => _zoomAt(
                      Offset(_viewport.width / 2, _viewport.height / 2), 0.84),
                  onFit: () => setState(_fit),
                  onSharePdf: _sharePdf,
                  scale: _scale,
                  recording: _lectureRecording,
                  onToggleRecording:
                      widget.classroom == null ? null : _toggleLectureRecording,
                  onHistory: widget.classroom == null
                      ? null
                      : () => showBoardHistory(context, widget.classroom!),
                  onImportPdf: widget.classroom == null ? null : _importPdf,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (isWide)
                        _SlidesRail(
                          board: board,
                          revision: _revision,
                          onDelete: _deleteSlide,
                        ),
                      Expanded(child: _buildCanvas(board)),
                    ],
                  ),
                ),
                if (!isWide)
                  SizedBox(
                    height: 92,
                    child: _SlidesRail(
                      board: board,
                      revision: _revision,
                      onDelete: _deleteSlide,
                      horizontal: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(BoardController board) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (!_fitted) {
        _fitted = true;
        _fit();
      }
      return ClipRect(
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: (e) => _pointerUp(e.pointer),
          onPointerCancel: (e) => _pointerUp(e.pointer),
          onPointerSignal: _pointerSignal,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: switch (board.tool) {
              BoardTool.pan => SystemMouseCursors.grab,
              BoardTool.select => SystemMouseCursors.precise,
              _ => SystemMouseCursors.basic,
            },
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                const Positioned.fill(child: ColoredBox(color: _chrome)),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform(
                    transform:
                        Matrix4.translationValues(_offset.dx, _offset.dy, 0)
                          ..scale(_scale, _scale, 1.0),
                    child: Container(
                      width: kCanvasSize.width,
                      height: kCanvasSize.height,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: SlideView(
                        slide: board.slide,
                        painter: SlidePainter(
                          strokes: board.slide.strokes,
                          active: board.active,
                          selected: board.selected,
                          marquee: board.marquee,
                          selectionBounds: board.selectionBounds(),
                          revision: _revision,
                          drawSheet: false,
                        ),
                      ),
                    ),
                  ),
                ),
                // Raised hands / chats from students pop up here.
                Positioned(
                  top: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final event in _popups.reversed.take(4))
                        _EventPopup(event: event),
                    ],
                  ),
                ),
                // Teachers see "End class" only on the final slide.
                if (widget.classroom != null &&
                    board.current == board.slides.length - 1)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                      ),
                      onPressed: _endingClass ? null : _endClass,
                      icon: _endingClass
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70))
                          : const Icon(Icons.stop_circle_outlined, size: 20),
                      label: Text(
                          _endingClass ? 'Ending class…' : 'End class'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Popup card shown on the teacher's board when a student raises a hand
/// or sends a chat message.
class _EventPopup extends StatelessWidget {
  final ClassEvent event;
  const _EventPopup({required this.event});

  @override
  Widget build(BuildContext context) {
    final isHand = event.kind == 'hand';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: _chromeLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isHand ? Palette.marigold : _chromeLine, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHand ? Icons.back_hand : Icons.chat_bubble_outline,
              color: isHand ? Palette.marigold : const Color(0xFF8FB8D8),
              size: 20,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isHand
                        ? '${event.studentName} raised a hand · slide ${event.slideIndex + 1}'
                        : event.studentName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                  if (!isHand)
                    Text(
                      event.body,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top toolbar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final BoardController board;
  final Classroom? classroom;
  final String saveStatus;
  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onSharePdf;
  final bool recording;
  final VoidCallback? onToggleRecording;
  final VoidCallback? onHistory;
  final VoidCallback? onImportPdf;

  const _TopBar({
    required this.board,
    required this.classroom,
    required this.saveStatus,
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onSharePdf,
    required this.recording,
    required this.onToggleRecording,
    required this.onHistory,
    required this.onImportPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: _chromeLight,
        border: Border(bottom: BorderSide(color: _chromeLine)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Leave board',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    classroom == null
                        ? 'Practice board'
                        : classroomLabel(classroom!),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(saveStatus,
                    style: TextStyle(
                        color: saveStatus == 'Saved'
                            ? const Color(0xFF7FB98A)
                            : Palette.marigold,
                        fontSize: 11)),
              ],
            ),
            _divider(),
            _ToolButton(
                icon: Icons.edit_outlined,
                label: 'Pen',
                active: board.tool == BoardTool.pen,
                onTap: () => board.setTool(BoardTool.pen)),
            _ToolButton(
                icon: Icons.brush_outlined,
                label: 'Highlighter',
                active: board.tool == BoardTool.highlighter,
                onTap: () => board.setTool(BoardTool.highlighter)),
            _ToolButton(
                icon: Icons.cleaning_services_outlined,
                label: 'Eraser',
                active: board.tool == BoardTool.eraser,
                onTap: () => board.setTool(BoardTool.eraser)),
            _ToolButton(
                icon: Icons.highlight_alt_outlined,
                label: 'Select',
                active: board.tool == BoardTool.select,
                onTap: () => board.setTool(BoardTool.select)),
            _ToolButton(
                icon: Icons.pan_tool_alt_outlined,
                label: 'Move canvas',
                active: board.tool == BoardTool.pan,
                onTap: () => board.setTool(BoardTool.pan)),
            _divider(),
            for (final c in kPenColors)
              _ColorDot(
                color: c,
                active: board.color.value == c.value,
                onTap: () => board.setColor(c),
              ),
            const SizedBox(width: 6),
            _WidthButton(board: board),
            _divider(),
            if (board.hasSelection) ...[
              _ActionButton(
                  icon: Icons.content_cut,
                  label: 'Cut',
                  onTap: board.cutSelection),
              _ActionButton(
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onTap: board.copySelection),
              _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete selection',
                  onTap: board.deleteSelection),
            ],
            if (board.hasClipboard)
              _ActionButton(
                  icon: Icons.content_paste,
                  label: 'Paste',
                  onTap: board.paste),
            if (board.hasSelection || board.hasClipboard) _divider(),
            _ActionButton(
                icon: Icons.undo,
                label: 'Undo (Ctrl+Z)',
                onTap: board.canUndo ? board.undo : null),
            _ActionButton(
                icon: Icons.redo,
                label: 'Redo (Ctrl+Shift+Z)',
                onTap: board.canRedo ? board.redo : null),
            _divider(),
            _ActionButton(
                icon: Icons.zoom_out, label: 'Zoom out', onTap: onZoomOut),
            InkWell(
              onTap: onFit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('${(scale * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            _ActionButton(
                icon: Icons.zoom_in, label: 'Zoom in', onTap: onZoomIn),
            _ActionButton(
                icon: Icons.fit_screen_outlined,
                label: 'Fit to screen',
                onTap: onFit),
            _divider(),
            _ActionButton(
              icon: Icons.delete_sweep_outlined,
              label: 'Clear slide',
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('Clear this slide?'),
                    content: const Text(
                        'Everything on the current slide will be erased. You can undo.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel')),
                      FilledButton(
                          style:
                              FilledButton.styleFrom(backgroundColor: Palette.red),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Clear')),
                    ],
                  ),
                );
                if (ok == true) board.clearSlide();
              },
            ),
            if (onImportPdf != null)
              _ActionButton(
                icon: Icons.upload_file_outlined,
                label: 'Import a PDF — teach on its pages',
                onTap: onImportPdf,
              ),
            _ActionButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Share board as PDF',
              onTap: onSharePdf,
            ),
            if (onToggleRecording != null)
              Tooltip(
                message: recording
                    ? 'Recording the lecture for class notes'
                    : 'Record the lecture (becomes class notes)',
                child: IconButton(
                  onPressed: onToggleRecording,
                  icon: Icon(
                    recording ? Icons.mic : Icons.mic_none,
                    size: 21,
                    color: recording ? const Color(0xFFE57373) : Colors.white70,
                  ),
                ),
              ),
            if (onHistory != null)
              _ActionButton(
                icon: Icons.history,
                label: 'Past boards (by date)',
                onTap: onHistory,
              ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: _chromeLine,
      );
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active ? Palette.marigold : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon,
                  size: 21, color: active ? _chrome : Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon,
            size: 21,
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.white70),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _ColorDot(
      {required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: active ? 26 : 20,
          height: active ? 26 : 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : Colors.white24,
              width: active ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthButton extends StatelessWidget {
  final BoardController board;
  const _WidthButton({required this.board});

  static const _widths = {'Fine': 2.5, 'Medium': 4.0, 'Bold': 7.0, 'Marker': 12.0};

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Stroke width',
      color: _chromeLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      initialValue: board.strokeWidth,
      onSelected: board.setWidth,
      itemBuilder: (_) => [
        for (final e in _widths.entries)
          PopupMenuItem(
            value: e.value,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: e.value.clamp(2, 12).toDouble(),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(e.key,
                    style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: board.strokeWidth == e.value ? 1 : 0.7),
                        fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 22,
              height: board.strokeWidth.clamp(2.0, 12.0),
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slides rail (vertical on wide screens, horizontal strip on phones)
// ---------------------------------------------------------------------------

class _SlidesRail extends StatelessWidget {
  final BoardController board;
  final int revision;
  final bool horizontal;
  final Future<void> Function(int index) onDelete;

  const _SlidesRail({
    required this.board,
    required this.revision,
    required this.onDelete,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      for (var i = 0; i < board.slides.length; i++)
        _SlideTile(
          slide: board.slides[i],
          number: i + 1,
          active: i == board.current,
          revision: revision,
          horizontal: horizontal,
          onTap: () => board.goTo(i),
          onDelete: board.slides.length > 1
              ? () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: Text('Delete slide ${i + 1}?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel')),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Palette.red),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) await onDelete(i);
                }
              : null,
        ),
      _AddSlideTile(horizontal: horizontal, onTap: board.addSlide),
    ];

    if (horizontal) {
      return Container(
        decoration: const BoxDecoration(
          color: _chromeLight,
          border: Border(top: BorderSide(color: _chromeLine)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(10),
          children: [
            for (final w in items)
              Padding(padding: const EdgeInsets.only(right: 10), child: w),
          ],
        ),
      );
    }

    return Container(
      width: 148,
      decoration: const BoxDecoration(
        color: _chromeLight,
        border: Border(right: BorderSide(color: _chromeLine)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final w in items)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        ],
      ),
    );
  }
}

class _SlideTile extends StatelessWidget {
  final BoardSlide slide;
  final int number;
  final bool active;
  final int revision;
  final bool horizontal;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _SlideTile({
    required this.slide,
    required this.number,
    required this.active,
    required this.revision,
    required this.horizontal,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? Palette.marigold : _chromeLine,
              width: active ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SlideThumbnail(slide: slide, revision: revision),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        if (onDelete != null)
          Positioned(
            right: 4,
            top: 4,
            child: InkWell(
              onTap: onDelete,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.close, size: 12, color: Colors.white70),
              ),
            ),
          ),
      ],
    );

    return SizedBox(
      width: horizontal ? 120 : null,
      child: GestureDetector(onTap: onTap, child: tile),
    );
  }
}

class _AddSlideTile extends StatelessWidget {
  final bool horizontal;
  final VoidCallback onTap;
  const _AddSlideTile({required this.horizontal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: horizontal ? 120 : null,
      child: AspectRatio(
        aspectRatio: kCanvasSize.aspectRatio,
        child: Material(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _chromeLine),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.white54, size: 20),
                  SizedBox(height: 2),
                  Text('New slide',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
