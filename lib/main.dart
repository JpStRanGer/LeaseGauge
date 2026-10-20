import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:leasegauge/data/app_preferences.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/legal_acceptance_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/screens/lease_home_screen.dart';
import 'package:leasegauge/screens/legal_gate.dart';
import 'package:leasegauge/l10n/app_localizations.dart';

void main() {
  runApp(const LeaseGaugeApp());
}

class LeaseGaugeApp extends StatefulWidget {
  const LeaseGaugeApp({
    super.key,
    this.storage,
    this.trackingStore,
    this.legalStore,
    this.preferencesStore,
  });

  final LeaseFormStore? storage;
  final PeriodTrackingStore? trackingStore;
  final LegalAcceptanceStore? legalStore;
  final AppPreferencesStore? preferencesStore;

  @override
  State<LeaseGaugeApp> createState() => _LeaseGaugeAppState();
}

class _LeaseGaugeAppState extends State<LeaseGaugeApp> {
  late final AppPreferencesStore _preferencesStore;
  String? _languageCode;

  @override
  void initState() {
    super.initState();
    _preferencesStore = widget.preferencesStore ?? LocalAppPreferencesStore();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final languageCode = await _preferencesStore.loadLanguageCode();
    if (mounted) setState(() => _languageCode = languageCode);
  }

  Future<void> _setLanguage(String? languageCode) async {
    await _preferencesStore.saveLanguageCode(languageCode);
    if (mounted) setState(() => _languageCode = languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF245A68),
      surface: const Color(0xFFF5F7F8),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LeaseGauge',
      locale: _languageCode == null ? null : Locale(_languageCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7F8),
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: LegalGate(
        store: widget.legalStore ?? LocalLegalAcceptanceStore(),
        child: LeaseHomeScreen(
          storage: widget.storage ?? LeaseFormStorage(),
          trackingStore: widget.trackingStore ?? LocalPeriodTrackingStore(),
          languageCode: _languageCode,
          onLanguageChanged: _setLanguage,
        ),
      ),
    );
  }
}
