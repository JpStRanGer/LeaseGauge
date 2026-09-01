import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/domain/lease_calculator.dart';

class LeaseSetupScreen extends StatefulWidget {
  const LeaseSetupScreen({super.key, this.storage});

  final LeaseFormStore? storage;

  @override
  State<LeaseSetupScreen> createState() {
    return _LeaseSetupScreenState();
  }
}

class _LeaseSetupScreenState extends State<LeaseSetupScreen> {
  late final LeaseFormStore _storage;
  final _allowedDistanceController = TextEditingController();
  final _startOdometerController = TextEditingController();
  final _currentOdometerController = TextEditingController();
  final _commuteDistanceController = TextEditingController();
  DateTime? _returnDate;
  LeaseCalculation? _calculation;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? LeaseFormStorage();
    _loadSavedValues();
  }

  @override
  void dispose() {
    _allowedDistanceController.dispose();
    _startOdometerController.dispose();
    _currentOdometerController.dispose();
    _commuteDistanceController.dispose();
    super.dispose();
  }

  Future<void> _selectReturnDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _returnDate ?? today.add(const Duration(days: 365)),
      firstDate: today,
      lastDate: DateTime(today.year + 10, 12, 31),
    );

    if (selectedDate == null) {
      return;
    }

    setState(() {
      _returnDate = selectedDate;
    });
  }

  double? _readDistance(TextEditingController controller) {
    final normalizedText = controller.text.trim().replaceAll(',', '.');
    return double.tryParse(normalizedText);
  }

  String _formatDistance(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  Future<void> _loadSavedValues() async {
    try {
      final savedValues = await _storage.load();
      if (!mounted || savedValues == null) {
        return;
      }

      _allowedDistanceController.text = _formatDistance(
        savedValues.allowedDistanceKm,
      );
      _startOdometerController.text = _formatDistance(
        savedValues.startOdometerKm,
      );
      _currentOdometerController.text = _formatDistance(
        savedValues.currentOdometerKm,
      );
      _commuteDistanceController.text = _formatDistance(
        savedValues.commuteDistanceKm,
      );

      setState(() {
        _returnDate = savedValues.returnDate;
      });
    } on Exception {
      // The form remains usable even if local storage is unavailable.
    }
  }

  Future<void> _calculateLease() async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete all fields and select a return date.'),
        ),
      );
      return;
    }

    if (allowedDistance <= 0 ||
        startOdometer < 0 ||
        currentOdometer < startOdometer ||
        commuteDistance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the distances you entered.')),
      );
      return;
    }

    final calculation = calculateLeaseForPeriod(
      allowedDistanceKm: allowedDistance,
      startOdometerKm: startOdometer,
      currentOdometerKm: currentOdometer,
      from: DateTime.now(),
      returnDate: returnDate,
      commuteRoundTripKm: commuteDistance,
    );

    setState(() {
      _calculation = calculation;
    });

    try {
      await _storage.save(
        LeaseFormValues(
          allowedDistanceKm: allowedDistance,
          startOdometerKm: startOdometer,
          currentOdometerKm: currentOdometer,
          commuteDistanceKm: commuteDistance,
          returnDate: returnDate,
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mileage plan saved on this device.')),
      );
    } on Exception {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The plan was calculated but could not be saved.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan your lease')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lease details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _allowedDistanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total allowed distance',
                    hintText: 'For example: 45000',
                    suffixText: 'km',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _startOdometerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Odometer at lease start',
                    hintText: 'For example: 10000',
                    suffixText: 'km',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _currentOdometerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Current odometer',
                    hintText: 'For example: 25000',
                    suffixText: 'km',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _commuteDistanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Commute distance per workday',
                    hintText: 'For example: 40',
                    helperText: 'Total distance from home to work and back',
                    suffixText: 'km',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Lease return date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _selectReturnDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      _returnDate == null
                          ? 'Select return date'
                          : MaterialLocalizations.of(context)
                                .formatMediumDate(_returnDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('calculateLeaseButton'),
                    onPressed: _calculateLease,
                    icon: const Icon(Icons.calculate),
                    label: const Text('Calculate mileage plan'),
                  ),
                ),
                if (_calculation != null) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your mileage plan',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Already driven: '
                            '${_calculation!.usedDistanceKm.toStringAsFixed(0)} km',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Remaining in lease: '
                            '${_calculation!.remainingContractKm.toStringAsFixed(0)} km',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Reserved for commuting: '
                            '${_calculation!.commuteReserveKm.toStringAsFixed(0)} km',
                          ),
                          const Divider(height: 32),
                          const Text('Available for leisure driving'),
                          const SizedBox(height: 4),
                          Text(
                            '${_calculation!.leisureDistanceKm.toStringAsFixed(0)} km',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: _calculation!.leisureDistanceKm >= 0
                                      ? Colors.green.shade700
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
