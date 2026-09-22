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

/// Select only the current car and unchanged plan terms for comparisons.
PeriodTrackingSession? activeTrackingSession({
  required List<PeriodTrackingSession> sessions,
  required LeaseFormValues plan,
  required String carKey,
}) {
  final signature = _planSignature(plan);
  for (final session in sessions.reversed) {
    if (session.baseline.carKey == carKey &&
        session.baseline.planSignature == signature) {
      return session;
    }
  }
  return null;
}

/// Adds a successful manual reading without mutating existing history.
/// A different plan revision or car always starts a separate series.
List<PeriodTrackingSession> appendManualReading({
  required List<PeriodTrackingSession> sessions,
  required LeaseFormValues plan,
  required String carKey,
  required double kilometers,
  required DateTime recordedAt,
}) {
  return _appendReading(
    sessions: sessions,
    plan: plan,
    carKey: carKey,
    kilometers: kilometers,
    measuredAt: recordedAt,
    receivedAt: recordedAt,
    source: OdometerReadingSource.manual,
  );
}

/// Records Volvo's measurement time, not the time of a repeated refresh.
/// A stable vehicle ID is required so readings from two cars cannot mix.
List<PeriodTrackingSession> appendVolvoReading({
  required List<PeriodTrackingSession> sessions,
  required LeaseFormValues plan,
  required String vehicleId,
  required double kilometers,
  required DateTime measuredAt,
  required DateTime receivedAt,
}) {
  if (vehicleId.isEmpty || measuredAt.isAfter(receivedAt)) {
    throw const FormatException('Invalid Volvo measurement.');
  }
  return _appendReading(
    sessions: sessions,
    plan: plan,
    carKey: 'volvo-id:$vehicleId',
    kilometers: kilometers,
    measuredAt: measuredAt,
    receivedAt: receivedAt,
    source: OdometerReadingSource.volvo,
  );
}

List<PeriodTrackingSession> _appendReading({
  required List<PeriodTrackingSession> sessions,
  required LeaseFormValues plan,
  required String carKey,
  required double kilometers,
  required DateTime measuredAt,
  required DateTime receivedAt,
  required OdometerReadingSource source,
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
    source: source,
    measuredAt: measuredAt,
    receivedAt: receivedAt,
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
        id: '${receivedAt.toUtc().toIso8601String()}:$carKey',
        baseline: PeriodTrackingBaseline(
          carKey: carKey,
          startedAt: receivedAt,
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
