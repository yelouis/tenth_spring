import 'package:flutter/material.dart';
import 'explore/explore_service.dart';
import 'explore/places_pack.dart';
import 'outbox/database.dart';
import 'sync/scout_link.dart';
import 'ui/explore_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  PlacesPack? pack;
  try {
    pack = await PlacesPack.loadAsset();
  } catch (_) {}
  runApp(
    CompanionApp(
      database: database,
      initialPack: pack,
    ),
  );
}

class CompanionApp extends StatelessWidget {
  final AppDatabase database;
  final PlacesPack? initialPack;
  final PositionSource? positionSource;
  final ScoutLink? scoutLink;

  const CompanionApp({
    super.key,
    required this.database,
    this.initialPack,
    this.positionSource,
    this.scoutLink,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tenth Spring Companion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ExploreScreen(
        database: database,
        initialPack: initialPack,
        positionSource: positionSource,
        scoutLink: scoutLink,
      ),
    );
  }
}
