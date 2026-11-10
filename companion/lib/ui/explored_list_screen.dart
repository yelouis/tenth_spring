import 'package:flutter/material.dart';
import '../explore/explore_store.dart';
import '../explore/places_pack.dart';

class ExploredListScreen extends StatefulWidget {
  final ExploreStore store;
  final PlacesPack pack;

  const ExploredListScreen({
    super.key,
    required this.store,
    required this.pack,
  });

  @override
  State<ExploredListScreen> createState() => _ExploredListScreenState();
}

class _ExploredListScreenState extends State<ExploredListScreen> {
  List<ExploredAreaRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.store.getAllExploredAreas();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final byPlace = <String, List<ExploredAreaRow>>{};
    for (final row in _rows) {
      byPlace.putIfAbsent(row.placeId, () => []).add(row);
    }
    final placeIds = byPlace.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explored Places'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : placeIds.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No famous places explored yet. Tap Explore Here when you visit a famous city or park.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: placeIds.length,
                  itemBuilder: (context, index) {
                    final pid = placeIds[index];
                    final placeRows = byPlace[pid]!;
                    final place = widget.pack.place(pid);
                    final placeName = place?.name ?? pid;
                    final isCity = place?.kind == 'city';
                    final k = placeRows.length;
                    final t = place?.threshold ?? 1;
                    final revealed = k >= t;

                    final headerText = isCity
                        ? '$placeName — $k of $t neighbourhoods${revealed ? " · revealed" : ""}'
                        : '$placeName · revealed';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headerText,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (isCity) ...[
                              const SizedBox(height: 8.0),
                              for (final r in placeRows)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Text(
                                    '• ${widget.pack.area(r.areaKey)?.name ?? r.areaKey}'
                                    '${r.starter ? " (Waypost)" : ""}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
