/// Supabase connection — paste your project values here.
///
/// Supabase Dashboard -> Project Settings -> API:
///   * Project URL  -> [supabaseUrl]
///   * anon public  -> [supabaseAnonKey]
///
/// They can also be passed at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Paste your values between the quotes below.
  static const String _pastedUrl = 'https://zxudswchxzfmfydulrvi.supabase.co';
  static const String _pastedKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4dWRzd2NoeHpmbWZ5ZHVscnZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MzI5ODIsImV4cCI6MjEwMjEwODk4Mn0.i6qbTyW2fnNkdF4enIIIJzCnTVY1pRHntVIFqyOisDU';

  static String get supabaseUrl => _envUrl.isNotEmpty ? _envUrl : _pastedUrl;
  static String get supabaseAnonKey => _envKey.isNotEmpty ? _envKey : _pastedKey;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
