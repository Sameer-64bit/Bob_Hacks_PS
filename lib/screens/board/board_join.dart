import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../services/repository.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'board_screen.dart';

/// Smart board entry — type the classroom code shown on any student's or
/// teacher's dashboard and the panel becomes that class's board.
class BoardJoinScreen extends StatefulWidget {
  const BoardJoinScreen({super.key});

  @override
  State<BoardJoinScreen> createState() => _BoardJoinScreenState();
}

class _BoardJoinScreenState extends State<BoardJoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final classroom = await repo.classroomByCode(code);
      if (classroom == null) {
        if (mounted) {
          showError(context,
              'No classroom found for code $code. Check the dashboard and try again.');
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BoardScreen(classroom: classroom)),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFF20242B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF20242B),
        foregroundColor: Colors.white,
        title: const Text('Smart board',
            style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child:
                      const Icon(Icons.draw_outlined, color: Palette.marigold, size: 34),
                ),
                const SizedBox(height: 22),
                Text('Connect this board',
                    style: text.displayMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'Enter the classroom code from the student or teacher '
                  'dashboard. Everything drawn here is saved to that class.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'CSE1-XXXX',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 26,
                      letterSpacing: 4,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Palette.marigold, width: 1.6),
                    ),
                  ),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.marigold,
                      foregroundColor: const Color(0xFF20242B),
                    ),
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Open board'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const BoardScreen())),
                  child: Text(
                    'Or practice on a blank board',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small header used inside the board top bar.
String classroomLabel(Classroom c) =>
    '${branchByKey(c.branch).short} · ${yearName(c.year)} · ${c.code}';
