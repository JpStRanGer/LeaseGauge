import 'package:shared_preferences/shared_preferences.dart';

const supportedLanguageCodes = <String>['en', 'nb'];

abstract interface class AppPreferencesStore {
  Future<String?> loadLanguageCode();
  Future<void> saveLanguageCode(String? languageCode);
}

class LocalAppPreferencesStore implements AppPreferencesStore {
  static const _languageCodeKey = 'app_language_code';

  @override
  Future<String?> loadLanguageCode() async {
    final value = (await SharedPreferences.getInstance()).getString(
      _languageCodeKey,
    );
    return supportedLanguageCodes.contains(value) ? value : null;
  }

  @override
  Future<void> saveLanguageCode(String? languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await preferences.remove(_languageCodeKey);
      return;
    }
    if (!supportedLanguageCodes.contains(languageCode)) {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
    await preferences.setString(_languageCodeKey, languageCode);
  }
}
