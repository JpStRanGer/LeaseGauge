import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/domain/lease_calculator.dart';

void main() {
  test('calculates remaining distance for leisure driving', () {
    final result = calculateLease(
      allowedDistanceKm: 45000,
      startOdometerKm: 10000,
      currentOdometerKm: 25000,
      remainingWorkdays: 100,
      commuteRoundTripKm: 40,
    );

    expect(result.usedDistanceKm, 15000);
    expect(result.remainingContractKm, 30000);
    expect(result.commuteReserveKm, 4000);
    expect(result.leisureDistanceKm, 26000);
  });

  test('counts weekdays and skips the weekend', () {
    final workdays = countWorkdays(
      from: DateTime(2026, 9, 7),
      until: DateTime(2026, 9, 14),
    );

    expect(workdays, 5);
  });

  test('calculates lease using the return date', () {
    final result = calculateLeaseForPeriod(
      allowedDistanceKm: 45000,
      startOdometerKm: 10000,
      currentOdometerKm: 25000,
      from: DateTime(2026, 9, 7),
      returnDate: DateTime(2026, 9, 14),
      commuteRoundTripKm: 40,
    );

    expect(result.usedDistanceKm, 15000);
    expect(result.remainingContractKm, 30000);
    expect(result.commuteReserveKm, 200);
    expect(result.leisureDistanceKm, 29800);
  });

  test('spreads leisure distance across month, week, and day', () {
    final result = calculateLeisureBudgets(
      leisureDistanceKm: 3000,
      from: DateTime(2026, 9, 1),
      returnDate: DateTime(2026, 10, 1),
    );

    expect(result.totalKm, 3000);
    expect(result.currentMonthKm, 3000);
    expect(result.currentWeekKm, 600);
    expect(result.todayKm, 100);
  });

  test('keeps negative budgets visible when the lease is over plan', () {
    final result = calculateLeisureBudgets(
      leisureDistanceKm: -3000,
      from: DateTime(2026, 9, 1),
      returnDate: DateTime(2026, 10, 1),
    );

    expect(result.totalKm, -3000);
    expect(result.currentMonthKm, -3000);
    expect(result.currentWeekKm, -600);
    expect(result.todayKm, -100);
  });
}
