import 'dart:async';
import 'package:flutter/material.dart';
import '../capture/detector.dart';
import '../capture/fuzz.dart';
import '../capture/location_source.dart';
import '../capture/os_location_source.dart';
import '../outbox/database.dart';
import '../sync/scout_link.dart';
import 'pairing_screen.dart';

class ScoutLedgerScreen extends StatefulWidget {
  final AppDatabase database;
  final LocationSource? locationSource;
  final VisitCorridorDetector? detector;
  final ScoutLink? scoutLink;

  const ScoutLedgerScreen({
    super.key,
    required this.database,
    this.locationSource,
    this.detector,
    this.scoutLink,
  });

  @override
  State<ScoutLedgerScreen> createState() => _ScoutLedgerScreenState();
}

class _FixRecord {
  final double lat;
  final double lon;
  final int tsUtcMs;
  const _FixRecord({required this.lat, required this.lon, required this.tsUtcMs});
}

class _ScoutLedgerScreenState extends State<ScoutLedgerScreen>
    with WidgetsBindingObserver {
  bool _isScoutingPaused = false;
  bool _isBackgroundScoutingEnabled = true;
  bool _isReporting = false;
  DateTime? _lastReportTime;
  _FixRecord? _lastFix;
  List<VisitOutboxItem> _visits = [];
  late VisitCorridorDetector _detector;
  LocationSource? _locationSource;

  StreamSubscription? _fixSub;
  StreamSubscription? _visitSub;
  StreamSubscription? _corridorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLedger();
    _initCapturePipeline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBackgroundPermission();
    }
  }

  Future<void> _checkBackgroundPermission() async {
    if (_locationSource is OsLocationSource) {
      final granted = await (_locationSource as OsLocationSource)
          .isBackgroundPermissionGranted();
      if (mounted) {
        setState(() {
          _isBackgroundScoutingEnabled = granted;
        });
      }
    }
  }

  void _initCapturePipeline() {
    _detector = widget.detector ?? VisitCorridorDetector();
    _locationSource = widget.locationSource;

    if (_locationSource != null) {
      _checkBackgroundPermission();

      _visitSub = _detector.visitStream.listen((visit) async {
        await widget.database.insertVisit(
          kind: 'visit',
          lat: visit.fuzzedPoint.lat,
          lon: visit.fuzzedPoint.lon,
          startedAt: visit.startedAtTsMs,
          dwellSeconds: visit.dwellSeconds,
        );
        _refreshLedger();
      });

      _corridorSub = _detector.corridorStream.listen((corridor) async {
        await widget.database.insertVisit(
          kind: 'corridor',
          lat: corridor.fuzzedPoint.lat,
          lon: corridor.fuzzedPoint.lon,
          startedAt: corridor.timestampTsMs,
        );
        _refreshLedger();
      });

      _fixSub = _locationSource!.fixes().listen((fix) {
        final fuzzed = fuzzPoint(fix.lat, fix.lon);
        _lastFix = _FixRecord(
          lat: fuzzed.lat,
          lon: fuzzed.lon,
          tsUtcMs: fix.tsUtcMs,
        );
        if (!_isScoutingPaused) {
          _detector.processFix(fix);
        }
      });

      _locationSource!.start().catchError((e) {
        debugPrint('LocationSource start error: $e');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fixSub?.cancel();
    _visitSub?.cancel();
    _corridorSub?.cancel();
    if (widget.detector == null) {
      _detector.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshLedger() async {
    final visits = await widget.database.getAllVisits();
    if (mounted) {
      setState(() {
        _visits = visits;
      });
    }
  }

  Future<void> _triggerManualScout() async {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finding your location…')),
      );
    }
    final fix = await _locationSource?.currentFix();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't find your location — try again in a moment."),
        ),
      );
      return;
    }
    final p = fuzzPoint(fix.lat, fix.lon);
    await widget.database.insertVisit(
      kind: 'visit',
      lat: p.lat,
      lon: p.lon,
      startedAt: fix.tsUtcMs,
      dwellSeconds: 120,
    );
    _lastFix = _FixRecord(
      lat: p.lat,
      lon: p.lon,
      tsUtcMs: fix.tsUtcMs,
    );
    await _refreshLedger();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scouted a location near you')),
      );
    }
  }

  Future<void> _enableBackgroundScouting() async {
    if (_locationSource is OsLocationSource) {
      final granted = await (_locationSource as OsLocationSource)
          .requestBackgroundPermission();
      if (mounted) {
        setState(() {
          _isBackgroundScoutingEnabled = granted;
        });
      }
    }
  }

  void _toggleScoutingPause() {
    setState(() {
      _isScoutingPaused = !_isScoutingPaused;
    });
    if (_isScoutingPaused) {
      _locationSource?.stop();
    } else {
      _locationSource?.start();
    }
  }

  Future<void> _openPairing() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PairingScreen(scoutLink: widget.scoutLink),
      ),
    );
  }

  Future<void> _reportToPc() async {
    setState(() => _isReporting = true);
    final link = widget.scoutLink ?? ScoutLink();
    final bodyFix = _lastFix == null
        ? null
        : {
            "lat": _lastFix!.lat,
            "lon": _lastFix!.lon,
            "tsUtcMs": _lastFix!.tsUtcMs,
          };
    final result = await link.report(db: widget.database, bodyFix: bodyFix);
    if (!mounted) return;
    setState(() => _isReporting = false);

    switch (result) {
      case ReportOk(:final sent):
        setState(() {
          _lastReportTime = DateTime.now();
        });
        await _refreshLedger();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delivered $sent scout reports to PC.')),
        );
      case ReportUnreachable():
        _showErrorDialog("Can't reach your PC — open the scout report on your PC and re-scan its code.");
      case ReportUnpaired():
        _showErrorDialog("This phone isn't paired with that PC anymore — scan its code to pair again.");
      case ReportSchemaMismatch():
        _showErrorDialog("Schema mismatch with PC — please update your app or PC game.");
      case ReportPcStorageError():
        _showErrorDialog("Your PC couldn't file this scout report — nothing was lost. Try again in a moment.");
      case ReportProtocolError(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scout report error: ${message ?? 'protocol failure'}')),
        );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scout Link'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _lastReportText {
    if (_lastReportTime == null) return 'Never';
    final diff = DateTime.now().difference(_lastReportTime!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final visitCount = _visits.where((v) => v.kind == 'visit').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenth Spring Scout Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Pair with your PC',
            onPressed: _openPairing,
          ),
          IconButton(
            icon: Icon(_isScoutingPaused ? Icons.play_arrow : Icons.pause),
            tooltip: _isScoutingPaused ? 'Resume Scouting' : 'Pause Scouting',
            onPressed: _toggleScoutingPause,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLedger,
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).colorScheme.primaryContainer,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$visitCount places scouted today',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sync at your PC to add them to your map.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Last report: $_lastReportText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isReporting ? null : _reportToPc,
                      icon: _isReporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Report to PC'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openPairing,
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('Pair with your PC'),
                    ),
                  ],
                ),
                if (_isScoutingPaused) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PAUSED',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                if (!_isBackgroundScoutingEnabled && !_isScoutingPaused) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _enableBackgroundScouting,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Background scouting off — tap to enable',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _visits.isEmpty
                ? const Center(
                    child: Text('No scouted places recorded yet today.'),
                  )
                : ListView.separated(
                    itemCount: _visits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _visits[index];
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                          item.startedAt);
                      final timeStr =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                      return ListTile(
                        leading: Icon(
                          item.kind == 'visit'
                              ? Icons.place
                              : Icons.directions_walk,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(item.kind == 'visit'
                            ? 'A place near you'
                            : 'Travel corridor trace'),
                        subtitle: Text(
                          '$timeStr • ${item.kind == 'visit' ? '${item.dwellSeconds ?? 0}s dwell' : 'corridor point'} • Lat: ${item.lat}, Lon: ${item.lon}',
                        ),
                        trailing: item.synced == 1
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.cloud_upload_outlined),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScoutingPaused ? null : _triggerManualScout,
        icon: const Icon(Icons.my_location),
        label: const Text('Scout Here'),
      ),
    );
  }
}
