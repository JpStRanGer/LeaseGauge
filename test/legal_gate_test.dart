import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/legal_acceptance_storage.dart';
import 'package:leasegauge/screens/legal_gate.dart';

class _MemoryLegalStore implements LegalAcceptanceStore {
  bool accepted = false;
  bool failSave = false;
  int saves = 0;

  @override
  Future<bool> hasAcceptedCurrentTerms() async => accepted;

  @override
  Future<void> acceptCurrentTerms() async {
    saves++;
    if (failSave) throw StateError('storage unavailable');
    accepted = true;
  }
}

void main() {
  testWidgets('terms require an active choice and remain available later', (
    tester,
  ) async {
    final store = _MemoryLegalStore();
    await tester.pumpWidget(
      MaterialApp(
        home: LegalGate(
          store: store,
          child: const Scaffold(body: Text('App ready')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App ready'), findsNothing);
    expect(find.byKey(const Key('openTermsButton')), findsOneWidget);
    expect(find.byKey(const Key('openPrivacyButton')), findsOneWidget);
    expect(find.byKey(const Key('acceptTermsButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('legalQrButton')));
    await tester.pumpAndSettle();
    expect(
      find.text('Scan this code with your phone to read the document.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('acceptTermsButton')));
    await tester.pumpAndSettle();
    expect(store.saves, 1);
    expect(find.text('App ready'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: LegalGate(
          store: store,
          child: const Scaffold(body: Text('App ready')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App ready'), findsOneWidget);
  });

  testWidgets('failed local save does not open the app', (tester) async {
    final store = _MemoryLegalStore()..failSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: LegalGate(store: store, child: const Text('App ready')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptTermsButton')));
    await tester.pumpAndSettle();
    expect(find.text('App ready'), findsNothing);
    expect(find.byKey(const Key('legalAcceptanceError')), findsOneWidget);
  });
}
