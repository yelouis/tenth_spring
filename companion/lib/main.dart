import 'package:flutter/material.dart';
import 'outbox/database.dart';
import 'ui/scout_ledger_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  runApp(CompanionApp(database: database));
}

class CompanionApp extends StatelessWidget {
  final AppDatabase database;

  const CompanionApp({super.key, required this.database});

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
      home: ScoutLedgerScreen(database: database),
    );
  }
}
