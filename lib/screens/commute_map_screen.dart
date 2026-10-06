import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:leasegauge/data/address_search_client.dart';

/// A map-based distance picker for local testing. The public routing endpoint
/// must be replaced with a production service before commercial distribution.
class CommuteMapScreen extends StatefulWidget {
  const CommuteMapScreen({super.key, this.addressSearchClient});

  final AddressSearchClient? addressSearchClient;

  @override
  State<CommuteMapScreen> createState() => _CommuteMapScreenState();
}

class _CommuteMapScreenState extends State<CommuteMapScreen> {
  late final AddressSearchClient _addressSearchClient;
  late final bool _ownsAddressSearchClient;
  final MapController _mapController = MapController();
  final TextEditingController _homeAddressController = TextEditingController();
  final TextEditingController _workAddressController = TextEditingController();
  LatLng? _home;
  LatLng? _work;
  final List<LatLng> _via = [];
  List<LatLng> _route = const [];
  double? _oneWayKm;
  bool _loading = false;
  bool _searchingAddress = false;
  Timer? _routeTimer;
  int _routeRevision = 0;

  @override
  void initState() {
    super.initState();
    _ownsAddressSearchClient = widget.addressSearchClient == null;
    _addressSearchClient = widget.addressSearchClient ?? AddressSearchClient();
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    _homeAddressController.dispose();
    _workAddressController.dispose();
    if (_ownsAddressSearchClient) _addressSearchClient.close();
    super.dispose();
  }

  void _selectPoint(LatLng point) {
    setState(() {
      if (_home == null) {
        _home = point;
        _homeAddressController.text = 'Selected on map';
      } else if (_work == null) {
        _work = point;
        _workAddressController.text = 'Selected on map';
      } else if (_via.length < 5) {
        _via.add(point);
      }
      _oneWayKm = null;
      _route = const [];
    });
    if (_home != null && _work != null) _scheduleRoute();
  }

  void _removeLastVia() {
    if (_via.isEmpty) return;
    setState(() {
      _via.removeLast();
      _oneWayKm = null;
      _route = const [];
    });
    _scheduleRoute();
  }

  void _startOver() {
    _routeTimer?.cancel();
    _routeRevision++;
    setState(() {
      _home = null;
      _work = null;
      _via.clear();
      _route = const [];
      _oneWayKm = null;
      _loading = false;
      _homeAddressController.clear();
      _workAddressController.clear();
    });
  }

  void _scheduleRoute() {
    _routeTimer?.cancel();
    final revision = ++_routeRevision;
    setState(() => _loading = true);
    // One request per second at most on the public prototype server.
    _routeTimer = Timer(
      const Duration(milliseconds: 1100),
      () => _loadRoute(revision),
    );
  }

