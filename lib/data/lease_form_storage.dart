import 'package:shared_preferences/shared_preferences.dart';

class LeaseFormValues {
  const LeaseFormValues({
    required this.allowedDistanceKm,
    required this.startOdometerKm,
    required this.currentOdometerKm,
    required this.commuteDistanceKm,
    required this.returnDate,
  });

  final double allowedDistanceKm;
  final double startOdometerKm;
  final double currentOdometerKm;
  final double commuteDistanceKm;
  final DateTime returnDate;
}

abstract interface class LeaseFormStore {
  Future<LeaseFormValues?> load();

  Future<void> save(LeaseFormValues values);
}

class LeaseFormStorage implements LeaseFormStore {
  LeaseFormStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _allowedDistanceKey = 'lease.allowedDistanceKm';
  static const _startOdometerKey = 'lease.startOdometerKm';
  static const _currentOdometerKey = 'lease.currentOdometerKm';
  static const _commuteDistanceKey = 'lease.commuteDistanceKm';
  static const _returnDateKey = 'lease.returnDate';

  final SharedPreferencesAsync _preferences;

  @override
  Future<LeaseFormValues?> load() async {
    final allowedDistance = await _preferences.getDouble(_allowedDistanceKey);
    final startOdometer = await _preferences.getDouble(_startOdometerKey);
    final currentOdometer = await _preferences.getDouble(_currentOdometerKey);
    final commuteDistance = await _preferences.getDouble(_commuteDistanceKey);
    final returnDateText = await _preferences.getString(_returnDateKey);
    final returnDate = returnDateText == null
        ? null
        : DateTime.tryParse(returnDateText);

    if (allowedDistance == null ||
        startOdometer == null ||
        currentOdometer == null ||
        commuteDistance == null ||
        returnDate == null) {
      return null;
    }

    return LeaseFormValues(
      allowedDistanceKm: allowedDistance,
      startOdometerKm: startOdometer,
      currentOdometerKm: currentOdometer,
      commuteDistanceKm: commuteDistance,
      returnDate: returnDate,
    );
  }

  @override
  Future<void> save(LeaseFormValues values) async {
    await Future.wait([
      _preferences.setDouble(_allowedDistanceKey, values.allowedDistanceKm),
      _preferences.setDouble(_startOdometerKey, values.startOdometerKm),
      _preferences.setDouble(_currentOdometerKey, values.currentOdometerKm),
      _preferences.setDouble(_commuteDistanceKey, values.commuteDistanceKm),
      _preferences.setString(
        _returnDateKey,
        values.returnDate.toIso8601String(),
      ),
    ]);
  }
}
