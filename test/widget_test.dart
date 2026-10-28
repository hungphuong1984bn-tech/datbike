import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mybike_app/main.dart';

void main() {
  testWidgets('MyBikeApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyBikeApp()));
    expect(find.byType(MyBikeApp), findsOneWidget);
  });
}