  Future<void> _searchAddress({required bool home}) async {
    if (_searchingAddress) return;
    final controller = home ? _homeAddressController : _workAddressController;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _searchingAddress = true);
    try {
      final results = await _addressSearchClient.search(controller.text);
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No Norwegian address matched that search. Try including the house number and city.',
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<AddressSearchResult>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                home ? 'Choose home address' : 'Choose workplace address',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final result in results)
                ListTile(
                  leading: Icon(
                    home ? Icons.home_outlined : Icons.work_outline_rounded,
                  ),
                  title: Text(result.label),
                  onTap: () => Navigator.of(context).pop(result),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      final point = LatLng(selected.latitude, selected.longitude);
      setState(() {
        if (home) {
          _home = point;
          _homeAddressController.text = selected.label;
        } else {
          _work = point;
          _workAddressController.text = selected.label;
        }
        _oneWayKm = null;
        _route = const [];
      });
      _mapController.move(point, 15);
      if (_home != null && _work != null) _scheduleRoute();
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not search for that address. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  Future<void> _loadRoute(int revision) async {
    final home = _home!;
    final work = _work!;
    final via = List<LatLng>.of(_via);
    final coordinates = [
      home,
      ...via,
      work,
    ].map((point) => '${point.longitude},${point.latitude}').join(';');
    final uri = Uri.https(
      'routing.openstreetmap.de',
      '/routed-car/route/v1/driving/$coordinates',
      {'overview': 'full', 'geometries': 'geojson'},
    );
    try {
      final response = await http
          .get(
            uri,
            // Browsers forbid setting User-Agent and send their own Referer.
            headers: kIsWeb
                ? null
                : {
                    'User-Agent':
                        'LeaseGauge/1.0 (local route picker prototype)',
                  },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw const FormatException();
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = payload['routes'] as List<dynamic>;
      if (routes.isEmpty) throw const FormatException();
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final routeCoordinates = geometry['coordinates'] as List<dynamic>;
      final points = routeCoordinates.map((item) {
        final pair = item as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      if (!mounted || revision != _routeRevision) return;
      setState(() {
        _route = points;
        _oneWayKm = (route['distance'] as num).toDouble() / 1000;
      });
    } on Exception {
      if (!mounted || revision != _routeRevision) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not calculate a driving route. Try other points or enter the distance manually.',
          ),
        ),
      );
    } finally {
      if (mounted && revision == _routeRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _addressSearchField({required bool home}) {
    return TextField(
      key: Key(home ? 'homeAddressField' : 'workAddressField'),
      controller: home ? _homeAddressController : _workAddressController,
      textInputAction: TextInputAction.search,
      autofillHints: home ? const [AutofillHints.fullStreetAddress] : null,
      maxLength: 160,
      decoration: InputDecoration(
        labelText: home ? 'Home address' : 'Workplace address',
        hintText: home
            ? 'Example: Storgata 1, Oslo'
            : 'Enter workplace address',
        counterText: '',
        prefixIcon: Icon(home ? Icons.home_outlined : Icons.work_outline),
        suffixIcon: IconButton(
          key: Key(home ? 'searchHomeAddress' : 'searchWorkAddress'),
          tooltip: home ? 'Search home address' : 'Search workplace address',
          onPressed: _searchingAddress
              ? null
              : () => _searchAddress(home: home),
          icon: const Icon(Icons.search_rounded),
        ),
      ),
      onSubmitted: _searchingAddress ? null : (_) => _searchAddress(home: home),
    );
  }

  @override
  Widget build(BuildContext context) {
    final distance = _oneWayKm;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your commute')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _home == null
                      ? 'Move the map and tap your home location.'
                      : _work == null
                      ? 'Now tap your workplace.'
                      : 'Tap a road to add a via point and adjust the route (up to 5).',
                ),
                const SizedBox(height: 12),
                _addressSearchField(home: true),
                const SizedBox(height: 10),
                _addressSearchField(home: false),
                const SizedBox(height: 6),
                Text(
                  'Norwegian address search is sent to Kartverket only when you press Search. The address is not saved by LeaseGauge. You can still select points directly on the map.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_searchingAddress) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (_work != null)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: const Key('removeViaButton'),
                        onPressed: _via.isEmpty ? null : _removeLastVia,
                        icon: const Icon(Icons.undo_rounded),
                        label: Text('Remove last via point (${_via.length})'),
                      ),
                      TextButton.icon(
                        key: const Key('resetRouteButton'),
                        onPressed: _startOver,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Start over'),
                      ),
                    ],
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (distance != null)
                  Text(
                    'Driving route: ${distance.toStringAsFixed(1)} km one way · ${(distance * 2).toStringAsFixed(1)} km round trip',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(59.9139, 10.7522),
                initialZoom: 10,
                onTap: (_, point) => _selectPoint(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.strangestudio.leasegauge',
                ),
                if (_route.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route,
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_home != null)
                      Marker(
                        point: _home!,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.home_rounded,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    if (_work != null)
                      Marker(
                        point: _work!,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.work_rounded,
                          color: Colors.deepOrange,
                          size: 38,
                        ),
                      ),
                    for (var index = 0; index < _via.length; index++)
                      Marker(
                        point: _via[index],
                        width: 38,
                        height: 38,
                        child: CircleAvatar(child: Text('${index + 1}')),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                    TextSourceAttribution('Routing: OSRM / FOSSGIS'),
                    TextSourceAttribution('Address search: Kartverket'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('useMapDistanceButton'),
                onPressed: distance == null
                    ? null
                    : () => Navigator.of(context).pop(distance * 2),
                child: const Text('Use round-trip distance'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
