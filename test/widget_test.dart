import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/lease_form_storage.dart';
import 'package:leasegauge/main.dart';

class _MemoryLeaseFormStore implements LeaseFormStore {
  LeaseFormValues? values;

  @override
  Future<LeaseFormValues?> load() async => values;

  @override
  Future<void> save(LeaseFormValues values) async {
    this.values = values;
  }
}

void main() {
  testWidgets('shows the lease setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(LeaseGaugeApp(storage: _MemoryLeaseFormStore()));

    expect(find.text('Plan your lease'), findsOneWidget);
    expect(find.text('Lease details'), findsOneWidget);
  });
}
