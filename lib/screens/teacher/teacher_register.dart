import 'package:flutter/material.dart';

import '../../services/repository.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import 'teacher_dashboard.dart';

class TeacherRegisterScreen extends StatefulWidget {
  const TeacherRegisterScreen({super.key});

  @override
  State<TeacherRegisterScreen> createState() => _TeacherRegisterScreenState();
}

class _TeacherRegisterScreenState extends State<TeacherRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _employeeId = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _employeeId.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final teacher = await repo.registerTeacher(
        name: _name.text.trim(),
        employeeId: _employeeId.text.trim().toUpperCase(),
      );
      await SessionStore.save(LocalSession(SessionRole.teacher, teacher.id));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => TeacherDashboard(teacher: teacher)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign in'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Employee ID'),
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
    if (id == null || id.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final teacher = await repo.teacherByEmployeeId(id.toUpperCase());
      if (teacher == null) {
        if (mounted) showError(context, 'No teacher found with employee ID $id.');
        return;
      }
      await SessionStore.save(LocalSession(SessionRole.teacher, teacher.id));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => TeacherDashboard(teacher: teacher)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher registration')),
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
                  Text('Set up your week', style: text.displayMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Register once, then upload your 7-day schedule. Classrooms '
                    'are created and matched with students automatically.',
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
                    controller: _employeeId,
                    decoration: const InputDecoration(
                        labelText: 'Employee ID', hintText: 'e.g. CSJMU-T-0042'),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Enter your employee ID'
                        : null,
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
                          : const Text('Register'),
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
