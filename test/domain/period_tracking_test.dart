import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/domain/period_tracking.dart';

void main() {
  final baseline = PeriodTrackingBaseline(
    carKey: 'car-a',
    startedAt: DateTime(2026, 9, 21, 10),
    odometerKm: 1000,
    remainingContractKm: 160,
    returnDate: DateTime(2026, 9, 28),
    commuteRoundTripKm: 10,
    commuteWeekdays: const {DateTime.monday, DateTime.tuesday},
  );

  test('assigned daily budgets sum to the entire remaining contract', () {
    final daily = List.generate(
      7,
      (offset) => assignedAllowanceKm(
        baseline: baseline,
        from: DateTime(2026, 9, 21 + offset),
        until: DateTime(2026, 9, 22 + offset),
      ),
    );
    expect(daily.reduce((a, b) => a + b), closeTo(160, 0.000001));
    expect(daily[0], 30); // 20 shared + 10 planned commute.
    expect(daily[2], 20); // No commute allocation on Wednesday.
  });

  test('first partial calendar periods never claim a precise balance', () {
    for (final period in BudgetPeriod.values) {
      final result = calculatePeriodBudget(
        baseline: baseline,
        readings: [],
        now: DateTime(2026, 9, 21, 11),
        period: period,
      );
      expect(result.basis, PeriodBasis.missingStart);
      expect(result.remainingKm, isNull);
    }
  });

  test('later day needs a real boundary measurement and a later reading', () {
    final start = DatedOdometerReading(
      carKey: 'car-a',
      kilometers: 1010,
      source: OdometerReadingSource.manual,
      measuredAt: DateTime(2026, 9, 23),
      receivedAt: DateTime(2026, 9, 23),
    );
    final end = DatedOdometerReading(
      carKey: 'car-a',
      kilometers: 1016,
      source: OdometerReadingSource.volvo,
      measuredAt: DateTime(2026, 9, 23, 14),
      receivedAt: DateTime(2026, 9, 23, 15),
    );
    final result = calculatePeriodBudget(
      baseline: baseline,
      readings: [start, end],
      now: DateTime(2026, 9, 23, 16),
      period: BudgetPeriod.day,
    );
    expect(result.basis, PeriodBasis.measured);
    expect(result.allowanceKm, 20);
    expect(result.drivenKm, 6);
    expect(result.remainingKm, 14);
  });

  test('another car cannot supply the missing start reading', () {
    final result = calculatePeriodBudget(
      baseline: baseline,
      readings: [
        DatedOdometerReading(
          carKey: 'car-b',
          kilometers: 99999,
          source: OdometerReadingSource.volvo,
          measuredAt: DateTime(2026, 9, 23),
          receivedAt: DateTime(2026, 9, 23),
        ),
      ],
      now: DateTime(2026, 9, 23, 16),
      period: BudgetPeriod.day,
    );
    expect(result.basis, PeriodBasis.missingStart);
  });
}
