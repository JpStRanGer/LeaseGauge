import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/data/period_tracking_recorder.dart';
import 'package:leasegauge/data/volvo_connection_client.dart';
import 'package:leasegauge/domain/lease_calculator.dart';
import 'package:leasegauge/domain/period_tracking.dart';
import 'package:leasegauge/widgets/info_help_button.dart';
import 'package:leasegauge/screens/lease_setup_screen.dart';
import 'package:leasegauge/screens/feedback_screen.dart';
import 'package:leasegauge/screens/legal_gate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _DisconnectScope { thisDevice, everywhere }

enum _VolvoRefreshFeedback { idle, loading, success }

class LeaseHomeScreen extends StatefulWidget {
  const LeaseHomeScreen({
    super.key,
    required this.storage,
    required this.trackingStore,
  });

  final LeaseFormStore storage;
  final PeriodTrackingStore trackingStore;

  @override
  State<LeaseHomeScreen> createState() => _LeaseHomeScreenState();
}

class _LeaseHomeScreenState extends State<LeaseHomeScreen> {
  static const _volvoEnabled = bool.fromEnvironment('LEASEGAUGE_VOLVO_ENABLED');
  LeaseFormValues? _plan;
  List<PeriodTrackingSession> _trackingSessions = [];
  String? _trackingError;
  bool _loading = true;
  bool _loadFailed = false;
  bool _savingOdometer = false;
  bool _volvoBusy = false;
  bool _volvoConnected = false;
  bool _latestOdometerIsFromVolvo = false;
  bool _manualOdometerEditing = false;
  bool _odometerDetailsExpanded = false;
  _VolvoRefreshFeedback _volvoRefreshFeedback = _VolvoRefreshFeedback.idle;
  String? _volvoMessage;
  DateTime? _volvoUpdatedAt;
  String? _selectedVolvoVehicleLabel;
  String? _selectedVolvoVehicleId;
  int? _volvoVehicleCount;
  VolvoConnectionClient? _volvoClient;
  VolvoPairing? _pairing;
  VolvoPairing? _phonePairing;
  DateTime? _pairDeadline;
  Timer? _pairTimer;
  bool _pairPolling = false;
  final _odometerController = TextEditingController();

  @override
  void dispose() {
    _pairTimer?.cancel();
    _volvoClient?.close();
    _odometerController.dispose();
    super.dispose();
  }

  void _setPlan(LeaseFormValues plan) {
    _plan = plan;
    _odometerController.text =
        plan.currentOdometerKm == plan.currentOdometerKm.roundToDouble()
        ? plan.currentOdometerKm.toStringAsFixed(0)
        : plan.currentOdometerKm.toString();
  }

  String get _manualCarKey => _selectedVolvoVehicleId == null
      ? 'manual-unassigned'
      : 'volvo-id:${_selectedVolvoVehicleId!}';

  Future<void> _recordVolvoReading(
    LeaseFormValues plan,
    VolvoOdometer reading,
    String vehicleId,
  ) async {
    if (_trackingError != null) return;
    final next = appendVolvoReading(
      sessions: _trackingSessions,
      plan: plan,
      vehicleId: vehicleId,
      kilometers: reading.kilometers,
      measuredAt: reading.vehicleUpdatedAt,
      receivedAt: DateTime.now(),
    );
    await widget.trackingStore.save(next);
    if (mounted) setState(() => _trackingSessions = next);
  }

  Future<void> _recordManualReading(
    LeaseFormValues plan,
    double kilometers,
    String carKey,
  ) async {
    if (_trackingError != null) {
      throw const FormatException(
        'Existing local history could not be read safely.',
      );
    }
    final next = appendManualReading(
      sessions: _trackingSessions,
      plan: plan,
      carKey: carKey,
      kilometers: kilometers,
      recordedAt: DateTime.now(),
    );
    await widget.trackingStore.save(next);
    if (mounted) {
      setState(() {
        _trackingSessions = next;
        _trackingError = null;
      });
    }
  }

