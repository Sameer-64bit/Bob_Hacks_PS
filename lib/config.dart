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

  // ---------------------------------------------------------------------
  // Google Gemini API key — powers "Translate slide" and "Describe slide"
  // for students. Get one at aistudio.google.com/apikey.
  // Optional: without it the AI buttons show a setup hint instead.
  // ---------------------------------------------------------------------
  // SECURITY: never commit a real key here — GitHub blocks the push and the
  // key could be abused if the repo is public. Pass it at build time instead:
  //   flutter run --dart-define=GEMINI_API_KEY=your-key
  static const String _envGeminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _pastedGeminiKey = '';

  static String get geminiApiKey =>
      _envGeminiKey.isNotEmpty ? _envGeminiKey : _pastedGeminiKey;

  static bool get hasAi => geminiApiKey.isNotEmpty;
}
