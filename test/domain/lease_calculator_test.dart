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
}
