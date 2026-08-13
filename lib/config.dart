/// Supabase connection — supplied at build time, never committed.
///
/// Copy `env.example.json` to `env.json`, fill in your values, then run:
///   flutter run --dart-define-from-file=env.json
///
/// Get the values from Supabase Dashboard -> Project Settings -> API:
///   * Project URL  -> SUPABASE_URL
///   * anon public  -> SUPABASE_ANON_KEY
///
/// Individual flags work too:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// `env.json` is gitignored. With nothing supplied the app opens [SetupScreen]
/// instead of crashing.
class AppConfig {
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Deliberately empty — credentials do not live in source control.
  static const String _pastedUrl = '';
  static const String _pastedKey = '';

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
  static const String _pastedGeminiKey = 'local-proxy-mode';

  static String get geminiApiKey =>
      _envGeminiKey.isNotEmpty ? _envGeminiKey : _pastedGeminiKey;

  static bool get hasAi => true;
}
