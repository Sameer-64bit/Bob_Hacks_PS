/// Languages a student or teacher can set as their default. Slide
/// translation targets this language.
class AppLanguage {
  final String code;
  final String name; // English name, used in AI prompts
  final String native; // shown in the picker

  const AppLanguage(this.code, this.name, this.native);
}

const List<AppLanguage> kLanguages = [
  AppLanguage('en', 'English', 'English'),
  AppLanguage('hi', 'Hindi', 'हिन्दी'),
  AppLanguage('bn', 'Bengali', 'বাংলা'),
  AppLanguage('ta', 'Tamil', 'தமிழ்'),
  AppLanguage('te', 'Telugu', 'తెలుగు'),
  AppLanguage('mr', 'Marathi', 'मराठी'),
  AppLanguage('gu', 'Gujarati', 'ગુજરાતી'),
  AppLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
  AppLanguage('ur', 'Urdu', 'اردو'),
];

AppLanguage languageByCode(String code) =>
    kLanguages.firstWhere((l) => l.code == code, orElse: () => kLanguages.first);
