import 'package:flutter_test/flutter_test.dart';

import 'package:caliu/main.dart';

void main() {
  testWidgets('App arrenca amb el mapa', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Explorar Esdeveniments (Caliu)'), findsOneWidget);
  });
}
