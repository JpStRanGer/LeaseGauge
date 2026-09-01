import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/main.dart';

void main() {
  testWidgets('shows the lease setup screen', (
      WidgetTester tester,
      ) async {
    await tester.pumpWidget(const LeaseGaugeApp());

    expect(find.text('Plan your lease'), findsOneWidget);
    expect(find.text('Lease details'), findsOneWidget);
  });
}