  void _showVolvoMessage(String message) {
    if (!mounted) return;
    setState(() => _volvoMessage = message);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _saveOdometer() async {
    final plan = _plan;
    if (plan == null || _savingOdometer) return;
    final reading = double.tryParse(
      _odometerController.text.trim().replaceAll(',', '.'),
    );
    if (reading == null ||
        !reading.isFinite ||
        reading < plan.startOdometerKm ||
        reading < plan.currentOdometerKm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid reading at least as high as the last saved odometer.',
          ),
        ),
      );
      return;
    }
    if (reading == plan.currentOdometerKm) return;
    final manualCarKey = _manualCarKey;
    FocusScope.of(context).unfocus();
    setState(() => _savingOdometer = true);
    try {
      final updated = plan.withCurrentOdometer(reading);
      await widget.storage.save(updated);
      if (!mounted) return;
      String? historyWarning;
      try {
        await _recordManualReading(updated, reading, manualCarKey);
      } on Exception {
        historyWarning =
            'Odometer saved, but local period history could not be saved.';
        if (mounted) setState(() => _trackingError = historyWarning);
      }
      if (!mounted) return;
      setState(() {
        _setPlan(updated);
        _latestOdometerIsFromVolvo = false;
        _manualOdometerEditing = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            historyWarning ?? 'Odometer saved. Your budget is up to date.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the reading. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingOdometer = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_volvoEnabled) _volvoClient = VolvoConnectionClient();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await widget.storage.load();
      List<PeriodTrackingSession> trackingSessions = [];
      String? trackingError;
      try {
        trackingSessions = await widget.trackingStore.load();
      } on Exception {
        trackingError = 'Local period history could not be loaded.';
      }
      if (!mounted) return;
      setState(() {
        if (plan != null) _setPlan(plan);
        _trackingSessions = trackingSessions;
        _trackingError = trackingError;
        _loading = false;
        _loadFailed = false;
      });
      if (_volvoEnabled && plan != null) unawaited(_restoreAndRefreshVolvo());
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _restoreAndRefreshVolvo() async {
    try {
      final paired = await _volvoClient?.isPaired() ?? false;
      if (!mounted) return;
      setState(() => _volvoConnected = paired);
      if (paired) await _refreshVolvo(silent: true);
    } on Exception {
      // Manual entry remains usable if secure device storage is unavailable.
    }
  }

  Future<void> _refreshVolvo({
    bool silent = false,
    bool afterSelection = false,
  }) async {
    final client = _volvoClient;
    final plan = _plan;
    if (client == null || plan == null || (_volvoBusy && !afterSelection)) {
      return;
    }
    setState(() {
      _volvoBusy = true;
      if (!silent) {
        _volvoRefreshFeedback = _VolvoRefreshFeedback.loading;
        _volvoMessage = null;
      }
    });
    try {
      final reading = await client.readOdometer();
      if (!mounted) return;
      if (reading == null) {
        setState(() {
          _volvoConnected = false;
          _volvoUpdatedAt = null;
          _selectedVolvoVehicleLabel = null;
          _selectedVolvoVehicleId = null;
          _volvoVehicleCount = null;
          _latestOdometerIsFromVolvo = false;
          if (!silent) {
            _volvoRefreshFeedback = _VolvoRefreshFeedback.idle;
            _volvoMessage = 'Connect your Volvo to update automatically.';
          }
        });
        return;
      }
      final lowerReading = reading.kilometers < plan.currentOdometerKm;
      final newerReading = reading.kilometers > plan.currentOdometerKm;
      var replacedForSelectedCar = false;
      var currentReadingIsFromVolvo = false;
      if (lowerReading && afterSelection) {
        if (reading.kilometers < plan.startOdometerKm) {
          if (mounted && !silent) {
            _showVolvoMessage(
              'This car has a lower odometer than the start of this lease. Edit the plan before using it.',
            );
          }
        } else if (await _confirmLowerVehicleReading(reading, plan)) {
          final updated = plan.withCurrentOdometer(reading.kilometers);
          await widget.storage.save(updated);
          if (!mounted) return;
          setState(() => _setPlan(updated));
          replacedForSelectedCar = true;
          currentReadingIsFromVolvo = true;
        }
      } else if (reading.kilometers >= plan.currentOdometerKm) {
        final updated = plan.withCurrentOdometer(reading.kilometers);
        await widget.storage.save(updated);
        if (!mounted) return;
        setState(() => _setPlan(updated));
        currentReadingIsFromVolvo = true;
      }
      // The odometer endpoint supplies a label, not a stable vehicle ID.
      // Resolve the ID separately; never use a label to merge car histories.
      String? vehicleId;
      int? vehicleCount;
      try {
        final available = await client.readVehicles();
        vehicleCount = available.vehicles.length;
        vehicleId =
            available.selectedVehicleId ??
            (available.vehicles.length == 1
                ? available.vehicles.single.id
                : null);
        if (vehicleId != null &&
            !available.vehicles.any((vehicle) => vehicle.id == vehicleId)) {
          vehicleId = null;
        }
      } on Exception {
        // The existing odometer flow must remain usable if history cannot
        // safely identify the car.
      }
      if (!mounted) return;
      setState(() {
        _selectedVolvoVehicleId = vehicleId;
        _volvoVehicleCount = vehicleCount;
      });
      if (vehicleId != null &&
          (currentReadingIsFromVolvo || !lowerReading || !afterSelection)) {
        try {
          await _recordVolvoReading(_plan ?? plan, reading, vehicleId);
        } on Exception {
          if (mounted) {
            setState(
              () => _trackingError = 'Volvo updated the plan, but local period history could not be saved.',
            );
          }
        }
      }
      setState(() {
        _volvoConnected = true;
        _volvoUpdatedAt = reading.vehicleUpdatedAt;
        _selectedVolvoVehicleLabel = reading.vehicleLabel;
        _latestOdometerIsFromVolvo = currentReadingIsFromVolvo;
        _manualOdometerEditing = false;
        if (!silent) {
          _volvoRefreshFeedback = _VolvoRefreshFeedback.success;
          _volvoMessage = replacedForSelectedCar
              ? 'Car changed. The new car\'s odometer has replaced the previous reading.'
              : lowerReading
              ? afterSelection
                    ? 'Car changed, but you kept the previous odometer reading.'
                    : 'Volvo was checked. Its reading is older, so your saved value was kept.'
              : newerReading
              ? 'Updated from Volvo: ${reading.kilometers.toStringAsFixed(0)} km. Your budget is up to date.'
              : 'Volvo was checked. Your saved reading is already up to date.';
        }
      });
    } on VolvoVehicleSelectionRequired {
      if (mounted) {
        setState(() {
          _volvoConnected = true;
          _volvoRefreshFeedback = _VolvoRefreshFeedback.idle;
        });
        final selected = await _chooseVolvoVehicle(client);
        if (selected && mounted) {
          await _refreshVolvo(silent: silent, afterSelection: true);
        } else if (mounted && !silent) {
          _showVolvoMessage(
            'Choose the leased car before updating from Volvo. Manual entry remains available.',
          );
        }
      }
    } on Exception {
      if (mounted && !silent) {
        setState(() => _volvoRefreshFeedback = _VolvoRefreshFeedback.idle);
        _showVolvoMessage(
          'Could not get a new reading. Manual entry still works.',
        );
      }
    } finally {
      if (mounted) setState(() => _volvoBusy = false);
    }
  }

  Future<bool> _confirmLowerVehicleReading(
    VolvoOdometer reading,
    LeaseFormValues plan,
  ) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use the lower reading?'),
        content: Text(
          '${reading.vehicleLabel ?? 'The selected car'} reports '
          '${reading.kilometers.toStringAsFixed(0)} km. Your current plan '
          'uses ${plan.currentOdometerKm.toStringAsFixed(0)} km.\n\n'
          'This is expected when you deliberately switch to a different car. '
          'Use the lower reading only if this lease plan belongs to that car.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep current reading'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use new car reading'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _chooseVolvoVehicle(VolvoConnectionClient client) async {
    try {
      final available = await client.readVehicles();
      if (!mounted) return false;
      setState(() => _volvoVehicleCount = available.vehicles.length);
      if (available.vehicles.isEmpty) {
        _showVolvoMessage('No Volvo vehicles are available for this account.');
        return false;
      }
      final vehicle = await showDialog<VolvoVehicle>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose your leased car'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'More than one car is linked to this Volvo ID. LeaseGauge will only read the odometer from the car you choose on this device.',
                ),
                const SizedBox(height: 16),
                // Options are supplied only by the authenticated server. The
                // server validates the chosen id against Volvo before saving it.
                for (final vehicle in available.vehicles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(vehicle),
                      icon: const Icon(Icons.directions_car_rounded),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(vehicle.label),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (vehicle == null) return false;
      await client.selectVehicle(vehicle.id);
      if (mounted) {
        setState(() {
          _selectedVolvoVehicleLabel = vehicle.label;
          _selectedVolvoVehicleId = vehicle.id;
        });
      }
      return true;
    } on Exception {
      if (mounted) {
        _showVolvoMessage(
          'Could not load your Volvo vehicles. Please try again.',
        );
      }
      return false;
    }
  }

  Future<void> _connectVolvo() async {
    final client = _volvoClient;
    if (client == null || _volvoBusy) return;
    setState(() {
      _volvoBusy = true;
      _volvoMessage = null;
    });
    try {
      if (client.demoMultipleVehicles) {
        await client.reconnectDemo();
        if (!mounted) return;
        setState(() => _volvoConnected = true);
        await _refreshVolvo(afterSelection: true);
        return;
      }
      final pairing = await client.beginPairing();
      var launched = false;
      try {
        launched = await launchUrl(
          pairing.browserStartUrl ?? pairing.authorizationUrl,
          mode: LaunchMode.externalApplication,
        );
      } on Exception {
        // Some parked AAOS systems intentionally have no browser app.
      }
      if (!launched) {
        _startPairingPoll(
          pairing,
          message: 'Scan the QR code with your phone to sign in to Volvo.',
          showPhoneQr: true,
        );
        return;
      }
      _startPairingPoll(
        pairing,
        message:
            'Complete the Volvo sign-in in your browser, then return here.',
        showPhoneQr: false,
      );
    } on VolvoServiceUnavailable {
      _showVolvoMessage(
        'Volvo connection is not available yet. Enter the odometer manually for now.',
      );
    } on Exception {
      _showVolvoMessage(
        'Could not start Volvo sign-in. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _volvoBusy = false);
    }
  }

  void _startPairingPoll(
    VolvoPairing pairing, {
    required String message,
    required bool showPhoneQr,
  }) {
    if (!mounted) return;
    _pairTimer?.cancel();
    setState(() {
      _pairing = pairing;
      _phonePairing = showPhoneQr ? pairing : null;
      _pairDeadline = DateTime.now().add(const Duration(minutes: 10));
      _volvoMessage = message;
    });
    _pairTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollVolvoPairing()),
    );
  }

  void _cancelPhonePairing() {
    _pairTimer?.cancel();
    setState(() {
      _pairing = null;
      _phonePairing = null;
      _pairDeadline = null;
      _volvoMessage =
          'Volvo connection cancelled. Manual entry is still available.';
    });
  }

  Future<void> _pollVolvoPairing() async {
    final pairing = _pairing;
    final client = _volvoClient;
    if (pairing == null || client == null || _pairPolling) return;
    if (_pairDeadline != null && DateTime.now().isAfter(_pairDeadline!)) {
      _pairTimer?.cancel();
      _pairing = null;
      _phonePairing = null;
      _showVolvoMessage('Connection timed out. Please try again.');
      return;
    }
    _pairPolling = true;
    try {
      if (await client.completePairing(pairing)) {
        _pairTimer?.cancel();
        _pairing = null;
        _phonePairing = null;
        if (mounted) {
          setState(() {
            _volvoConnected = true;
            _volvoMessage = 'Volvo connected.';
          });
          await _refreshVolvo();
        }
      }
    } on Exception {
      _pairTimer?.cancel();
      _pairing = null;
      _phonePairing = null;
      _showVolvoMessage('Connection stopped. You can try again.');
    } finally {
      _pairPolling = false;
    }
  }

  Future<void> _disconnectVolvo() async {
    final client = _volvoClient;
    if (client == null || _volvoBusy) return;
    final scope = await showDialog<_DisconnectScope>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Volvo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('This device only'),
              subtitle: const Text('Other devices stay connected.'),
              onTap: () =>
                  Navigator.pop(dialogContext, _DisconnectScope.thisDevice),
            ),
            ListTile(
              title: const Text('Everywhere'),
              subtitle: const Text(
                'Disconnect the car, phone and other devices.',
              ),
              onTap: () =>
                  Navigator.pop(dialogContext, _DisconnectScope.everywhere),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    if (scope == _DisconnectScope.everywhere) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Disconnect on every device?'),
          content: const Text(
            'Volvo updates will stop on this phone, the car and every other connected device. Each device will need to connect again. Saved lease plans and mileage remain on each device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Disconnect everywhere'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _volvoBusy = true);
    try {
      if (scope == _DisconnectScope.thisDevice) {
        await client.disconnectThisDevice();
      } else {
        await client.disconnectEverywhere();
      }
      if (mounted) {
        setState(() {
          _volvoConnected = false;
          _volvoUpdatedAt = null;
          _selectedVolvoVehicleLabel = null;
          _selectedVolvoVehicleId = null;
          _volvoVehicleCount = null;
          _latestOdometerIsFromVolvo = false;
          _manualOdometerEditing = false;
          _volvoRefreshFeedback = _VolvoRefreshFeedback.idle;
          _volvoMessage = scope == _DisconnectScope.thisDevice
              ? 'Volvo disconnected on this device. Other devices stay connected.'
              : 'Volvo disconnected on every device. Manual entry is still available.';
        });
      }
    } on Exception {
      _showVolvoMessage('Could not disconnect. Please try again.');
    } finally {
      if (mounted) setState(() => _volvoBusy = false);
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
      _setPlan(savedPlan);
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
    final volvoUpdatedAt = _volvoUpdatedAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final volvoUpdatedLabel = volvoUpdatedAt == null
        ? null
        : '${localizations.formatMediumDate(volvoUpdatedAt)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(volvoUpdatedAt), alwaysUse24HourFormat: true)}';
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
    final trackingSession =
        plan == null || (_volvoConnected && _selectedVolvoVehicleId == null)
        ? null
        : activeTrackingSession(
            sessions: _trackingSessions,
            plan: plan,
            carKey: _manualCarKey,
          );
    final periodNow = DateTime.now();
    final periodBudgets = trackingSession == null
        ? null
        : {
            for (final period in BudgetPeriod.values)
              period: calculatePeriodBudget(
                baseline: trackingSession.baseline,
                readings: trackingSession.readings,
                now: periodNow,
                period: period,
              ),
          };
    final collapseOdometer =
        !_odometerDetailsExpanded &&
        !_volvoBusy &&
        _phonePairing == null &&
        _volvoRefreshFeedback != _VolvoRefreshFeedback.loading;

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
                      if (collapseOdometer)
                        Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const Key('expandOdometerStatus'),
                            onTap: () {
                              setState(() {
                                _odometerDetailsExpanded = true;
                                if (_volvoRefreshFeedback ==
                                    _VolvoRefreshFeedback.success) {
                                  _volvoRefreshFeedback =
                                      _VolvoRefreshFeedback.idle;
                                  _volvoMessage = null;
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _volvoConnected
                                        ? Icons.check_circle_rounded
                                        : Icons.edit_rounded,
                                    color: _volvoConnected
                                        ? const Color(0xFF176B49)
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _volvoConnected
                                              ? 'Volvo connected'
                                              : 'Manual odometer',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          !_volvoConnected
                                              ? 'Latest reading: ${_formatKm(plan.currentOdometerKm)}'
                                              : !_latestOdometerIsFromVolvo
                                              ? 'Manual reading: ${_formatKm(plan.currentOdometerKm)}'
                                              : _selectedVolvoVehicleLabel ==
                                                    null
                                              ? 'Latest odometer: ${_formatKm(plan.currentOdometerKm)}'
                                              : '${_selectedVolvoVehicleLabel!} · ${_formatKm(plan.currentOdometerKm)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const InfoHelpButton(
                                    key: Key('odometerHelpButton'),
                                    title: 'Current odometer',
                                    introduction: 'This is the odometer reading LeaseGauge currently uses in every mileage calculation.',
                                    items: [
                                      InfoHelpItem(
                                        heading: 'Where it comes from',
                                        description: 'A connected Volvo can supply the reading automatically. Otherwise, you enter and save it manually.',
                                      ),
                                      InfoHelpItem(
                                        heading: 'Manual changes',
                                        description: 'A manual reading changes LeaseGauge only. It never changes the value stored in your car.',
                                      ),
                                      InfoHelpItem(
                                        heading: 'How to use it',
                                        description: 'Keep this reading current. All remaining-distance and period figures depend on it.',
                                      ),
                                    ],
                                  ),
                                  const Text('Show'),
                                  const Icon(Icons.expand_more_rounded),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  key: const Key('collapseOdometerHeader'),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() {
                                    _odometerDetailsExpanded = false;
                                    if (_volvoRefreshFeedback ==
                                        _VolvoRefreshFeedback.success) {
                                      _volvoRefreshFeedback =
                                          _VolvoRefreshFeedback.idle;
                                      _volvoMessage = null;
                                    }
                                  }),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Current odometer',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      const InfoHelpButton(
                                        key: Key('odometerHelpButton'),
                                        title: 'Current odometer',
                                        introduction: 'This is the odometer reading LeaseGauge currently uses in every mileage calculation.',
                                        items: [
                                          InfoHelpItem(
                                            heading: 'Automatic reading',
                                            description: 'When Volvo is connected, LeaseGauge checks the selected car when the app starts and when you choose Update from Volvo.',
                                          ),
                                          InfoHelpItem(
                                            heading: 'Manual reading',
                                            description: 'You can still enter a value yourself. It changes LeaseGauge only and does not change your car.',
                                          ),
                                          InfoHelpItem(
                                            heading: 'Why it matters',
                                            description: 'The newest saved reading is the starting point for the remaining-distance and period calculations.',
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        tooltip: 'Hide odometer details',
                                        onPressed: () => setState(() {
                                          _odometerDetailsExpanded = false;
                                          if (_volvoRefreshFeedback ==
                                              _VolvoRefreshFeedback.success) {
                                            _volvoRefreshFeedback =
                                                _VolvoRefreshFeedback.idle;
                                            _volvoMessage = null;
                                          }
                                        }),
                                        icon: const Icon(
                                          Icons.expand_less_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _volvoConnected
                                      ? 'The latest reading comes from Volvo. You can also enter one manually.'
                                      : _volvoEnabled
                                      ? 'Enter a reading manually, or connect Volvo for automatic updates.'
                                      : 'Enter a reading manually.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _volvoConnected
                                          ? Icons.sync_rounded
                                          : Icons.edit_outlined,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _volvoConnected
                                          ? 'Volvo connected'
                                          : 'Manual entry',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _volvoConnected
                                      ? 'The app checks Volvo on a fresh launch or when you tap Update from Volvo. Manual entry stays available below.'
                                      : _volvoEnabled
                                      ? 'Connect your Volvo ID for updates when the app starts and on demand.'
                                      : 'Volvo updates are not available in this version.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_volvoEnabled) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      SizedBox(
                                        width: 156,
                                        child: FilledButton.icon(
                                          onPressed: _volvoBusy
                                              ? null
                                              : (_volvoConnected
                                                    ? () => _refreshVolvo()
                                                    : _connectVolvo),
                                          icon: Icon(
                                            _volvoBusy && _volvoConnected
                                                ? Icons.hourglass_top_rounded
                                                : _volvoConnected
                                                ? Icons.refresh_rounded
                                                : Icons.link_rounded,
                                          ),
                                          label: Text(
                                            _volvoConnected
                                                ? 'Update from Volvo'
                                                : 'Connect Volvo',
                                          ),
                                        ),
                                      ),
                                      if (_volvoConnected)
                                        SizedBox(
                                          width: 156,
                                          child: OutlinedButton.icon(
                                            onPressed: _volvoBusy
                                                ? null
                                                : _disconnectVolvo,
                                            icon: const Icon(
                                              Icons.link_off_rounded,
                                            ),
                                            label: const Text('Disconnect'),
                                          ),
                                        ),
                                      if (_volvoConnected &&
                                          (_volvoVehicleCount ?? 0) > 1)
                                        SizedBox(
                                          width: 156,
                                          child: OutlinedButton.icon(
                                            onPressed: _volvoBusy
                                                ? null
                                                : () async {
                                                    final client = _volvoClient;
                                                    if (client == null) return;
                                                    setState(
                                                      () => _volvoBusy = true,
                                                    );
                                                    final changed =
                                                        await _chooseVolvoVehicle(
                                                          client,
                                                        );
                                                    if (changed && mounted) {
                                                      await _refreshVolvo(
                                                        afterSelection: true,
                                                      );
                                                    }
                                                    if (mounted) {
                                                      setState(
                                                        () =>
                                                            _volvoBusy = false,
                                                      );
                                                    }
                                                  },
                                            icon: const Icon(
                                              Icons.directions_car_rounded,
                                            ),
                                            label: const Text('Change car'),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (_selectedVolvoVehicleLabel != null)
                                    Text(
                                      'Selected car: $_selectedVolvoVehicleLabel',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  if (volvoUpdatedLabel != null)
                                    Text(
                                      'Car last updated: $volvoUpdatedLabel',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  if (_phonePairing != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: 280,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Connect with your phone',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Scan this code with your phone, sign in to your Volvo ID, then keep this screen open. The car will connect automatically.',
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          DecoratedBox(
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: QrImageView(
                                                data: _phonePairing!
                                                    .authorizationUrl
                                                    .toString(),
                                                version: QrVersions.auto,
                                                size: 220,
                                                backgroundColor: Colors.white,
                                                errorCorrectionLevel:
                                                    QrErrorCorrectLevel.M,
                                                semanticsLabel:
                                                    'Volvo sign-in QR code',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: _cancelPhonePairing,
                                            child: const Text(
                                              'Cancel connection',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (_volvoRefreshFeedback !=
                                      _VolvoRefreshFeedback.idle) ...[
                                    const SizedBox(height: 12),
                                    Semantics(
                                      liveRegion: true,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        child: Container(
                                          key: ValueKey(_volvoRefreshFeedback),
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color:
                                                _volvoRefreshFeedback ==
                                                    _VolvoRefreshFeedback
                                                        .success
                                                ? const Color(0xFFE6F5EE)
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              if (_volvoRefreshFeedback ==
                                                  _VolvoRefreshFeedback.loading)
                                                const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                      ),
                                                )
                                              else
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  color: Color(0xFF176B49),
                                                  size: 24,
                                                ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _volvoRefreshFeedback ==
                                                          _VolvoRefreshFeedback
                                                              .loading
                                                      ? 'Reading the latest odometer from Volvo…'
                                                      : _volvoMessage ?? 'Volvo check complete.',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else if (_volvoMessage != null)
                                    Text(
                                      _volvoMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                                const SizedBox(height: 18),
                                if (_volvoConnected &&
                                    _latestOdometerIsFromVolvo &&
                                    !_manualOdometerEditing) ...[
                                  SizedBox(
                                    width: 320,
                                    child: TextField(
                                      controller: _odometerController,
                                      readOnly: true,
                                      enableInteractiveSelection: false,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Automatic reading from Volvo',
                                        helperText: _volvoUpdatedAt == null
                                            ? 'Retrieved from your selected Volvo.'
                                            : 'Retrieved from Volvo · $volvoUpdatedLabel',
                                        prefixIcon: const Icon(
                                          Icons.cloud_done_rounded,
                                        ),
                                        suffixText: 'km',
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    key: const Key('enterManualOdometerButton'),
                                    onPressed: () => setState(
                                      () => _manualOdometerEditing = true,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Enter a manual reading'),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(left: 12),
                                    child: Text(
                                      'Manual entry changes LeaseGauge only; it does not change Volvo.',
                                    ),
                                  ),
                                ] else ...[
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 250,
                                        child: TextField(
                                          key: const Key('quickOdometerField'),
                                          controller: _odometerController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: _volvoConnected
                                                ? 'Manual odometer reading'
                                                : 'Odometer reading',
                                            helperText: _volvoConnected
                                                ? 'This changes LeaseGauge only; it does not change Volvo.'
                                                : null,
                                            suffixText: 'km',
                                          ),
                                          onSubmitted: (_) => _saveOdometer(),
                                        ),
                                      ),
                                      FilledButton.icon(
                                        key: const Key('saveOdometerButton'),
                                        onPressed: _savingOdometer
                                            ? null
                                            : _saveOdometer,
                                        icon: const Icon(Icons.check_rounded),
                                        label: Text(
                                          _volvoConnected
                                              ? 'Save manual reading'
                                              : 'Save reading',
                                        ),
                                      ),
                                      if (_volvoConnected &&
                                          _manualOdometerEditing)
                                        TextButton(
                                          onPressed: () {
                                            FocusScope.of(context).unfocus();
                                            setState(() {
                                              _manualOdometerEditing = false;
                                              _setPlan(plan);
                                            });
                                          },
                                          child: const Text(
                                            'Cancel manual entry',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      _DailySuggestionCard(
                        value: _formatKm(budgets!.todayKm, signed: true),
                      ),
                      const SizedBox(height: 14),
                      _PeriodComparisonCard(
                        budgets: periodBudgets,
                        historyError: _trackingError,
                        formatKm: _formatKm,
                      ),
                      const SizedBox(height: 14),
                      _BalanceHero(
                        balance: _formatKm(budgets.totalKm, signed: true),
                        onTrack: budgets.totalKm >= 0,
                        returnDate: MaterialLocalizations.of(context)
                            .formatShortDate(plan.returnDate),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Other rolling suggestions',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These shares are recalculated from your latest saved odometer reading. They are not measured period balances.',
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
                                label: 'Suggested for the rest of this month',
                                value: _formatKm(
                                  budgets.currentMonthKm,
                                  signed: true,
                                ),
                              ),
                              _BudgetTile(
                                width: cardWidth,
                                icon: Icons.date_range_rounded,
                                label: 'Suggested for the rest of this week',
                                value: _formatKm(
                                  budgets.currentWeekKm,
                                  signed: true,
                                ),
                              ),
                              _BudgetTile(
                                width: cardWidth,
                                icon: Icons.today_rounded,
                                label: 'Suggested today',
                                value: _formatKm(budgets.todayKm, signed: true),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      _LocalTrackingCard(
                        manualReadingCount: _trackingSessions.fold<int>(
                          0,
                          (count, session) =>
                              count +
                              session.readings
                                  .where(
                                    (reading) =>
                                        reading.source ==
                                        OdometerReadingSource.manual,
                                  )
                                  .length,
                        ),
                        volvoReadingCount: _trackingSessions.fold<int>(
                          0,
                          (count, session) =>
                              count +
                              session.readings
                                  .where(
                                    (reading) =>
                                        reading.source ==
                                        OdometerReadingSource.volvo,
                                  )
                                  .length,
                        ),
                        error: _trackingError,
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lease snapshot',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const InfoHelpButton(
                            key: Key('leaseSnapshotHelpButton'),
                            title: 'Lease snapshot',
                            introduction: 'This is a summary of the lease details and calculated distances LeaseGauge is currently using.',
                            items: [
                              InfoHelpItem(
                                heading: 'Contract figures',
                                description: 'The allowance, starting odometer, commute plan and return date come from the plan you saved.',
                              ),
                              InfoHelpItem(
                                heading: 'Calculated figures',
                                description: 'Already driven, remaining distance and the commute reserve are recalculated from your latest saved odometer reading.',
                              ),
                              InfoHelpItem(
                                heading: 'If something looks wrong',
                                description: 'Check the current odometer and choose Edit plan to review the contract details.',
                              ),
                            ],
                          ),
                        ],
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
                        _volvoConnected
                            ? 'Your odometer is updated from the selected Volvo when the app opens and when you request an update. Manual entry remains available. Commutes are reserved only on your selected days, and budgets are spread evenly across calendar days.'
                            : 'Your odometer is entered manually for now; the app does not read the car automatically. Commutes are reserved only on your selected days, and budgets are spread evenly across calendar days.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('openFeedbackButton'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const FeedbackScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.feedback_outlined),
                        label: const Text('Send feedback'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const LegalDocumentLinks(),
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

class _LocalTrackingCard extends StatelessWidget {
  const _LocalTrackingCard({
    required this.manualReadingCount,
    required this.volvoReadingCount,
    required this.error,
  });

  final int manualReadingCount;
  final int volvoReadingCount;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message =
        error ??
        (manualReadingCount == 0 && volvoReadingCount == 0
            ? 'No readings saved on this device yet.'
            : volvoReadingCount == 0
            ? '$manualReadingCount manual reading${manualReadingCount == 1 ? '' : 's'} saved on this device.'
            : '$manualReadingCount manual and $volvoReadingCount Volvo reading${volvoReadingCount == 1 ? '' : 's'} saved on this device.');
    return Card(
      key: const Key('localTrackingCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Local reading history',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const InfoHelpButton(
                  key: Key('localTrackingHelpButton'),
                  title: 'Local reading history',
                  introduction: 'LeaseGauge keeps a small history of odometer readings on this device so it can measure driving within calendar periods.',
                  items: [
                    InfoHelpItem(
                      heading: 'Stored only here',
                      description: 'This history is not uploaded or synchronized. Another phone, browser or car installation can therefore have a different history.',
                    ),
                    InfoHelpItem(
                      heading: 'Why readings are needed',
                      description: 'A reading near the start of a period and a newer reading let LeaseGauge calculate how far you actually drove.',
                    ),
                    InfoHelpItem(
                      heading: 'Kept separate',
                      description: 'Different cars and substantial plan revisions use separate histories so their measurements are not mixed.',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 6),
            Text(
              'This history stays on this device. Different cars and plan revisions are kept separate.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodComparisonCard extends StatelessWidget {
  const _PeriodComparisonCard({
    required this.budgets,
    required this.historyError,
    required this.formatKm,
  });

  final Map<BudgetPeriod, PeriodBudget>? budgets;
  final String? historyError;
  final String Function(double, {bool signed}) formatKm;

  String _periodName(BudgetPeriod period) => switch (period) {
    BudgetPeriod.day => 'Today',
    BudgetPeriod.week => 'This week',
    BudgetPeriod.month => 'This month',
  };

  String _status(BudgetPeriod period, PeriodBudget? budget) {
    if (historyError != null) return 'Local history is unavailable.';
    if (budget == null) return 'Missing start reading on this device.';
    return switch (budget.basis) {
      PeriodBasis.measured =>
        'Driven: ${formatKm(budget.drivenKm!)} · remaining as of the last reading:',
      PeriodBasis.missingStart =>
        'Missing start-of-${period.name} reading. A reading now cannot recreate the start.',
      PeriodBasis.missingLatest =>
        'A newer odometer reading is needed to measure this period.',
      PeriodBasis.beforeTracking => 'Tracking has not started for this period.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('periodComparisonCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Calendar period comparison · new',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const InfoHelpButton(
                  key: Key('periodComparisonHelpButton'),
                  title: 'Calendar period comparison',
                  introduction: 'This compares an allowance for the current day, week and month with the distance actually measured in that period.',
                  items: [
                    InfoHelpItem(
                      heading: 'What is included',
                      description: 'These period figures cover all driving, including commuting. They are not the same as the leisure-only suggestions.',
                    ),
                    InfoHelpItem(
                      heading: 'How measurement works',
                      description: 'LeaseGauge needs a local odometer reading from the start of the period and a newer reading. If either is missing, the app explains what data is needed.',
                    ),
                    InfoHelpItem(
                      heading: 'Reading the result',
                      description: 'A positive remaining value means the measured driving is below the assigned allowance. A negative value means it is above it.',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'These allowances cover all driving, including planned commutes. They are separate from the rolling leisure suggestions below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final period in BudgetPeriod.values) ...[
              const Divider(height: 26),
              Text(
                _periodName(period),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                budgets == null
                    ? 'Assigned allowance: waiting for a local start reading'
                    : 'Assigned allowance: ${formatKm(budgets![period]!.allowanceKm)}',
              ),
              const SizedBox(height: 4),
              Text(
                _status(period, budgets?[period]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (budgets?[period]?.basis == PeriodBasis.measured) ...[
                const SizedBox(height: 4),
                Text(
                  formatKm(budgets![period]!.remainingKm!, signed: true),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Measured through ${MaterialLocalizations.of(context).formatMediumDate(budgets![period]!.measuredThrough!.toLocal())}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(budgets![period]!.measuredThrough!.toLocal()), alwaysUse24HourFormat: true)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DailySuggestionCard extends StatelessWidget {
  const _DailySuggestionCard({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('dailySuggestionCard'),
      margin: EdgeInsets.zero,
      color: const Color(0xFFEAF3F2),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suggested today',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const InfoHelpButton(
                  key: Key('dailySuggestionHelpButton'),
                  title: 'Suggested today',
                  introduction: 'This is a planning suggestion for leisure driving today, not a measurement of what you have driven today.',
                  items: [
                    InfoHelpItem(
                      heading: 'How it is calculated',
                      description: 'LeaseGauge first reserves distance for the commutes in your plan. It then spreads the remaining leisure distance evenly across the calendar days left in the lease.',
                    ),
                    InfoHelpItem(
                      heading: 'How to read it',
                      description: 'A positive number is the suggested room available today. A negative number means the plan is already over its calculated leisure allowance.',
                    ),
                    InfoHelpItem(
                      heading: 'It changes over time',
                      description: 'The suggestion is recalculated whenever the saved odometer or plan changes.',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A rolling share of your remaining leisure kilometres. This is not a measured balance for today.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
            Row(
              children: [
                const Icon(
                  Icons.directions_car_filled_rounded,
                  color: Color(0xFFB8F0E7),
                  size: 32,
                ),
                const Spacer(),
                const InfoHelpButton(
                  key: Key('balanceHelpButton'),
                  title: 'Leisure distance left',
                  introduction: 'This is the estimated distance available for non-commute driving until the car is returned.',
                  iconColor: Color(0xFFE5F5F4),
                  items: [
                    InfoHelpItem(
                      heading: 'How it is calculated',
                      description: 'LeaseGauge takes the contract distance still available and subtracts the distance reserved for your planned commutes.',
                    ),
                    InfoHelpItem(
                      heading: 'Positive or negative',
                      description: 'A positive value is available beyond the planned commuting. A negative value means the current plan exceeds the contract allowance.',
                    ),
                    InfoHelpItem(
                      heading: 'This is an estimate',
                      description: 'The result depends on the saved odometer, commute schedule and contract details being correct.',
                    ),
                  ],
                ),
              ],
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
              Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const Spacer(),
                  InfoHelpButton(
                    key: ValueKey('rollingBudgetHelpButton-$label'),
                    title: label,
                    introduction: 'This is a rolling leisure-driving suggestion for the named period. It is not a measurement of driving during that period.',
                    items: const [
                      InfoHelpItem(
                        heading: 'How it is calculated',
                        description: 'LeaseGauge reserves planned commuting, divides the remaining leisure distance across the calendar days left in the lease, and adds the relevant days in this period.',
                      ),
                      InfoHelpItem(
                        heading: 'How to read it',
                        description: 'A positive number suggests room for leisure driving. A negative number means the calculated leisure plan is over its allowance.',
                      ),
                      InfoHelpItem(
                        heading: 'Why it moves',
                        description: 'The value is recalculated from the newest saved odometer and is not preserved as a historical period balance.',
                      ),
                    ],
                  ),
                ],
              ),
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
