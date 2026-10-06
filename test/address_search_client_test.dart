import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leasegauge/data/address_search_client.dart';

void main() {
  test(
    'search sends one bounded query and parses Kartverket coordinates',
    () async {
      http.Request? captured;
      final client = AddressSearchClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'adresser': [
                {
                  'adressetekst': 'Karl Johans gate 1',
                  'postnummer': '0154',
                  'poststed': 'OSLO',
                  'representasjonspunkt': {'lat': 59.911377, 'lon': 10.749404},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await client.search('  Karl Johans gate 1 Oslo  ');

      expect(captured?.method, 'GET');
      expect(captured?.url.host, 'api.kartverket.no');
      expect(captured?.url.path, '/adresser/v1/sok');
      expect(captured?.url.queryParameters['sok'], 'Karl Johans gate 1 Oslo');
      expect(captured?.url.queryParameters['treffPerSide'], '5');
      expect(results, hasLength(1));
      expect(results.single.label, 'Karl Johans gate 1, 0154 OSLO');
      expect(results.single.latitude, closeTo(59.911377, 0.000001));
      expect(results.single.longitude, closeTo(10.749404, 0.000001));
    },
  );

  test('search rejects short input before making a request', () async {
    var requested = false;
    final client = AddressSearchClient(
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );

    expect(() => client.search('ab'), throwsFormatException);
    expect(requested, isFalse);
  });

  test('search drops malformed and out-of-range results', () async {
    final client = AddressSearchClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'adresser': [
              {
                'adressetekst': 'Invalid address',
                'representasjonspunkt': {'lat': 500, 'lon': 10},
              },
              {'adressetekst': 'Missing point'},
            ],
          }),
          200,
        ),
      ),
    );

    expect(await client.search('Invalid address'), isEmpty);
  });
}
