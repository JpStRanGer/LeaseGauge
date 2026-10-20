import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/startup_reminder_service.dart';
import 'package:leasegauge/screens/settings_screen.dart';

class _ReminderController implements StartupReminderController {
  _ReminderController({required this.supported, this.enabled = false});

  final bool supported;
  bool enabled;
  int saves = 0;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<void> setEnabled(bool enabled) async {
    this.enabled = enabled;
    saves++;
  }
}

void main() {
  testWidgets('automotive user can opt in to the startup reminder', (
    tester,
  ) async {
    final controller = _ReminderController(supported: true);
    String? selectedLanguage;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          languageCode: null,
          onLanguageChanged: (value) async => selectedLanguage = value,
          reminderController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startupReminderSwitch')));
    await tester.pumpAndSettle();
    expect(controller.enabled, isTrue);
    expect(controller.saves, 1);

    await tester.tap(find.byKey(const Key('languageSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Norsk (bokmål)').last);
    await tester.pumpAndSettle();
    expect(selectedLanguage, 'nb');
  });

  testWidgets('startup reminder is disabled outside Android Automotive', (
    tester,
  ) async {
    final controller = _ReminderController(supported: false);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          languageCode: 'en',
          onLanguageChanged: (_) async {},
          reminderController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('startupReminderSwitch')),
    );
    expect(switchTile.onChanged, isNull);
    expect(find.textContaining('Android Automotive'), findsOneWidget);
  });
}
