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
}
