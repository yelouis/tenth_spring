import 'package:flutter/material.dart';
import 'capture/os_location_source.dart';
import 'outbox/database.dart';
import 'ui/scout_ledger_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  final locationSource = OsLocationSource();
  runApp(CompanionApp(
    database: database,
    locationSource: locationSource,
  ));
}

class CompanionApp extends StatelessWidget {
  final AppDatabase database;
  final OsLocationSource? locationSource;

  const CompanionApp({
    super.key,
    required this.database,
    this.locationSource,
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
      home: ScoutLedgerScreen(
        database: database,
        locationSource: locationSource,
      ),
    );
  }
}
