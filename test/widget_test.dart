import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/main.dart';

void main() {
  testWidgets('app opens to the document launcher', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(XournalppMobile());
    await tester.pump();

    expect(find.text('Xournal++'), findsOneWidget);
  });
}
