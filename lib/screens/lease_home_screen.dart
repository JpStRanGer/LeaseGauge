import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/volvo_connection_client.dart';
import 'package:leasegauge/domain/lease_calculator.dart';
import 'package:leasegauge/screens/lease_setup_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _DisconnectScope { thisDevice, everywhere }

enum _VolvoRefreshFeedback { idle, loading, success }

class LeaseHomeScreen extends StatefulWidget {
  const LeaseHomeScreen({super.key, required this.storage});

  final LeaseFormStore storage;

  @override
  State<LeaseHomeScreen> createState() => _LeaseHomeScreenState();
}

class _LeaseHomeScreenState extends State<LeaseHomeScreen> {
  static const _volvoEnabled = bool.fromEnvironment('LEASEGAUGE_VOLVO_ENABLED');
  LeaseFormValues? _plan;
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
    FocusScope.of(context).unfocus();
    setState(() => _savingOdometer = true);
    try {
      final updated = plan.withCurrentOdometer(reading);
      await widget.storage.save(updated);
      if (!mounted) return;
      setState(() {
        _setPlan(updated);
        _latestOdometerIsFromVolvo = false;
        _manualOdometerEditing = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Odometer saved. Your budget is up to date.'),
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
      if (!mounted) return;
      setState(() {
        if (plan != null) _setPlan(plan);
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
      if (available.vehicles.isEmpty) {
        _showVolvoMessage('No Volvo vehicles are available for this account.');
        return false;
      }
      final vehicle = await showDialog<VolvoVehicle>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose your leased car'),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'More than one car is linked to this Volvo ID. LeaseGauge will only read the odometer from the car you choose on this device.',
              ),
            ),
            // Options are supplied only by the authenticated server. The
            // server validates the chosen id against Volvo before saving it.
            for (final vehicle in available.vehicles)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(vehicle),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(vehicle.label),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Cancel'),
              ),
            ),
          ],
        ),
      );
      if (vehicle == null) return false;
      await client.selectVehicle(vehicle.id);
      if (mounted) setState(() => _selectedVolvoVehicleLabel = vehicle.label);
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
                                Chip(
                                  avatar: Icon(
                                    _volvoConnected
                                        ? Icons.sync_rounded
                                        : Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _volvoConnected
                                        ? 'Volvo connected'
                                        : 'Manual entry',
                                  ),
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
                                      TextButton.icon(
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
                                      if (_volvoConnected)
                                        TextButton(
                                          onPressed: _volvoBusy
                                              ? null
                                              : _disconnectVolvo,
                                          child: const Text('Disconnect'),
                                        ),
                                      if (_volvoConnected)
                                        TextButton(
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
                                                      () => _volvoBusy = false,
                                                    );
                                                  }
                                                },
                                          child: const Text('Change car'),
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
                        _volvoConnected
                            ? 'Your odometer is updated from the selected Volvo when the app opens and when you request an update. Manual entry remains available. Commutes are reserved only on your selected days, and budgets are spread evenly across calendar days.'
                            : 'Your odometer is entered manually for now; the app does not read the car automatically. Commutes are reserved only on your selected days, and budgets are spread evenly across calendar days.',
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
