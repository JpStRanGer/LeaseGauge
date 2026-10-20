import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/startup_reminder_service.dart';
import 'package:leasegauge/l10n/app_localizations.dart';
import 'package:leasegauge/screens/settings_screen.dart';

class _ReminderController implements StartupReminderController {
  _ReminderController({required this.supported});

  final bool supported;
  bool enabled = false;
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

  testWidgets('settings are available in Norwegian Bokmal', (tester) async {
    final controller = _ReminderController(supported: true);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nb'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsScreen(
          languageCode: 'nb',
          onLanguageChanged: (_) async {},
          reminderController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Innstillinger'), findsOneWidget);
    expect(find.text('Språk'), findsOneWidget);
    expect(find.text('Påminnelse før kjøreturen'), findsOneWidget);
    expect(find.text('Norsk (bokmål)'), findsOneWidget);
  });
}
