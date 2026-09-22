import 'package:leasegauge/domain/lease_calculator.dart';

/// A fixed starting point for one car and one revision of a lease plan.
/// Dates use the device's local calendar; reading timestamps are instants.
class PeriodTrackingBaseline {
  const PeriodTrackingBaseline({
    required this.carKey,
    required this.startedAt,
    required this.odometerKm,
    required this.remainingContractKm,
    required this.returnDate,
    required this.commuteRoundTripKm,
    required this.commuteWeekdays,
  });

  final String carKey;
  final DateTime startedAt;
  final double odometerKm;
  final double remainingContractKm;
  final DateTime returnDate;
  final double commuteRoundTripKm;
  final Set<int> commuteWeekdays;
}

enum OdometerReadingSource { manual, volvo }

class DatedOdometerReading {
  const DatedOdometerReading({
    required this.carKey,
    required this.kilometers,
    required this.source,
    required this.measuredAt,
    required this.receivedAt,
  });

  final String carKey;
  final double kilometers;
  final OdometerReadingSource source;
  final DateTime measuredAt;
  final DateTime receivedAt;
}

enum BudgetPeriod { day, week, month }

enum PeriodBasis { measured, missingStart, missingLatest, beforeTracking }

class PeriodBudget {
  const PeriodBudget({
    required this.period,
    required this.start,
    required this.end,
    required this.allowanceKm,
    required this.basis,
    this.drivenKm,
    this.remainingKm,
  });

  final BudgetPeriod period;
  final DateTime start;
  final DateTime end;
  final double allowanceKm;
  final PeriodBasis basis;
  final double? drivenKm;
  final double? remainingKm;
}

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime _periodStart(DateTime now, BudgetPeriod period) {
  final today = _date(now);
  return switch (period) {
    BudgetPeriod.day => today,
    BudgetPeriod.week => today.subtract(Duration(days: today.weekday - 1)),
    BudgetPeriod.month => DateTime.utc(today.year, today.month),
  };
}

DateTime _periodEnd(DateTime start, BudgetPeriod period) => switch (period) {
  BudgetPeriod.day => start.add(const Duration(days: 1)),
  BudgetPeriod.week => start.add(const Duration(days: 7)),
  BudgetPeriod.month => DateTime.utc(start.year, start.month + 1),
};

/// Distributes the *contract* balance at activation across remaining days.
/// Planned commute raises the assigned total-driving amount on commute days;
/// measured driving is never classified by purpose.
double assignedAllowanceKm({
  required PeriodTrackingBaseline baseline,
  required DateTime from,
  required DateTime until,
}) {
  final trackingStart = _date(baseline.startedAt);
  final contractEnd = _date(baseline.returnDate);
  final requestedStart = _date(from);
  final requestedEnd = _date(until);
  final start = requestedStart.isAfter(trackingStart)
      ? requestedStart
      : trackingStart;
  final end = requestedEnd.isBefore(contractEnd) ? requestedEnd : contractEnd;
  if (!start.isBefore(end) || !trackingStart.isBefore(contractEnd)) return 0;

  final remainingDays = contractEnd.difference(trackingStart).inDays;
  final commuteDays = countWorkdays(
    from: trackingStart,
    until: contractEnd,
    commuteWeekdays: baseline.commuteWeekdays,
  );
  final leisurePerDay =
      (baseline.remainingContractKm -
          commuteDays * baseline.commuteRoundTripKm) /
      remainingDays;
  final days = end.difference(start).inDays;
  final assignedCommuteDays = countWorkdays(
    from: start,
    until: end,
    commuteWeekdays: baseline.commuteWeekdays,
  );
  return days * leisurePerDay +
      assignedCommuteDays * baseline.commuteRoundTripKm;
}

/// Produces an exact period balance only when there is a reading at the
/// calendar boundary and a later reading for the *same car*. Sparse readings
/// cannot reconstruct a missing midnight odometer value.
PeriodBudget calculatePeriodBudget({
  required PeriodTrackingBaseline baseline,
  required Iterable<DatedOdometerReading> readings,
  required DateTime now,
  required BudgetPeriod period,
}) {
  final start = _periodStart(now, period);
  final end = _periodEnd(start, period);
  final allowance = assignedAllowanceKm(
    baseline: baseline,
    from: start,
    until: end,
  );
  if (now.isBefore(baseline.startedAt)) {
    return PeriodBudget(
      period: period,
      start: start,
      end: end,
      allowanceKm: allowance,
      basis: PeriodBasis.beforeTracking,
    );
  }

  final boundary = DateTime(start.year, start.month, start.day);
  if (boundary.isBefore(baseline.startedAt)) {
    return PeriodBudget(
      period: period,
      start: start,
      end: end,
      allowanceKm: allowance,
      basis: PeriodBasis.missingStart,
    );
  }

  final eligible =
      readings
          .where(
            (reading) =>
                reading.carKey == baseline.carKey &&
                reading.kilometers.isFinite &&
                reading.kilometers >= 0 &&
                !reading.measuredAt.isAfter(now) &&
                !reading.measuredAt.isAfter(reading.receivedAt),
          )
          .toList()
        ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  // Calendar boundaries are local instants. DateTime.utc above is only used
  // for day counting, which stays stable across daylight-saving transitions.
  DatedOdometerReading? first;
  DatedOdometerReading? latest;
  for (final reading in eligible) {
    if (reading.measuredAt.isAtSameMomentAs(boundary)) first = reading;
    if (!reading.measuredAt.isBefore(boundary) &&
        reading.measuredAt.isBefore(now.add(const Duration(microseconds: 1)))) {
      latest = reading;
    }
  }
  if (first == null) {
    return PeriodBudget(
      period: period,
      start: start,
      end: end,
      allowanceKm: allowance,
      basis: PeriodBasis.missingStart,
    );
  }
  if (latest == null || latest.measuredAt.isAtSameMomentAs(first.measuredAt)) {
    return PeriodBudget(
      period: period,
      start: start,
      end: end,
      allowanceKm: allowance,
      basis: PeriodBasis.missingLatest,
    );
  }
  final driven = latest.kilometers - first.kilometers;
  if (driven < 0) {
    return PeriodBudget(
      period: period,
      start: start,
      end: end,
      allowanceKm: allowance,
      basis: PeriodBasis.missingLatest,
    );
  }
  return PeriodBudget(
    period: period,
    start: start,
    end: end,
    allowanceKm: allowance,
    basis: PeriodBasis.measured,
    drivenKm: driven,
    remainingKm: allowance - driven,
  );
}
