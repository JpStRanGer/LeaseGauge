import 'package:flutter/material.dart';
import 'package:leasegauge/data/startup_reminder_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.languageCode,
    required this.onLanguageChanged,
    this.reminderController,
  });

  final String? languageCode;
  final Future<void> Function(String? languageCode) onLanguageChanged;
  final StartupReminderController? reminderController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final StartupReminderController _reminderController;
  bool _loadingReminder = true;
  bool _reminderSupported = false;
  bool _reminderEnabled = false;
  bool _savingReminder = false;

  @override
  void initState() {
    super.initState();
    _reminderController = widget.reminderController ?? StartupReminderService();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final supported = await _reminderController.isSupported();
    final enabled = supported && await _reminderController.isEnabled();
    if (!mounted) return;
    setState(() {
      _reminderSupported = supported;
      _reminderEnabled = enabled;
      _loadingReminder = false;
    });
  }

  Future<void> _setReminder(bool enabled) async {
    if (_savingReminder) return;
    setState(() => _savingReminder = true);
    try {
      await _reminderController.setEnabled(enabled);
      if (mounted) setState(() => _reminderEnabled = enabled);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The startup reminder could not be changed.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingReminder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Text(
                'Language',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('languageSelector'),
                initialValue: widget.languageCode,
                decoration: const InputDecoration(
                  labelText: 'App language',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Use system language'),
                  ),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'nb', child: Text('Norsk (bokmål)')),
                ],
                onChanged: widget.onLanguageChanged,
              ),
              const SizedBox(height: 32),
              Text(
                'Before-you-drive reminder',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  key: const Key('startupReminderSwitch'),
                  value: _reminderEnabled,
                  onChanged:
                      _loadingReminder || _savingReminder || !_reminderSupported
                      ? null
                      : _setReminder,
                  secondary: const Icon(Icons.notifications_none_rounded),
                  title: const Text('Remind me when the car system starts'),
                  subtitle: Text(
                    _loadingReminder
                        ? 'Checking this device…'
                        : _reminderSupported
                        ? 'Shows a quiet reminder at most once every 24 hours. '
                              'Tap it before driving to open LeaseGauge and update the odometer.'
                        : 'Available in the Android Automotive installation. '
                              'A car can wake from sleep without fully restarting, so a reminder cannot be guaranteed for every trip.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
