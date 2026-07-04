import 'package:flutter_test/flutter_test.dart';
import 'package:erpcomplete_messenger/main.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const ErpMessengerApp());
    await tester.pump();
    expect(find.text('ERPComplete Messenger'), findsOneWidget);
  });
}
