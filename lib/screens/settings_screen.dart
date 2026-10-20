import 'package:flutter/material.dart';
import 'package:leasegauge/data/startup_reminder_service.dart';
import 'package:leasegauge/l10n/app_localizations.dart';

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
        SnackBar(
          content: Text(
            context.tr('The startup reminder could not be changed.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingReminder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Text(
                context.tr('Language'),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('languageSelector'),
                initialValue: widget.languageCode,
                decoration: InputDecoration(
                  labelText: context.tr('App language'),
                  prefixIcon: const Icon(Icons.language_rounded),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.tr('Use system language')),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(context.tr('English')),
                  ),
                  DropdownMenuItem(
                    value: 'nb',
                    child: const Text('Norsk (bokmål)'),
                  ),
                ],
                onChanged: widget.onLanguageChanged,
              ),
              const SizedBox(height: 32),
              Text(
                context.tr('Before-you-drive reminder'),
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
                  title: Text(
                    context.tr('Remind me when the car system starts'),
                  ),
                  subtitle: Text(
                    _loadingReminder
                        ? context.tr('Checking this device…')
                        : _reminderSupported
                        ? context.tr(
                            'Shows a quiet reminder at most once every 24 hours. Tap it before driving to open LeaseGauge and update the odometer.',
                          )
                        : context.tr(
                            'Available in the Android Automotive installation. A car can wake from sleep without fully restarting, so a reminder cannot be guaranteed for every trip.',
                          ),
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
