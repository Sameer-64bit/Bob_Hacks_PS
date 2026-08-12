import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/landing.dart';
import 'screens/setup_screen.dart';
import 'screens/student/student_dashboard.dart';
import 'screens/teacher/teacher_dashboard.dart';
import 'services/repository.dart';
import 'services/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // The legacy `anon` key keeps working here; kept for compatibility with
      // projects that haven't switched to the new publishable keys yet.
      // ignore: deprecated_member_use
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const KakshaApp());
}

class KakshaApp extends StatelessWidget {
  const KakshaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaksha',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AppConfig.isConfigured ? const _SplashGate() : const SetupScreen(),
    );
  }
}

/// Restores the saved session (if any) and routes to the right dashboard.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    Widget destination = const LandingScreen();
    try {
      final session = await SessionStore.load();
      if (session != null) {
        if (session.role == SessionRole.student) {
          final student = await repo.studentById(session.id);
          if (student != null) {
            destination = StudentDashboard(student: student);
          } else {
            await SessionStore.clear();
          }
        } else {
          final teacher = await repo.teacherById(session.id);
          if (teacher != null) {
            destination = TeacherDashboard(teacher: teacher);
          } else {
            await SessionStore.clear();
          }
        }
      }
    } catch (_) {
      // Network hiccup — land on the role picker; the user can sign in again.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Palette.navy)),
    );
  }
}
