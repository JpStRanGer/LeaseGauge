import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/address_search_client.dart';
import 'package:leasegauge/screens/commute_map_screen.dart';

class _FakeAddressSearchClient extends AddressSearchClient {
  String? lastQuery;

  @override
  Future<List<AddressSearchResult>> search(String input) async {
    lastQuery = input;
    return const [
      AddressSearchResult(
        label: 'Karl Johans gate 1, 0154 OSLO',
        latitude: 59.9111,
        longitude: 10.7494,
      ),
    ];
  }
}

void main() {
  testWidgets('address search lets the user select a home address', (
    tester,
  ) async {
    final client = _FakeAddressSearchClient();
    await tester.pumpWidget(
      MaterialApp(home: CommuteMapScreen(addressSearchClient: client)),
    );

    await tester.enterText(
      find.byKey(const Key('homeAddressField')),
      'Karl Johans gate 1 Oslo',
    );
    await tester.tap(find.byKey(const Key('searchHomeAddress')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(client.lastQuery, 'Karl Johans gate 1 Oslo');
    expect(find.text('Choose home address'), findsOneWidget);

    await tester.tap(find.text('Karl Johans gate 1, 0154 OSLO'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.widgetWithText(TextField, 'Karl Johans gate 1, 0154 OSLO'),
      findsOneWidget,
    );
  });
}
