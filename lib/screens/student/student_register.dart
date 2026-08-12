import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../services/repository.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_dashboard.dart';

class StudentRegisterScreen extends StatefulWidget {
  const StudentRegisterScreen({super.key});

  @override
  State<StudentRegisterScreen> createState() => _StudentRegisterScreenState();
}

class _StudentRegisterScreenState extends State<StudentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _roll = TextEditingController();
  Branch _branch = kBranches.first;
  int _year = 1;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final (student, classroom) = await repo.registerStudent(
        name: _name.text.trim(),
        rollNo: _roll.text.trim().toUpperCase(),
        branchKey: _branch.key,
        year: _year,
      );
      await SessionStore.save(LocalSession(SessionRole.student, student.id));
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _WelcomeSheet(name: student.name, code: classroom.code),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => StudentDashboard(student: student)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final roll = await _askRollNumber(context);
    if (roll == null || roll.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final student = await repo.studentByRoll(roll.toUpperCase());
      if (student == null) {
        if (mounted) {
          showError(context, 'No student found with roll number $roll.');
        }
        return;
      }
      await SessionStore.save(LocalSession(SessionRole.student, student.id));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => StudentDashboard(student: student)),
        (_) => false,
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
    final years = List.generate(_branch.years, (i) => i + 1);
    return Scaffold(
      appBar: AppBar(title: const Text('Student registration')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join your classroom', style: text.displayMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Pick your programme and year — you are placed with your '
                    'batchmates automatically.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _roll,
                    decoration: const InputDecoration(
                        labelText: 'Roll number', hintText: 'e.g. CSJMA23001390105'),
                    validator: (v) =>
                        (v == null || v.trim().length < 3) ? 'Enter your roll number' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Branch>(
                    value: _branch,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Branch / programme'),
                    items: [
                      for (final b in kBranches)
                        DropdownMenuItem(
                            value: b,
                            child: Text(b.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (b) => setState(() {
                      _branch = b!;
                      if (_year > _branch.years) _year = 1;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _year,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text(yearName(y))),
                    ],
                    onChanged: (y) => setState(() => _year = y!),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _register,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Register & join classroom'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _signIn,
                      child: const Text('Already registered? Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _askRollNumber(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Sign in'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Roll number'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Sign in')),
      ],
    ),
  );
}

class _WelcomeSheet extends StatelessWidget {
  final String name;
  final String code;
  const _WelcomeSheet({required this.name, required this.code});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Palette.sage.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Palette.sage, size: 30),
          ),
          const SizedBox(height: 14),
          Text('Welcome, $name!', style: text.headlineMedium),
          const SizedBox(height: 6),
          Text('You are enrolled. Your classroom code is:',
              style: text.bodyMedium),
          const SizedBox(height: 12),
          CodeChip(code: code),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go to my dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}
