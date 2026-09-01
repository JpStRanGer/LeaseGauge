import 'package:flutter/material.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/screens/lease_setup_screen.dart';

void main() {
  runApp(const LeaseGaugeApp());
}

class LeaseGaugeApp extends StatelessWidget {
  const LeaseGaugeApp({super.key, this.storage});

  final LeaseFormStore? storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LeaseGauge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: LeaseSetupScreen(storage: storage),
    );
  }
}
