import 'package:flutter/material.dart';
import '../outbox/database.dart';

class ScoutLedgerScreen extends StatefulWidget {
  final AppDatabase database;

  const ScoutLedgerScreen({super.key, required this.database});

  @override
  State<ScoutLedgerScreen> createState() => _ScoutLedgerScreenState();
}

class _ScoutLedgerScreenState extends State<ScoutLedgerScreen> {
  bool _isScoutingPaused = false;
  List<VisitOutboxItem> _visits = [];

  @override
  void initState() {
    super.initState();
    _refreshLedger();
  }

  Future<void> _refreshLedger() async {
    final visits = await widget.database.getAllVisits();
    setState(() {
      _visits = visits;
    });
  }

  Future<void> _triggerManualScout() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Manual fix: fuzzed default coords for demo/manual button
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
            onPressed: () {
              setState(() {
                _isScoutingPaused = !_isScoutingPaused;
              });
            },
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
