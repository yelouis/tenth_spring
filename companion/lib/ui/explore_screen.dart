import 'package:flutter/material.dart';
import '../explore/explore_service.dart';
import '../explore/explore_store.dart';
import '../explore/places_pack.dart';
import '../sync/scout_link.dart';
import 'controls_screen.dart';
import 'explored_list_screen.dart';
import 'pairing_screen.dart';

class ExploreScreen extends StatefulWidget {
  final ExploreStore database;
  final PlacesPack? initialPack;
  final PositionSource? positionSource;
  final ScoutLink? scoutLink;

  const ExploreScreen({
    super.key,
    required this.database,
    this.initialPack,
    this.positionSource,
    this.scoutLink,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  PlacesPack? _pack;
  ExploreService? _service;
  late final ScoutLink _scoutLink;

  ExploreResult? _lastResult;
  String? _reportMessage;
  int _pendingCount = 0;
  String _lastReportLabel = 'Never';
  bool _isExploring = false;
  bool _isReporting = false;

  @override
  void initState() {
    super.initState();
    _scoutLink = widget.scoutLink ?? ScoutLink();
    if (widget.initialPack != null) {
      _pack = widget.initialPack;
      _service = ExploreService(
        store: widget.database,
        pack: _pack!,
        positionSource: widget.positionSource,
      );
    } else {
      _loadPack();
    }
    _refreshOutboxStatus();
  }

  Future<void> _loadPack() async {
    try {
      final loaded = await PlacesPack.loadAsset();
      if (!mounted) return;
      setState(() {
        _pack = loaded;
        _service = ExploreService(
          store: widget.database,
          pack: loaded,
          positionSource: widget.positionSource,
        );
      });
    } catch (_) {}
  }

  Future<void> _refreshOutboxStatus() async {
    final pending = await widget.database.getAllOutboxItems();
    final lastMsStr = await widget.database.getMeta('last_report_ms');
    String lastLabel = 'Never';
    if (lastMsStr != null) {
      final ms = int.tryParse(lastMsStr);
      if (ms != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        lastLabel = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
      }
    }
    if (!mounted) return;
    setState(() {
      _pendingCount = pending.length;
      _lastReportLabel = lastLabel;
    });
  }

  Future<void> _handleExploreHere() async {
    if (_isExploring) return;
    var service = _service;
    if (service == null) {
      await _loadPack();
      service = _service;
      if (service == null) return;
    }

    setState(() {
      _isExploring = true;
    });

    final result = await service.exploreHere();
    await _refreshOutboxStatus();
    if (!mounted) return;
    setState(() {
      _isExploring = false;
      _lastResult = result;
    });
  }

  Future<void> _handleReportToPc() async {
    if (_isReporting) return;
    setState(() {
      _isReporting = true;
      _reportMessage = null;
    });

    final packVer = _pack?.packVersion ?? 1;
    final res = await _scoutLink.report(
      db: widget.database,
      schemaVersion: 3,
      packVersion: packVer,
    );
    await _refreshOutboxStatus();
    if (!mounted) return;
    setState(() {
      _isReporting = false;
      _reportMessage = res.userMessage;
    });
  }

  Future<void> _openPairing() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PairingScreen(scoutLink: _scoutLink),
      ),
    );
    await _refreshOutboxStatus();
  }

  Future<void> _openExploredList() async {
    final pack = _pack;
    if (pack == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExploredListScreen(
          store: widget.database,
          pack: pack,
        ),
      ),
    );
    await _refreshOutboxStatus();
  }

  Future<void> _openControls() async {
    final pack = _pack;
    final service = _service;
    if (pack == null || service == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ControlsScreen(
          store: widget.database,
          pack: pack,
          exploreService: service,
          pairingStore: _scoutLink.store,
        ),
      ),
    );
    await _refreshOutboxStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenth Spring Scout Ledger'),
        actions: [
          IconButton(
            key: const Key('nav_explored_button'),
            tooltip: 'Explored places',
            icon: const Icon(Icons.map_outlined),
            onPressed: _openExploredList,
          ),
          IconButton(
            key: const Key('nav_controls_button'),
            tooltip: 'Controls & Set home',
            icon: const Icon(Icons.tune),
            onPressed: _openControls,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                kPermissionRationale,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              SizedBox(
                height: 72.0,
                child: FilledButton.icon(
                  key: const Key('explore_here_button'),
                  onPressed: _isExploring ? null : _handleExploreHere,
                  icon: const Icon(Icons.explore, size: 28.0),
                  label: Text(
                    _isExploring ? 'Checking location...' : 'Explore Here',
                    style: const TextStyle(fontSize: 20.0),
                  ),
                ),
              ),
              const SizedBox(height: 20.0),
              if (_lastResult != null)
                Card(
                  key: const Key('explore_result_card'),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastResult!.message,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (_lastResult!.permissionDenied && _service != null) ...[
                          const SizedBox(height: 12.0),
                          OutlinedButton(
                            key: const Key('result_open_settings_button'),
                            onPressed: () {
                              _service!.positionSource.openAppSettings();
                            },
                            child: const Text('Open Settings'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              Card(
                key: const Key('report_section_card'),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '$_pendingCount discoveries waiting',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'Last report: $_lastReportLabel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_reportMessage != null) ...[
                        const SizedBox(height: 8.0),
                        Text(
                          _reportMessage!,
                          key: const Key('report_status_text'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 12.0),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              key: const Key('report_to_pc_button'),
                              onPressed:
                                  _isReporting ? null : _handleReportToPc,
                              icon: const Icon(Icons.sync),
                              label: const Text('Report to PC'),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          OutlinedButton.icon(
                            key: const Key('pair_pc_button'),
                            onPressed: _openPairing,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Pair'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
