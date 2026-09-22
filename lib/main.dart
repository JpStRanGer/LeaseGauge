import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/screens/lease_home_screen.dart';

void main() {
  runApp(const LeaseGaugeApp());
}

class LeaseGaugeApp extends StatelessWidget {
  const LeaseGaugeApp({super.key, this.storage, this.trackingStore});

  final LeaseFormStore? storage;
  final PeriodTrackingStore? trackingStore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF245A68),
      surface: const Color(0xFFF5F7F8),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LeaseGauge',
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
      home: LeaseHomeScreen(
        storage: storage ?? LeaseFormStorage(),
        trackingStore: trackingStore ?? LocalPeriodTrackingStore(),
      ),
    );
  }
}
