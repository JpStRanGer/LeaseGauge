import 'package:shared_preferences/shared_preferences.dart';

/// Increment this when the published terms change materially.
const currentTermsVersion = '2026-09-22.1';

abstract interface class LegalAcceptanceStore {
  Future<bool> hasAcceptedCurrentTerms();

  Future<void> acceptCurrentTerms();
}

class LocalLegalAcceptanceStore implements LegalAcceptanceStore {
  LocalLegalAcceptanceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _versionKey = 'legal.terms.version';
  static const _acceptedAtKey = 'legal.terms.acceptedAtUtc';

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> hasAcceptedCurrentTerms() async =>
      await _preferences.getString(_versionKey) == currentTermsVersion &&
      await _preferences.getString(_acceptedAtKey) != null;

  @override
  Future<void> acceptCurrentTerms() async {
    // Write the version last: an interrupted save must not count as acceptance.
    await _preferences.setString(
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    await _preferences.setString(_versionKey, currentTermsVersion);
  }
}
