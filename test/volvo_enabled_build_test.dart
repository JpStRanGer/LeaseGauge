import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/legal_acceptance_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/main.dart';

const _volvoEnabled = bool.fromEnvironment('LEASEGAUGE_VOLVO_ENABLED');

class _LeaseStore implements LeaseFormStore {
  LeaseFormValues? values = LeaseFormValues(
    allowedDistanceKm: 45000,
    startOdometerKm: 0,
    currentOdometerKm: 8140,
    commuteDistanceKm: 40,
    returnDate: DateTime.now().add(const Duration(days: 365)),
    commuteWeekdays: const {1, 2, 3, 4, 5},
  );

  @override
  Future<LeaseFormValues?> load() async => values;

  @override
  Future<void> save(LeaseFormValues values) async => this.values = values;
}

class _LegalStore implements LegalAcceptanceStore {
  @override
  Future<void> acceptCurrentTerms() async {}

  @override
  Future<bool> hasAcceptedCurrentTerms() async => true;
}

class _TrackingStore implements PeriodTrackingStore {
  @override
  Future<List<PeriodTrackingSession>> load() async => const [];

  @override
  Future<void> save(List<PeriodTrackingSession> sessions) async {}
}

void main() {
  testWidgets('Volvo-enabled builds expose the connection action', (
    tester,
  ) async {
    await tester.pumpWidget(
      LeaseGaugeApp(
        storage: _LeaseStore(),
        legalStore: _LegalStore(),
        trackingStore: _TrackingStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expandOdometerStatus')));
    await tester.pumpAndSettle();

    expect(find.text('Connect Volvo'), findsOneWidget);
    expect(
      find.text('Volvo updates are not available in this version.'),
      findsNothing,
    );
  }, skip: !_volvoEnabled);
}
