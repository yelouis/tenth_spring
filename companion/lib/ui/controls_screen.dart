import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../explore/explore_service.dart';
import '../explore/explore_store.dart';
import '../explore/places_pack.dart';
import '../sync/pairing.dart';

class ControlsScreen extends StatefulWidget {
  final ExploreStore store;
  final PlacesPack pack;
  final ExploreService exploreService;
  final PairingStore? pairingStore;

  const ControlsScreen({
    super.key,
    required this.store,
    required this.pack,
    required this.exploreService,
    this.pairingStore,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  String? _starterPlaceId;
  String _permissionLabel = 'Checking...';
  String? _statusMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final starter = await widget.store.getStarterPlaceId();
    String permText = 'Not requested';
    try {
      final perm = await widget.exploreService.positionSource.checkPermission();
      switch (perm) {
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          permText = 'While Using the App';
        case LocationPermission.denied:
          permText = 'Not granted (asked on tap)';
        case LocationPermission.deniedForever:
          permText = 'Denied — allow in Settings';
        case LocationPermission.unableToDetermine:
          permText = 'Unknown';
      }
    } catch (_) {
      permText = 'Unavailable';
    }
    if (!mounted) return;
    setState(() {
      _starterPlaceId = starter;
      _permissionLabel = permText;
    });
  }

  Future<void> _handleSetHome() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    final res = await widget.exploreService.setHome();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = res.message;
    });
  }

  Future<void> _handleEraseEverything() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    await widget.store.eraseAll();
    final pStore = widget.pairingStore ?? PairingStore();
    try {
      await pStore.clear();
    } catch (_) {}
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = 'All explored places, pending reports, and pairing erased.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final starterName = _starterPlaceId != null
        ? (widget.pack.place(_starterPlaceId!)?.name ?? _starterPlaceId!)
        : 'Not set';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controls & Privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (_statusMessage != null)
            Card(
              key: const Key('controls_status_card'),
              margin: const EdgeInsets.only(bottom: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_statusMessage!),
              ),
            ),
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Starting City',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  Text('Current starting city: $starterName'),
                  const SizedBox(height: 8.0),
                  const Text(kSetHomeExplanation),
                  const SizedBox(height: 12.0),
                  FilledButton.icon(
                    key: const Key('set_home_button'),
                    onPressed: _busy ? null : _handleSetHome,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Set home'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location Permission',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  Text('Status: $_permissionLabel'),
                  const SizedBox(height: 8.0),
                  const Text(kPermissionRationale),
                  const SizedBox(height: 12.0),
                  OutlinedButton(
                    key: const Key('open_settings_button'),
                    onPressed: () {
                      widget.exploreService.positionSource.openAppSettings();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Erase Everything',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Erases your phone outbox, explored list, starting city, and PC pairing in one tap.',
                  ),
                  const SizedBox(height: 12.0),
                  OutlinedButton.icon(
                    key: const Key('erase_all_button'),
                    onPressed: _busy ? null : _handleEraseEverything,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Erase everything'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Map Attribution',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  Text(widget.pack.attribution),
                  const SizedBox(height: 4.0),
                  Text(
                    'Places pack v${widget.pack.packVersion} (snapshot ${widget.pack.snapshot})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
