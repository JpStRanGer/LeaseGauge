import 'dart:convert';

import 'package:leasegauge/domain/period_tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A locally kept plan/car revision. Older sessions are retained when a plan
/// or selected car changes; their readings are never mixed with the new one.
class PeriodTrackingSession {
  const PeriodTrackingSession({
    required this.id,
    required this.baseline,
    required this.readings,
  });

  final String id;
  final PeriodTrackingBaseline baseline;
  final List<DatedOdometerReading> readings;

  PeriodTrackingSession withReading(DatedOdometerReading reading) {
    if (reading.carKey != baseline.carKey) {
      throw ArgumentError.value(reading.carKey, 'carKey', 'Wrong car');
    }
    if (!reading.kilometers.isFinite || reading.kilometers < 0) {
      throw ArgumentError.value(reading.kilometers, 'kilometers');
    }
    // A refresh of the same Volvo measurement is not another measurement.
    if (readings.any(
      (existing) =>
          existing.source == reading.source &&
          existing.measuredAt.isAtSameMomentAs(reading.measuredAt) &&
          existing.kilometers == reading.kilometers,
    )) {
      return this;
    }
    return PeriodTrackingSession(
      id: id,
      baseline: baseline,
      readings: [...readings, reading],
    );
  }
}

abstract interface class PeriodTrackingStore {
  Future<List<PeriodTrackingSession>> load();

  Future<void> save(List<PeriodTrackingSession> sessions);
}

/// Separate from the existing lease-plan keys so migration cannot overwrite
/// the user's plan or its current odometer value.
class LocalPeriodTrackingStore implements PeriodTrackingStore {
  LocalPeriodTrackingStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'lease.periodTracking.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<PeriodTrackingSession>> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported local period history');
    }
    final sessions = decoded['sessions'];
    if (sessions is! List) {
      throw const FormatException('Invalid local period history');
    }
    return sessions.map((item) {
      final json = item as Map<String, dynamic>;
      final baseline = json['baseline'] as Map<String, dynamic>;
      final readingItems = json['readings'] as List;
      return PeriodTrackingSession(
        id: json['id'] as String,
        baseline: PeriodTrackingBaseline(
          carKey: baseline['carKey'] as String,
          startedAt: DateTime.parse(baseline['startedAt'] as String),
          odometerKm: (baseline['odometerKm'] as num).toDouble(),
          remainingContractKm: (baseline['remainingContractKm'] as num)
              .toDouble(),
          returnDate: DateTime.parse(baseline['returnDate'] as String),
          commuteRoundTripKm: (baseline['commuteRoundTripKm'] as num)
              .toDouble(),
          commuteWeekdays: (baseline['commuteWeekdays'] as List)
              .map((day) => (day as num).toInt())
              .toSet(),
        ),
        readings: readingItems.map((item) {
          final reading = item as Map<String, dynamic>;
          return DatedOdometerReading(
            carKey: reading['carKey'] as String,
            kilometers: (reading['kilometers'] as num).toDouble(),
            source: OdometerReadingSource.values.byName(
              reading['source'] as String,
            ),
            measuredAt: DateTime.parse(reading['measuredAt'] as String),
            receivedAt: DateTime.parse(reading['receivedAt'] as String),
          );
        }).toList(),
      );
    }).toList();
  }

  @override
  Future<void> save(List<PeriodTrackingSession> sessions) async {
    final payload = {
      'version': 1,
      'sessions': sessions.map((session) {
        final baseline = session.baseline;
        return {
          'id': session.id,
          'baseline': {
            'carKey': baseline.carKey,
            'startedAt': baseline.startedAt.toUtc().toIso8601String(),
            'odometerKm': baseline.odometerKm,
            'remainingContractKm': baseline.remainingContractKm,
            'returnDate': baseline.returnDate.toIso8601String(),
            'commuteRoundTripKm': baseline.commuteRoundTripKm,
            'commuteWeekdays': baseline.commuteWeekdays.toList()..sort(),
          },
          'readings': session.readings
              .map(
                (reading) => {
                  'carKey': reading.carKey,
                  'kilometers': reading.kilometers,
                  'source': reading.source.name,
                  'measuredAt': reading.measuredAt.toUtc().toIso8601String(),
                  'receivedAt': reading.receivedAt.toUtc().toIso8601String(),
                },
              )
              .toList(),
        };
      }).toList(),
    };
    await _preferences.setString(_key, jsonEncode(payload));
  }
}
