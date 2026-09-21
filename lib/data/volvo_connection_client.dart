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
    this.vehicleLabel,
  });

  final double kilometers;
  final DateTime vehicleUpdatedAt;
  final String? vehicleLabel;
}

class VolvoVehicle {
  const VolvoVehicle({required this.id, required this.label});

  final String id;
  final String label;
}

class VolvoVehicles {
  const VolvoVehicles({required this.vehicles, this.selectedVehicleId});

  final List<VolvoVehicle> vehicles;
  final String? selectedVehicleId;
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
    this.demoMultipleVehicles = const bool.fromEnvironment(
      'LEASEGAUGE_DEMO_MULTIPLE_VOLVOS',
    ),
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _tokens = tokenStore ?? const SecureDeviceTokenStore(),
       _baseUrl = baseUrl ?? Uri.parse('https://leasegauge.jonaspettersen.no');

  final http.Client _http;
  final bool _ownsHttp;
  final DeviceTokenStore _tokens;
  final Uri _baseUrl;
  final bool demoMultipleVehicles;
  String? _demoSelectedVehicleId;
  bool _demoConnected = true;

  static const _demoVehicles = [
    VolvoVehicle(id: 'demo-ex30', label: 'Volvo EX30 · demo car'),
    VolvoVehicle(id: 'demo-xc40', label: 'Volvo XC40 · demo car'),
  ];

  Uri _endpoint(String path) => _baseUrl.resolve(path);

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<bool> isPaired() async =>
      (demoMultipleVehicles && _demoConnected) ||
      (await _tokens.read()) != null;

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
    if (demoMultipleVehicles) {
      if (!_demoConnected) return null;
      if (_demoSelectedVehicleId == null) {
        throw const VolvoVehicleSelectionRequired();
      }
      final ex30 = _demoSelectedVehicleId == 'demo-ex30';
      return VolvoOdometer(
        kilometers: ex30 ? 16420 : 23175,
        vehicleUpdatedAt: DateTime.now().toUtc(),
        vehicleLabel: ex30 ? _demoVehicles[0].label : _demoVehicles[1].label,
      );
    }
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
    final label = data['vehicle_label'];
    if (label != null && label is! String) {
      throw const FormatException('Invalid vehicle label response.');
    }
    return VolvoOdometer(
      kilometers: kilometers,
      vehicleUpdatedAt: updatedAt,
      vehicleLabel: label as String?,
    );
  }

  Future<VolvoVehicles> readVehicles() async {
    if (demoMultipleVehicles) {
      return VolvoVehicles(
        vehicles: _demoVehicles,
        selectedVehicleId: _demoSelectedVehicleId,
      );
    }
    final token = await _tokens.read();
    if (token == null) return const VolvoVehicles(vehicles: []);
    final response = await _http.get(
      _endpoint('/leasegauge/api/vehicles'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401) {
      await _tokens.clear();
      return const VolvoVehicles(vehicles: []);
    }
    if (response.statusCode != 200) {
      throw StateError('The vehicle list could not be retrieved.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawVehicles = data['vehicles'];
    if (rawVehicles is! List) {
      throw const FormatException('Invalid vehicle list response.');
    }
    final vehicles = <VolvoVehicle>[];
    for (final raw in rawVehicles) {
      if (raw is! Map) throw const FormatException('Invalid vehicle response.');
      final id = raw['id'];
      final label = raw['label'];
      if (id is! String || id.isEmpty || label is! String || label.isEmpty) {
        throw const FormatException('Invalid vehicle response.');
      }
      vehicles.add(VolvoVehicle(id: id, label: label));
    }
    final selected = data['selected_vehicle_id'];
    if (selected != null && selected is! String) {
      throw const FormatException('Invalid selected vehicle response.');
    }
    return VolvoVehicles(
      vehicles: vehicles,
      selectedVehicleId: selected as String?,
    );
  }

  Future<void> selectVehicle(String vehicleId) async {
    if (demoMultipleVehicles) {
      if (!_demoVehicles.any((vehicle) => vehicle.id == vehicleId)) {
        throw StateError('The vehicle could not be selected.');
      }
      _demoSelectedVehicleId = vehicleId;
      return;
    }
    final token = await _tokens.read();
    if (token == null) throw StateError('Volvo is not connected.');
    final response = await _http.post(
      _endpoint('/leasegauge/api/vehicle/select'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'vehicle_id': vehicleId}),
    );
    if (response.statusCode == 401) {
      await _tokens.clear();
      throw StateError('Volvo is not connected.');
    }
    if (response.statusCode != 200) {
      throw StateError('The vehicle could not be selected.');
    }
  }

  Future<void> disconnectThisDevice() => demoMultipleVehicles
      ? _disconnectDemo()
      : _disconnect('/leasegauge/api/disconnect-device');

  Future<void> disconnectEverywhere() => demoMultipleVehicles
      ? _disconnectDemo()
      : _disconnect('/leasegauge/api/disconnect');

  Future<void> _disconnectDemo() async {
    _demoConnected = false;
    _demoSelectedVehicleId = null;
  }

  /// Available only in a build made with LEASEGAUGE_DEMO_MULTIPLE_VOLVOS.
  /// It lets the visual test flow start over without calling Volvo.
  Future<void> reconnectDemo() async {
    if (!demoMultipleVehicles) {
      throw StateError('Demo mode is not enabled.');
    }
    _demoConnected = true;
    _demoSelectedVehicleId = null;
  }

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
