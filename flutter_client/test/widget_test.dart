import 'package:flutter_test/flutter_test.dart';

import 'package:city_ling_client/main.dart';

void main() {
  testWidgets('City Ling shell renders main tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CityLingApp());

    expect(find.text('City Ling'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Pokedex'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });
}
