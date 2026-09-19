import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/domain/lease_calculator.dart';

class LeaseSetupScreen extends StatefulWidget {
  const LeaseSetupScreen({
    super.key,
    required this.storage,
    this.initialValues,
  });

  final LeaseFormStore storage;
  final LeaseFormValues? initialValues;

  @override
  State<LeaseSetupScreen> createState() => _LeaseSetupScreenState();
}

class _LeaseSetupScreenState extends State<LeaseSetupScreen> {
  final _allowedDistanceController = TextEditingController();
  final _startOdometerController = TextEditingController();
  final _currentOdometerController = TextEditingController();
  final _commuteDistanceController = TextEditingController();
  DateTime? _returnDate;
  Set<int> _commuteWeekdays = {...defaultCommuteWeekdays};
  bool _saving = false;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    if (widget.initialValues case final values?) {
      _applyValues(values);
    } else {
      _loadSavedValues();
    }
  }

  void _applyValues(LeaseFormValues values) {
    _allowedDistanceController.text = _formatDistance(values.allowedDistanceKm);
    _startOdometerController.text = _formatDistance(values.startOdometerKm);
    _currentOdometerController.text = _formatDistance(values.currentOdometerKm);
    _commuteDistanceController.text = _formatDistance(values.commuteDistanceKm);
    _returnDate = values.returnDate;
    _commuteWeekdays = {...values.commuteWeekdays};
  }

  Future<void> _loadSavedValues() async {
    try {
      final values = await widget.storage.load();
      if (!mounted || values == null) return;
      setState(() => _applyValues(values));
    } on Exception {
      // The form can still be filled in when local storage is unavailable.
    }
  }

  @override
  void dispose() {
    _allowedDistanceController.dispose();
    _startOdometerController.dispose();
    _currentOdometerController.dispose();
    _commuteDistanceController.dispose();
    super.dispose();
  }

  String _formatDistance(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  double? _readDistance(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.'));
  }

  Future<void> _selectReturnDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final earliest = today.add(const Duration(days: 1));
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _returnDate != null && _returnDate!.isAfter(today)
          ? _returnDate!
          : today.add(const Duration(days: 365)),
      firstDate: earliest,
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (selectedDate != null && mounted) {
      setState(() => _returnDate = selectedDate);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _savePlan() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final allowedDistance = _readDistance(_allowedDistanceController);
    final startOdometer = _readDistance(_startOdometerController);
    final currentOdometer = _readDistance(_currentOdometerController);
    final commuteDistance = _readDistance(_commuteDistanceController);
    final returnDate = _returnDate;

    if (allowedDistance == null ||
        startOdometer == null ||
        currentOdometer == null ||
        commuteDistance == null ||
        returnDate == null) {
      _showMessage('Complete all fields and select a return date.');
      return;
    }

    if (!allowedDistance.isFinite ||
        !startOdometer.isFinite ||
        !currentOdometer.isFinite ||
        !commuteDistance.isFinite ||
        allowedDistance <= 0 ||
        startOdometer < 0 ||
        currentOdometer < startOdometer ||
        commuteDistance < 0 ||
        !returnDate.isAfter(DateUtils.dateOnly(DateTime.now()))) {
      _showMessage('Check the distances and return date you entered.');
      return;
    }

    final values = LeaseFormValues(
      allowedDistanceKm: allowedDistance,
      startOdometerKm: startOdometer,
      currentOdometerKm: currentOdometer,
      commuteDistanceKm: commuteDistance,
      returnDate: returnDate,
      commuteWeekdays: {..._commuteWeekdays},
    );

    setState(() => _saving = true);
    try {
      await widget.storage.save(values);
      if (!mounted) return;
      Navigator.of(context).pop(values);
    } on Exception {
      if (!mounted) return;
      _showMessage('Could not save on this device. Please try again.');
      setState(() => _saving = false);
    }
  }

  Widget _distanceField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        suffixText: 'km',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 44),
            children: [
              Text(
                'Make the plan yours',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'These details stay on this device. Change them whenever your lease or routine changes.',
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _FormSection(
                icon: Icons.description_outlined,
                title: 'Your lease',
                subtitle: 'The distance in your contract and when it ends.',
                children: [
                  _distanceField(
                    controller: _allowedDistanceController,
                    label: 'Total allowed distance',
                    hint: 'For example: 45000',
                  ),
                  const SizedBox(height: 16),
                  Text('Lease return date', style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('returnDateButton'),
                      onPressed: _selectReturnDate,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(
                        _returnDate == null
                            ? 'Choose a date'
                            : MaterialLocalizations.of(context)
                                  .formatShortDate(_returnDate!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormSection(
                icon: Icons.speed_rounded,
                title: 'Odometer',
                subtitle: 'Enter the dashboard reading manually for now.',
                children: [
                  _distanceField(
                    controller: _startOdometerController,
                    label: 'Odometer at lease start',
                    hint: 'For example: 10000',
                  ),
                  const SizedBox(height: 16),
                  _distanceField(
                    controller: _currentOdometerController,
                    label: 'Current odometer',
                    hint: 'For example: 25000',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormSection(
                icon: Icons.work_outline_rounded,
                title: 'Your commute',
                subtitle:
                    'We reserve this distance only on the days you select.',
                children: [
                  _distanceField(
                    controller: _commuteDistanceController,
                    label: 'Round trip per commute day',
                    hint: 'For example: 40',
                    helper: 'Home to work and back',
                  ),
                  const SizedBox(height: 18),
                  Text('Days you drive to work', style: textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Leave all days off if you do not commute by car.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (
                        var day = DateTime.monday;
                        day <= DateTime.sunday;
                        day++
                      )
                        FilterChip(
                          key: Key('commuteDay$day'),
                          label: Text(_dayLabels[day - 1]),
                          selected: _commuteWeekdays.contains(day),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _commuteWeekdays.add(day);
                              } else {
                                _commuteWeekdays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('savePlanButton'),
                  onPressed: _saving ? null : _savePlan,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Save plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
