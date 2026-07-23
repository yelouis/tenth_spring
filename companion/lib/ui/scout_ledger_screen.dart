import 'dart:async';
import 'package:flutter/material.dart';
import '../capture/detector.dart';
import '../capture/location_source.dart';
import '../outbox/database.dart';

class ScoutLedgerScreen extends StatefulWidget {
  final AppDatabase database;
  final LocationSource? locationSource;
  final VisitCorridorDetector? detector;

  const ScoutLedgerScreen({
    super.key,
    required this.database,
    this.locationSource,
    this.detector,
  });

  @override
  State<ScoutLedgerScreen> createState() => _ScoutLedgerScreenState();
}

class _ScoutLedgerScreenState extends State<ScoutLedgerScreen> {
  bool _isScoutingPaused = false;
  List<VisitOutboxItem> _visits = [];
  late VisitCorridorDetector _detector;
  LocationSource? _locationSource;

  StreamSubscription? _fixSub;
  StreamSubscription? _visitSub;
  StreamSubscription? _corridorSub;

  @override
  void initState() {
    super.initState();
    _refreshLedger();
    _initCapturePipeline();
  }

  void _initCapturePipeline() {
    _detector = widget.detector ?? VisitCorridorDetector();
    _locationSource = widget.locationSource;

    if (_locationSource != null) {
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
    final now = DateTime.now().millisecondsSinceEpoch;
    await widget.database.insertVisit(
      kind: 'visit',
      lat: 37.775,
      lon: -122.419,
      startedAt: now,
      dwellSeconds: 120,
    );
    await _refreshLedger();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scouted a location near you')),
      );
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

  @override
  Widget build(BuildContext context) {
    final visitCount = _visits.where((v) => v.kind == 'visit').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenth Spring Scout Ledger'),
        actions: [
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
