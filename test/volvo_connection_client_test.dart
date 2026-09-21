import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leasegauge/data/volvo_connection_client.dart';

class MemoryTokenStore implements DeviceTokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

void main() {
  test(
    'pairing keeps Volvo token off the phone and reads only distance',
    () async {
      final tokens = MemoryTokenStore();
      var pollCount = 0;
      final requests = <http.Request>[];
      final client = VolvoConnectionClient(
        baseUrl: Uri.parse('https://leasegauge.jonaspettersen.no'),
        tokenStore: tokens,
        httpClient: MockClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/leasegauge/api/pair/start':
              return http.Response(
                jsonEncode({
                  'authorization_url': 'https://volvoid.eu.volvocars.com/as/authorization.oauth2?state=abc',
                  'browser_start_path':
                      '/leasegauge/browser/start?ticket=opaque',
                  'pair_id': 'pair-1',
                  'pair_secret': 'secret-1',
                }),
                200,
              );
            case '/leasegauge/api/pair/complete':
              pollCount++;
              return http.Response(
                pollCount == 1
                    ? jsonEncode({'status': 'pending'})
                    : jsonEncode({
                        'status': 'connected',
                        'device_token': 'device-only-token',
                      }),
                pollCount == 1 ? 202 : 200,
              );
            case '/leasegauge/api/odometer':
              expect(
                request.headers['Authorization'],
                'Bearer device-only-token',
              );
              return http.Response(
                jsonEncode({
                  'kilometers': 7857,
                  'vehicle_updated_at': '2026-09-19T14:41:11Z',
                }),
                200,
              );
            default:
              throw StateError('Unexpected ${request.url.path}');
          }
        }),
      );

      final pairing = await client.beginPairing();
      expect(pairing.authorizationUrl.host, 'volvoid.eu.volvocars.com');
      expect(
        pairing.browserStartUrl.toString(),
        'https://leasegauge.jonaspettersen.no/leasegauge/browser/start?ticket=opaque',
      );
      expect(tokens.value, isNull);
      expect(await client.completePairing(pairing), isFalse);
      expect(await client.completePairing(pairing), isTrue);
      expect(tokens.value, 'device-only-token');
      final reading = await client.readOdometer();
      expect(reading?.kilometers, 7857);
      expect(reading?.vehicleUpdatedAt.isUtc, isTrue);
      expect(requests.last.headers.containsKey('vcc-api-key'), isFalse);
      client.close();
    },
  );

  test('invalid or expired device token falls back to manual entry', () async {
    final tokens = MemoryTokenStore()..value = 'expired-token';
    final client = VolvoConnectionClient(
      tokenStore: tokens,
      httpClient: MockClient((request) async => http.Response('', 401)),
    );
    expect(await client.readOdometer(), isNull);
    expect(tokens.value, isNull);
    client.close();
  });

  test(
    'multiple vehicles keep the connection for a future selection',
    () async {
      final tokens = MemoryTokenStore()..value = 'device-token';
      final client = VolvoConnectionClient(
        tokenStore: tokens,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'error': 'vehicle_selection_required'}),
            409,
          ),
        ),
      );
      expect(
        client.readOdometer(),
        throwsA(isA<VolvoVehicleSelectionRequired>()),
      );
      expect(tokens.value, 'device-token');
      client.close();
    },
  );

  test('unexpected authorization host is rejected', () async {
    final client = VolvoConnectionClient(
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'authorization_url': 'https://malicious.example/steal',
            'pair_id': 'pair-1',
            'pair_secret': 'secret-1',
          }),
          200,
        ),
      ),
    );
    expect(client.beginPairing(), throwsFormatException);
    client.close();
  });

  test(
    'lists and selects a Volvo vehicle using the device credential',
    () async {
      final tokens = MemoryTokenStore()..value = 'device-token';
      final paths = <String>[];
      final client = VolvoConnectionClient(
        tokenStore: tokens,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.headers['Authorization'], 'Bearer device-token');
          if (request.url.path == '/leasegauge/api/vehicles') {
            return http.Response(
              jsonEncode({
                'vehicles': [
                  {'id': 'vin-1', 'label': 'Volvo ending 111111'},
                  {'id': 'vin-2', 'label': 'Volvo ending 222222'},
                ],
                'selected_vehicle_id': null,
              }),
              200,
            );
          }
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'vehicle_id': 'vin-2'});
          return http.Response(
            jsonEncode({'selected_vehicle_id': 'vin-2'}),
            200,
          );
        }),
      );

      final available = await client.readVehicles();
      expect(available.vehicles.map((vehicle) => vehicle.label), [
        'Volvo ending 111111',
        'Volvo ending 222222',
      ]);
      expect(available.selectedVehicleId, isNull);
      await client.selectVehicle('vin-2');
      expect(paths, [
        '/leasegauge/api/vehicles',
        '/leasegauge/api/vehicle/select',
      ]);
      client.close();
    },
  );

  test(
    'debug demo can exercise the multiple-car flow without Volvo access',
    () async {
      final client = VolvoConnectionClient(
        tokenStore: MemoryTokenStore(),
        demoMultipleVehicles: true,
      );

      expect(await client.isPaired(), isTrue);
      expect(
        client.readOdometer(),
        throwsA(isA<VolvoVehicleSelectionRequired>()),
      );
      final vehicles = await client.readVehicles();
      expect(vehicles.vehicles, hasLength(2));
      await client.selectVehicle('demo-xc40');
      expect(
        (await client.readOdometer())?.vehicleLabel,
        'Volvo XC40 · demo car',
      );
      await client.disconnectThisDevice();
      expect(await client.isPaired(), isFalse);
      client.close();
    },
  );

  test('unconfigured server reports a specific unavailable error', () async {
    final client = VolvoConnectionClient(
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((request) async => http.Response('', 503)),
    );
    expect(client.beginPairing(), throwsA(isA<VolvoServiceUnavailable>()));
    client.close();
  });

  test('disconnecting this device uses only the device endpoint', () async {
    final tokens = MemoryTokenStore()..value = 'phone-token';
    final paths = <String>[];
    final client = VolvoConnectionClient(
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer phone-token');
        return http.Response(jsonEncode({'connected': false}), 200);
      }),
    );

    await client.disconnectThisDevice();
    expect(paths, ['/leasegauge/api/disconnect-device']);
    expect(tokens.value, isNull);
    client.close();
  });

  test('disconnecting everywhere uses the account-wide endpoint', () async {
    final tokens = MemoryTokenStore()..value = 'phone-token';
    final paths = <String>[];
    final client = VolvoConnectionClient(
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer phone-token');
        return http.Response(jsonEncode({'connected': false}), 200);
      }),
    );

    await client.disconnectEverywhere();
    expect(paths, ['/leasegauge/api/disconnect']);
    expect(tokens.value, isNull);
    client.close();
  });
}
