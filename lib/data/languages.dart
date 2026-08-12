/// Languages a student or teacher can set as their default. Slide
/// translation targets this language — the codes double as MyMemory
/// translation codes, so only add entries the free translator supports.
class AppLanguage {
  final String code;
  final String name; // English name, used in AI prompts
  final String native; // shown in the picker

  const AppLanguage(this.code, this.name, this.native);
}

const List<AppLanguage> kLanguages = [
  AppLanguage('en', 'English', 'English'),
  // Indian languages
  AppLanguage('hi', 'Hindi', 'हिन्दी'),
  AppLanguage('bn', 'Bengali', 'বাংলা'),
  AppLanguage('ta', 'Tamil', 'தமிழ்'),
  AppLanguage('te', 'Telugu', 'తెలుగు'),
  AppLanguage('mr', 'Marathi', 'मराठी'),
  AppLanguage('gu', 'Gujarati', 'ગુજરાતી'),
  AppLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
  AppLanguage('kn', 'Kannada', 'ಕನ್ನಡ'),
  AppLanguage('ml', 'Malayalam', 'മലയാളം'),
  AppLanguage('or', 'Odia', 'ଓଡ଼ିଆ'),
  AppLanguage('as', 'Assamese', 'অসমীয়া'),
  AppLanguage('ur', 'Urdu', 'اردو'),
  AppLanguage('ne', 'Nepali', 'नेपाली'),
  // International
  AppLanguage('es', 'Spanish', 'Español'),
  AppLanguage('fr', 'French', 'Français'),
  AppLanguage('de', 'German', 'Deutsch'),
  AppLanguage('ar', 'Arabic', 'العربية'),
  AppLanguage('zh-CN', 'Chinese (Simplified)', '中文'),
  AppLanguage('ja', 'Japanese', '日本語'),
];

AppLanguage languageByCode(String code) =>
    kLanguages.firstWhere((l) => l.code == code, orElse: () => kLanguages.first);
