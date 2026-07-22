import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:companion/main.dart';
import 'package:companion/outbox/database.dart';

void main() {
  testWidgets('Scout Ledger UI renders correctly', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(CompanionApp(database: db));
    await tester.pumpAndSettle();

    expect(find.text('Tenth Spring Scout Ledger'), findsOneWidget);
    expect(find.text('0 places scouted today'), findsOneWidget);
    expect(find.text('Sync at your PC to add them to your map.'), findsOneWidget);
  });
}
