import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// LeaseGauge device credentials only. Volvo's OAuth tokens stay on the server.
abstract interface class DeviceTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureDeviceTokenStore implements DeviceTokenStore {
  const SecureDeviceTokenStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'leasegauge.deviceToken';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class VolvoPairing {
  const VolvoPairing({
    required this.authorizationUrl,
    required this.pairId,
    required this.pairSecret,
    this.browserStartUrl,
  });

  final Uri authorizationUrl;

  /// Marks a same-device browser visit so the callback can return to the app.
  final Uri? browserStartUrl;
  final String pairId;
  final String pairSecret;
}

class VolvoOdometer {
  const VolvoOdometer({
    required this.kilometers,
    required this.vehicleUpdatedAt,
  });

  final double kilometers;
  final DateTime vehicleUpdatedAt;
}

class VolvoVehicleSelectionRequired implements Exception {
  const VolvoVehicleSelectionRequired();
}

class VolvoServiceUnavailable implements Exception {
  const VolvoServiceUnavailable();
}

class VolvoConnectionClient {
  VolvoConnectionClient({
    http.Client? httpClient,
    DeviceTokenStore? tokenStore,
    Uri? baseUrl,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _tokens = tokenStore ?? const SecureDeviceTokenStore(),
       _baseUrl = baseUrl ?? Uri.parse('https://leasegauge.jonaspettersen.no');

  final http.Client _http;
  final bool _ownsHttp;
  final DeviceTokenStore _tokens;
  final Uri _baseUrl;

  Uri _endpoint(String path) => _baseUrl.resolve(path);

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<bool> isPaired() async => (await _tokens.read()) != null;

  Future<VolvoPairing> beginPairing() async {
    final response = await _http.post(_endpoint('/leasegauge/api/pair/start'));
    if (response.statusCode == 503) {
      throw const VolvoServiceUnavailable();
    }
    if (response.statusCode != 200) {
      throw StateError('Could not start Volvo connection.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url = Uri.tryParse(data['authorization_url'] as String? ?? '');
    final browserPath = data['browser_start_path'] as String?;
    final browserUrl = browserPath == null ? null : _endpoint(browserPath);
    final pairId = data['pair_id'] as String?;
    final pairSecret = data['pair_secret'] as String?;
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'volvoid.eu.volvocars.com' ||
        pairId == null ||
        pairSecret == null ||
        pairId.isEmpty ||
        pairSecret.isEmpty) {
      throw const FormatException('Invalid Volvo pairing response.');
    }
    if (browserUrl != null &&
        (browserPath == null ||
            !browserPath.startsWith('/leasegauge/browser/start?') ||
            browserUrl.scheme != _baseUrl.scheme ||
            browserUrl.host != _baseUrl.host ||
            browserUrl.port != _baseUrl.port)) {
      throw const FormatException('Invalid browser start URL.');
    }
    return VolvoPairing(
      authorizationUrl: url,
      browserStartUrl: browserUrl,
      pairId: pairId,
      pairSecret: pairSecret,
    );
  }

  /// Returns false while the owner is still completing the Volvo sign-in.
  Future<bool> completePairing(VolvoPairing pairing) async {
    final response = await _http.post(
      _endpoint('/leasegauge/api/pair/complete'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pair_id': pairing.pairId,
        'pair_secret': pairing.pairSecret,
      }),
    );
    if (response.statusCode == 202) return false;
    if (response.statusCode != 200) {
      throw StateError('Volvo connection could not be completed.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['device_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Missing device credential.');
    }
    await _tokens.write(token);
    return true;
  }

  Future<VolvoOdometer?> readOdometer() async {
    final token = await _tokens.read();
    if (token == null) return null;
    final response = await _http.get(
      _endpoint('/leasegauge/api/odometer'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 409) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['error'] == 'vehicle_selection_required') {
          throw const VolvoVehicleSelectionRequired();
        }
      } on FormatException {
        // Older server errors may not have a JSON body.
      }
    }
    if (response.statusCode == 401 || response.statusCode == 409) {
      await _tokens.clear();
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError('The latest odometer could not be retrieved.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final kilometers = (data['kilometers'] as num?)?.toDouble();
    final updatedAt = DateTime.tryParse(
      data['vehicle_updated_at'] as String? ?? '',
    );
    if (kilometers == null ||
        !kilometers.isFinite ||
        kilometers < 0 ||
        updatedAt == null) {
      throw const FormatException('Invalid odometer response.');
    }
    return VolvoOdometer(kilometers: kilometers, vehicleUpdatedAt: updatedAt);
  }

  Future<void> disconnectThisDevice() =>
      _disconnect('/leasegauge/api/disconnect-device');

  Future<void> disconnectEverywhere() =>
      _disconnect('/leasegauge/api/disconnect');

  Future<void> _disconnect(String path) async {
    final token = await _tokens.read();
    if (token == null) return;
    final response = await _http.post(
      _endpoint(path),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200 && response.statusCode != 401) {
      throw StateError('Could not disconnect Volvo.');
    }
    await _tokens.clear();
  }
}
