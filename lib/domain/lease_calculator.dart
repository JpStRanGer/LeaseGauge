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

class LeisureBudgets {
  const LeisureBudgets({
    required this.totalKm,
    required this.currentMonthKm,
    required this.currentWeekKm,
    required this.todayKm,
  });

  final double totalKm;
  final double currentMonthKm;
  final double currentWeekKm;
  final double todayKm;
}

const defaultCommuteWeekdays = <int>{
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
};

LeaseCalculation calculateLease({
  required double allowedDistanceKm,
  required double startOdometerKm,
  required double currentOdometerKm,
  required int remainingWorkdays,
  required double commuteRoundTripKm,
}) {
  final usedDistanceKm = currentOdometerKm - startOdometerKm;

  final remainingContractKm = allowedDistanceKm - usedDistanceKm;

  final commuteReserveKm = remainingWorkdays * commuteRoundTripKm;

  final leisureDistanceKm = remainingContractKm - commuteReserveKm;

  return LeaseCalculation(
    usedDistanceKm: usedDistanceKm,
    remainingContractKm: remainingContractKm,
    commuteReserveKm: commuteReserveKm,
    leisureDistanceKm: leisureDistanceKm,
  );
}

int countWorkdays({
  required DateTime from,
  required DateTime until,
  Set<int> commuteWeekdays = defaultCommuteWeekdays,
}) {
  final startDate = DateTime.utc(from.year, from.month, from.day);

  final endDate = DateTime.utc(until.year, until.month, until.day);

  if (!startDate.isBefore(endDate)) {
    return 0;
  }

  var workdays = 0;

  for (
    var date = startDate;
    date.isBefore(endDate);
    date = date.add(const Duration(days: 1))
  ) {
    if (commuteWeekdays.contains(date.weekday)) {
      workdays++;
    }
  }

  return workdays;
}

LeaseCalculation calculateLeaseForPeriod({
  required double allowedDistanceKm,
  required double startOdometerKm,
  required double currentOdometerKm,
  required DateTime from,
  required DateTime returnDate,
  required double commuteRoundTripKm,
  Set<int> commuteWeekdays = defaultCommuteWeekdays,
}) {
  final remainingWorkdays = countWorkdays(
    from: from,
    until: returnDate,
    commuteWeekdays: commuteWeekdays,
  );

  return calculateLease(
    allowedDistanceKm: allowedDistanceKm,
    startOdometerKm: startOdometerKm,
    currentOdometerKm: currentOdometerKm,
    remainingWorkdays: remainingWorkdays,
    commuteRoundTripKm: commuteRoundTripKm,
  );
}

LeisureBudgets calculateLeisureBudgets({
  required double leisureDistanceKm,
  required DateTime from,
  required DateTime returnDate,
}) {
  final startDate = DateTime.utc(from.year, from.month, from.day);
  final endDate = DateTime.utc(
    returnDate.year,
    returnDate.month,
    returnDate.day,
  );
  final remainingDays = endDate.difference(startDate).inDays;

  if (remainingDays <= 0) {
    return LeisureBudgets(
      totalKm: leisureDistanceKm,
      currentMonthKm: 0,
      currentWeekKm: 0,
      todayKm: 0,
    );
  }

  final dailyBudgetKm = leisureDistanceKm / remainingDays;
  final nextMonth = DateTime.utc(startDate.year, startDate.month + 1);
  final nextMonday = startDate.add(
    Duration(days: DateTime.daysPerWeek + 1 - startDate.weekday),
  );
  final monthEnd = endDate.isBefore(nextMonth) ? endDate : nextMonth;
  final weekEnd = endDate.isBefore(nextMonday) ? endDate : nextMonday;

  return LeisureBudgets(
    totalKm: leisureDistanceKm,
    currentMonthKm: dailyBudgetKm * monthEnd.difference(startDate).inDays,
    currentWeekKm: dailyBudgetKm * weekEnd.difference(startDate).inDays,
    todayKm: dailyBudgetKm,
  );
}
