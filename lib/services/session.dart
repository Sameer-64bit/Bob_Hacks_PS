import 'package:shared_preferences/shared_preferences.dart';

enum SessionRole { student, teacher }

/// Who is signed in on this device (kept locally, profile lives in Supabase).
class LocalSession {
  final SessionRole role;
  final String id; // row id in students/teachers

  const LocalSession(this.role, this.id);
}

class SessionStore {
  static const _kRole = 'session_role';
  static const _kId = 'session_id';

  static Future<LocalSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_kRole);
    final id = prefs.getString(_kId);
    if (role == null || id == null) return null;
    return LocalSession(
      role == 'teacher' ? SessionRole.teacher : SessionRole.student,
      id,
    );
  }

  static Future<void> save(LocalSession s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRole, s.role == SessionRole.teacher ? 'teacher' : 'student');
    await prefs.setString(_kId, s.id);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRole);
    await prefs.remove(_kId);
  }
}
