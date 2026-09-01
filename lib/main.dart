import 'package:flutter/material.dart';

void main() {
  runApp(const LeaseGaugeApp());
}

class LeaseGaugeApp extends StatelessWidget {
  const LeaseGaugeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LeaseGauge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LeaseGauge'),
        ),
        body: const Center(
          child: Text(
            'Know your mileage. Keep your lease on track.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}