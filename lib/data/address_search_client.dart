import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressSearchResult {
  const AddressSearchResult({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class AddressSearchClient {
  AddressSearchClient({http.Client? httpClient, Uri? baseUrl})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null,
      _baseUrl = baseUrl ?? Uri.parse('https://api.kartverket.no');

  static const _maximumQueryLength = 160;
  static const _maximumResponseBytes = 512 * 1024;

  final http.Client _http;
  final bool _ownsHttp;
  final Uri _baseUrl;

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<List<AddressSearchResult>> search(String input) async {
    final query = input.trim();
    if (query.length < 3 || query.length > _maximumQueryLength) {
      throw const FormatException('Enter a more specific address.');
    }

    final uri = _baseUrl.replace(
      path: '/adresser/v1/sok',
      queryParameters: {'sok': query, 'treffPerSide': '5', 'side': '0'},
    );
    final response = await _http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > _maximumResponseBytes) {
      throw StateError('Address search is temporarily unavailable.');
    }

    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map<String, dynamic> || payload['adresser'] is! List) {
      throw const FormatException('Invalid address search response.');
    }

    final results = <AddressSearchResult>[];
    for (final item in (payload['adresser'] as List).take(5)) {
      if (item is! Map<String, dynamic>) continue;
      final point = item['representasjonspunkt'];
      if (point is! Map<String, dynamic>) continue;
      final latitude = (point['lat'] as num?)?.toDouble();
      final longitude = (point['lon'] as num?)?.toDouble();
      final address = item['adressetekst'] as String?;
      final postalCode = item['postnummer'] as String?;
      final postalPlace = item['poststed'] as String?;
      if (latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          address == null ||
          address.trim().isEmpty) {
        continue;
      }
      final locality = [
        if (postalCode != null && postalCode.isNotEmpty) postalCode,
        if (postalPlace != null && postalPlace.isNotEmpty) postalPlace,
      ].join(' ');
      results.add(
        AddressSearchResult(
          label: locality.isEmpty ? address : '$address, $locality',
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return results;
  }
}
