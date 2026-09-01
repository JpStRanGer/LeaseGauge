import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/main.dart';

void main() {
  testWidgets('shows LeaseGauge title and tagline', (
      WidgetTester tester,
      ) async {
    await tester.pumpWidget(const LeaseGaugeApp());

    expect(find.text('LeaseGauge'), findsOneWidget);
    expect(
      find.text('Know your mileage. Keep your lease on track.'),
      findsOneWidget,
    );
  });
}