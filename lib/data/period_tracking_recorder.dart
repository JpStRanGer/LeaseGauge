import 'dart:convert';

import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/domain/period_tracking.dart';

String _planSignature(LeaseFormValues plan) => jsonEncode([
  plan.allowedDistanceKm,
  plan.startOdometerKm,
  plan.commuteDistanceKm,
  plan.returnDate.year,
  plan.returnDate.month,
  plan.returnDate.day,
  plan.commuteWeekdays.toList()..sort(),
]);

/// Adds a successful manual reading without mutating existing history.
/// A different plan revision or car always starts a separate series.
List<PeriodTrackingSession> appendManualReading({
  required List<PeriodTrackingSession> sessions,
  required LeaseFormValues plan,
  required String carKey,
  required double kilometers,
  required DateTime recordedAt,
}) {
  if (carKey.isEmpty ||
      !kilometers.isFinite ||
      kilometers < plan.startOdometerKm) {
    throw const FormatException('Invalid manual odometer reading.');
  }
  final signature = _planSignature(plan);
  final reading = DatedOdometerReading(
    carKey: carKey,
    kilometers: kilometers,
    source: OdometerReadingSource.manual,
    measuredAt: recordedAt,
    receivedAt: recordedAt,
  );
  final next = [...sessions];
  final index = next.lastIndexWhere(
    (session) =>
        session.baseline.carKey == carKey &&
        session.baseline.planSignature == signature,
  );
  if (index == -1) {
    next.add(
      PeriodTrackingSession(
        id: recordedAt.toUtc().toIso8601String(),
        baseline: PeriodTrackingBaseline(
          carKey: carKey,
          startedAt: recordedAt,
          odometerKm: kilometers,
          remainingContractKm:
              plan.allowedDistanceKm - (kilometers - plan.startOdometerKm),
          returnDate: plan.returnDate,
          commuteRoundTripKm: plan.commuteDistanceKm,
          commuteWeekdays: plan.commuteWeekdays,
          planSignature: signature,
        ),
        readings: [reading],
      ),
    );
  } else {
    next[index] = next[index].withReading(reading);
  }
  return next;
}
