import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/main.dart';

class _MemoryLeaseFormStore implements LeaseFormStore {
  _MemoryLeaseFormStore({this.values});

  LeaseFormValues? values;

  @override
  Future<LeaseFormValues?> load() async => values;

  @override
  Future<void> save(LeaseFormValues values) async {
    this.values = values;
  }
}

class _MemoryPeriodTrackingStore implements PeriodTrackingStore {
  List<PeriodTrackingSession> sessions = [];

  @override
  Future<List<PeriodTrackingSession>> load() async => sessions;

  @override
  Future<void> save(List<PeriodTrackingSession> sessions) async {
    this.sessions = sessions;
  }
}

class _UnreadablePeriodTrackingStore implements PeriodTrackingStore {
  bool saveCalled = false;

  @override
  Future<List<PeriodTrackingSession>> load() async {
    throw const FormatException('Unreadable local history');
  }

  @override
  Future<void> save(List<PeriodTrackingSession> sessions) async {
    saveCalled = true;
  }
}

void main() {
  testWidgets('quick odometer entry saves and updates the home budget', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLeaseFormStore(
      values: LeaseFormValues(
        allowedDistanceKm: 1000,
        startOdometerKm: 0,
        currentOdometerKm: 100,
        commuteDistanceKm: 0,
        returnDate: DateTime.now().add(const Duration(days: 30)),
        commuteWeekdays: const {},
      ),
    );
    final trackingStore = _MemoryPeriodTrackingStore();
    await tester.pumpWidget(
      LeaseGaugeApp(storage: store, trackingStore: trackingStore),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('+900 km'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+900 km'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('expandOdometerStatus')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Manual odometer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expandOdometerStatus')));
    await tester.pumpAndSettle();
    expect(find.text('Manual entry'), findsOneWidget);
    expect(
      find.text('Volvo updates are not available in this version.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('quickOdometerField')), '250');
    await tester.tap(find.byKey(const Key('saveOdometerButton')));
    await tester.pumpAndSettle();
    expect(store.values!.currentOdometerKm, 250);
    expect(trackingStore.sessions, hasLength(1));
    expect(trackingStore.sessions.single.readings, hasLength(1));
    expect(trackingStore.sessions.single.readings.single.kilometers, 250);
    await tester.scrollUntilVisible(
      find.text('+750 km'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+750 km'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('quickOdometerField')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('quickOdometerField')), '200');
    await tester.ensureVisible(find.byKey(const Key('saveOdometerButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveOdometerButton')));
    await tester.pump();
    expect(store.values!.currentOdometerKm, 250);
    expect(trackingStore.sessions.single.readings, hasLength(1));
    await tester.scrollUntilVisible(
      find.text('+750 km'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+750 km'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      LeaseGaugeApp(storage: store, trackingStore: trackingStore),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 manual reading saved on this device.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 manual reading saved on this device.'), findsOneWidget);
  });

  testWidgets('daily suggestion is prominent without changing old totals', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLeaseFormStore(
      values: LeaseFormValues(
        allowedDistanceKm: 1000,
        startOdometerKm: 0,
        currentOdometerKm: 100,
        commuteDistanceKm: 0,
        returnDate: DateTime.now().add(const Duration(days: 30)),
        commuteWeekdays: const {},
      ),
    );
    await tester.pumpWidget(
      LeaseGaugeApp(
        storage: store,
        trackingStore: _MemoryPeriodTrackingStore(),
      ),
    );
    await tester.pumpAndSettle();

    final dailyCard = find.byKey(const Key('dailySuggestionCard'));
    expect(dailyCard, findsOneWidget);
    expect(
      find.descendant(of: dailyCard, matching: find.text('+30 km')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('+900 km'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+900 km'), findsOneWidget);
    expect(
      find.text(
        'A rolling share of your remaining leisure kilometres. This is not a measured balance for today.',
      ),
      findsOneWidget,
    );
    expect(store.values!.currentOdometerKm, 100);
  });

  testWidgets(
    'new period comparison explains missing start without hiding suggestion',
    (WidgetTester tester) async {
      final store = _MemoryLeaseFormStore(
        values: LeaseFormValues(
          allowedDistanceKm: 1000,
          startOdometerKm: 0,
          currentOdometerKm: 100,
          commuteDistanceKm: 0,
          returnDate: DateTime.now().add(const Duration(days: 30)),
          commuteWeekdays: const {},
        ),
      );
      await tester.pumpWidget(
        LeaseGaugeApp(
          storage: store,
          trackingStore: _MemoryPeriodTrackingStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dailySuggestionCard')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('periodComparisonCard')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Calendar period comparison · new'), findsOneWidget);
      expect(
        find.text('Missing start reading on this device.'),
        findsNWidgets(3),
      );
      expect(store.values!.currentOdometerKm, 100);
    },
  );

  testWidgets('broken history does not prevent the old manual save', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLeaseFormStore(
      values: LeaseFormValues(
        allowedDistanceKm: 1000,
        startOdometerKm: 0,
        currentOdometerKm: 100,
        commuteDistanceKm: 0,
        returnDate: DateTime.now().add(const Duration(days: 30)),
        commuteWeekdays: const {},
      ),
    );
    final trackingStore = _UnreadablePeriodTrackingStore();
    await tester.pumpWidget(
      LeaseGaugeApp(storage: store, trackingStore: trackingStore),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expandOdometerStatus')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quickOdometerField')), '250');
    await tester.tap(find.byKey(const Key('saveOdometerButton')));
    await tester.pumpAndSettle();

    expect(store.values!.currentOdometerKm, 250);
    expect(trackingStore.saveCalled, isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const Key('localTrackingCard')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('localTrackingCard')),
        matching: find.text(
          'Odometer saved, but local period history could not be saved.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('home is an overview and opens a separate setup page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      LeaseGaugeApp(
        storage: _MemoryLeaseFormStore(),
        trackingStore: _MemoryPeriodTrackingStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LeaseGauge'), findsOneWidget);
    expect(
      find.text('A clearer view of your lease starts here'),
      findsOneWidget,
    );
    expect(find.text('Total allowed distance'), findsNothing);

    await tester.tap(find.byKey(const Key('createPlanButton')));
    await tester.pumpAndSettle();

    expect(find.text('Plan details'), findsOneWidget);
    expect(find.text('Total allowed distance'), findsOneWidget);
  });

  testWidgets('selected commute days are saved and shown on the overview', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLeaseFormStore(
      values: LeaseFormValues(
        allowedDistanceKm: 20000,
        startOdometerKm: 0,
        currentOdometerKm: 123,
        commuteDistanceKm: 40,
        returnDate: DateTime.now().add(const Duration(days: 365)),
      ),
    );
    await tester.pumpWidget(
      LeaseGaugeApp(
        storage: store,
        trackingStore: _MemoryPeriodTrackingStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your driving outlook'), findsOneWidget);
    expect(find.text('Total allowed distance'), findsNothing);

    await tester.tap(find.byKey(const Key('editPlanButton')));
    await tester.pumpAndSettle();
    expect(find.text('Make the plan yours'), findsOneWidget);

    final formScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('commuteDay1')),
      250,
      scrollable: formScroll,
    );
    await tester.ensureVisible(find.byKey(const Key('commuteDay1')));
    await tester.pumpAndSettle();
    final monday = tester.widget<FilterChip>(
      find.byKey(const Key('commuteDay1')),
    );
    expect(monday.selected, isTrue);
    await tester.tap(find.byKey(const Key('commuteDay1')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('savePlanButton')),
      250,
      scrollable: formScroll,
    );
    await tester.ensureVisible(find.byKey(const Key('savePlanButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePlanButton')));
    await tester.pumpAndSettle();

    expect(store.values!.commuteWeekdays, {
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    });
    expect(find.text('Your driving outlook'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tue, Wed, Thu, Fri'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Tue, Wed, Thu, Fri'), findsOneWidget);
  });

  testWidgets('no selected commute days leaves the full balance available', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLeaseFormStore(
      values: LeaseFormValues(
        allowedDistanceKm: 1000,
        startOdometerKm: 0,
        currentOdometerKm: 100,
        commuteDistanceKm: 40,
        returnDate: DateTime.now().add(const Duration(days: 30)),
        commuteWeekdays: const {},
      ),
    );
    await tester.pumpWidget(
      LeaseGaugeApp(
        storage: store,
        trackingStore: _MemoryPeriodTrackingStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('+900 km'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+900 km'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No commute days'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('No commute days'), findsOneWidget);
  });
}
