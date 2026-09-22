import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/period_tracking_recorder.dart';
import 'package:leasegauge/domain/period_tracking.dart';

void main() {
  final plan = LeaseFormValues(
    allowedDistanceKm: 1000,
    startOdometerKm: 100,
    currentOdometerKm: 250,
    commuteDistanceKm: 20,
    returnDate: DateTime(2027, 1),
    commuteWeekdays: const {DateTime.monday},
  );
  final firstAt = DateTime(2026, 9, 22, 14);

  test('manual readings retain time and append without rewriting the past', () {
    final first = appendManualReading(
      sessions: [],
      plan: plan,
      carKey: 'manual-unassigned',
      kilometers: 250,
      recordedAt: firstAt,
    );
    final later = appendManualReading(
      sessions: first,
      plan: plan.withCurrentOdometer(260),
      carKey: 'manual-unassigned',
      kilometers: 260,
      recordedAt: firstAt.add(const Duration(days: 1)),
    );

    expect(first.single.readings, hasLength(1));
    expect(later, hasLength(1));
    expect(later.single.readings, hasLength(2));
    expect(
      later.single.readings.last.measuredAt,
      firstAt.add(const Duration(days: 1)),
    );
    expect(later.single.readings.last.source, OdometerReadingSource.manual);
    expect(later.single.baseline.remainingContractKm, 850);
  });

  test('plan edits and car changes start separate histories', () {
    final first = appendManualReading(
      sessions: [],
      plan: plan,
      carKey: 'volvo-label:car-a',
      kilometers: 250,
      recordedAt: firstAt,
    );
    final changedPlan = LeaseFormValues(
      allowedDistanceKm: 1200,
      startOdometerKm: plan.startOdometerKm,
      currentOdometerKm: 260,
      commuteDistanceKm: plan.commuteDistanceKm,
      returnDate: plan.returnDate,
      commuteWeekdays: plan.commuteWeekdays,
    );
    final revised = appendManualReading(
      sessions: first,
      plan: changedPlan,
      carKey: 'volvo-label:car-a',
      kilometers: 260,
      recordedAt: firstAt.add(const Duration(hours: 1)),
    );
    final otherCar = appendManualReading(
      sessions: revised,
      plan: changedPlan,
      carKey: 'volvo-label:car-b',
      kilometers: 260,
      recordedAt: firstAt.add(const Duration(hours: 2)),
    );

    expect(first, hasLength(1));
    expect(revised, hasLength(2));
    expect(otherCar, hasLength(3));
    expect(otherCar.map((session) => session.baseline.carKey), [
      'volvo-label:car-a',
      'volvo-label:car-a',
      'volvo-label:car-b',
    ]);
  });

  test(
    'Volvo measurements use stable car IDs and repeated refreshes dedupe',
    () {
      final measured = DateTime.utc(2026, 9, 22, 12);
      final first = appendVolvoReading(
        sessions: [],
        plan: plan,
        vehicleId: 'vin-a',
        kilometers: 250,
        measuredAt: measured,
        receivedAt: measured.add(const Duration(minutes: 5)),
      );
      final refreshed = appendVolvoReading(
        sessions: first,
        plan: plan,
        vehicleId: 'vin-a',
        kilometers: 250,
        measuredAt: measured,
        receivedAt: measured.add(const Duration(minutes: 10)),
      );
      final secondCar = appendVolvoReading(
        sessions: refreshed,
        plan: plan,
        vehicleId: 'vin-b',
        kilometers: 400,
        measuredAt: measured,
        receivedAt: measured.add(const Duration(minutes: 11)),
      );

      expect(refreshed.single.readings, hasLength(1));
      expect(refreshed.single.readings.single.measuredAt, measured);
      expect(secondCar, hasLength(2));
      expect(secondCar.last.baseline.carKey, 'volvo-id:vin-b');
      expect(
        activeTrackingSession(
          sessions: secondCar,
          plan: plan,
          carKey: 'volvo-id:vin-a',
        )?.readings,
        hasLength(1),
      );
    },
  );
}
