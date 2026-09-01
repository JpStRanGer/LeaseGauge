class LeaseCalculation {
  const LeaseCalculation({
    required this.usedDistanceKm,
    required this.remainingContractKm,
    required this.commuteReserveKm,
    required this.leisureDistanceKm,
  });

  final double usedDistanceKm;
  final double remainingContractKm;
  final double commuteReserveKm;
  final double leisureDistanceKm;
}

LeaseCalculation calculateLease({
  required double allowedDistanceKm,
  required double startOdometerKm,
  required double currentOdometerKm,
  required int remainingWorkdays,
  required double commuteRoundTripKm,
}) {
  final usedDistanceKm = currentOdometerKm - startOdometerKm;

  final remainingContractKm =
      allowedDistanceKm - usedDistanceKm;

  final commuteReserveKm =
      remainingWorkdays * commuteRoundTripKm;

  final leisureDistanceKm =
      remainingContractKm - commuteReserveKm;

  return LeaseCalculation(
    usedDistanceKm: usedDistanceKm,
    remainingContractKm: remainingContractKm,
    commuteReserveKm: commuteReserveKm,
    leisureDistanceKm: leisureDistanceKm,
  );
}
