import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/domain/lease_calculator.dart';
import 'package:leasegauge/screens/lease_setup_screen.dart';

class LeaseHomeScreen extends StatefulWidget {
  const LeaseHomeScreen({super.key, required this.storage});

  final LeaseFormStore storage;

  @override
  State<LeaseHomeScreen> createState() => _LeaseHomeScreenState();
}

class _LeaseHomeScreenState extends State<LeaseHomeScreen> {
  LeaseFormValues? _plan;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await widget.storage.load();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
        _loadFailed = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _openEditor() async {
    final savedPlan = await Navigator.of(context).push<LeaseFormValues>(
      MaterialPageRoute(
        builder: (_) =>
            LeaseSetupScreen(storage: widget.storage, initialValues: _plan),
      ),
    );
    if (!mounted || savedPlan == null) return;
    setState(() {
      _plan = savedPlan;
      _loadFailed = false;
    });
  }

  String _formatNumber(double value) {
    return value.abs().round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  String _formatKm(double value, {bool signed = false}) {
    final prefix = value < 0 ? '−' : (signed && value > 0 ? '+' : '');
    return '$prefix${_formatNumber(value)} km';
  }

  String _commuteDaysLabel(Set<int> days) {
    if (days.isEmpty) return 'No commute days';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (days.toList()..sort()).map((day) => names[day - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final today = DateUtils.dateOnly(DateTime.now());
    final calculation = plan == null
        ? null
        : calculateLeaseForPeriod(
            allowedDistanceKm: plan.allowedDistanceKm,
            startOdometerKm: plan.startOdometerKm,
            currentOdometerKm: plan.currentOdometerKm,
            from: today,
            returnDate: plan.returnDate,
            commuteRoundTripKm: plan.commuteDistanceKm,
            commuteWeekdays: plan.commuteWeekdays,
          );
    final budgets = calculation == null
        ? null
        : calculateLeisureBudgets(
            leisureDistanceKm: calculation.leisureDistanceKm,
            from: today,
            returnDate: plan!.returnDate,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, size: 26),
            SizedBox(width: 10),
            Text('LeaseGauge', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          if (plan != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                key: const Key('editPlanButton'),
                onPressed: _openEditor,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Edit plan'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 44),
                  children: [
                    if (_loadFailed)
                      _EmptyPlan(
                        title: 'Could not load your plan',
                        description: 'Local storage is unavailable right now. You can still try to set up a plan.',
                        onEdit: _openEditor,
                      )
                    else if (plan == null)
                      _EmptyPlan(
                        title: 'A clearer view of your lease starts here',
                        description: 'Add your contract, odometer and commute schedule to see how much room is left for everyday adventures.',
                        onEdit: _openEditor,
                      )
                    else ...[
                      Text(
                        'Your driving outlook',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your lease at a glance, updated from the details you save.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _BalanceHero(
                        balance: _formatKm(budgets!.totalKm, signed: true),
                        onTrack: budgets.totalKm >= 0,
                        returnDate: MaterialLocalizations.of(context)
                            .formatShortDate(plan.returnDate),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Suggested leisure budget',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'An even share of your remaining leisure kilometres.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 660;
                          final cardWidth = narrow
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 24) / 3;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _BudgetTile(
                                width: cardWidth,
                                icon: Icons.calendar_month_rounded,
                                label: 'Rest of this month',
                                value: _formatKm(
                                  budgets.currentMonthKm,
                                  signed: true,
                                ),
                              ),
                              _BudgetTile(
                                width: cardWidth,
                                icon: Icons.date_range_rounded,
                                label: 'Rest of this week',
                                value: _formatKm(
                                  budgets.currentWeekKm,
                                  signed: true,
                                ),
                              ),
                              _BudgetTile(
                                width: cardWidth,
                                icon: Icons.today_rounded,
                                label: 'Today',
                                value: _formatKm(budgets.todayKm, signed: true),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Lease snapshot',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            children: [
                              _DetailRow(
                                label: 'Contract allowance',
                                value: _formatKm(plan.allowedDistanceKm),
                              ),
                              _DetailRow(
                                label: 'Already driven',
                                value: _formatKm(calculation!.usedDistanceKm),
                              ),
                              _DetailRow(
                                label: 'Remaining in contract',
                                value: _formatKm(
                                  calculation.remainingContractKm,
                                ),
                              ),
                              _DetailRow(
                                label: 'Reserved for commuting',
                                value: _formatKm(calculation.commuteReserveKm),
                              ),
                              _DetailRow(
                                label: 'Commute days',
                                value: _commuteDaysLabel(plan.commuteWeekdays),
                              ),
                              _DetailRow(
                                label: 'Return date',
                                value: MaterialLocalizations.of(context)
                                    .formatShortDate(plan.returnDate),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Your odometer is entered manually for now; the app does not read the car automatically. Commutes are reserved only on your selected days, and budgets are spread evenly across calendar days.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan({
    required this.title,
    required this.description,
    required this.onEdit,
  });

  final String title;
  final String description;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 36),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.explore_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(description),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('createPlanButton'),
              onPressed: onEdit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Set up your lease'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.balance,
    required this.onTrack,
    required this.returnDate,
  });

  final String balance;
  final bool onTrack;
  final String returnDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173A47), Color(0xFF276477)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.directions_car_filled_rounded,
              color: Color(0xFFB8F0E7),
              size: 32,
            ),
            const SizedBox(height: 26),
            const Text(
              'LEISURE DISTANCE LEFT',
              style: TextStyle(
                color: Color(0xFFC1DDE3),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                balance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              onTrack
                  ? 'On track · available beyond planned commuting'
                  : 'Over plan · reduce future driving if possible',
              style: const TextStyle(
                color: Color(0xFFE5F5F4),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Until $returnDate',
              style: const TextStyle(color: Color(0xFFC1DDE3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 18),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
