import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybike_app/core/proximity/proximity_controller.dart';
import 'package:mybike_app/features/proximity/smart_key_radar.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('chưa kết nối → "--", không bịa khoảng cách', (tester) async {
    await tester.pumpWidget(_wrap(const SmartKeyRadarCard(
      prox: ProximitySnapshot(distanceM: 0.8, distanceConfidence: 0.9),
      connected: false,
    )));
    final t = tester.widget<Text>(find.byKey(const Key('smart_key_radar_distance')));
    expect(t.data, '--');
    expect(find.textContaining('Chưa kết nối'), findsOneWidget);
  });

  testWidgets('đã kết nối, có mẫu → hiện khoảng cách và trong vùng', (tester) async {
    await tester.pumpWidget(_wrap(const SmartKeyRadarCard(
      prox: ProximitySnapshot(distanceM: 0.8, distanceConfidence: 0.8),
      connected: true,
    )));
    final t = tester.widget<Text>(find.byKey(const Key('smart_key_radar_distance')));
    expect(t.data, '≈ 0.8 m');
    expect(find.textContaining('Trong vùng nhận diện'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose controller sạch
  });

  testWidgets('ngoài giới hạn 2 m → báo ngoài vùng', (tester) async {
    await tester.pumpWidget(_wrap(const SmartKeyRadarCard(
      prox: ProximitySnapshot(distanceM: 3.1, distanceConfidence: 0.5),
      connected: true,
    )));
    expect(find.textContaining('Ngoài vùng nhận diện'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('đã kết nối nhưng chưa có mẫu → chờ tín hiệu', (tester) async {
    await tester.pumpWidget(_wrap(const SmartKeyRadarCard(
      prox: ProximitySnapshot(),
      connected: true,
    )));
    expect(find.textContaining('Đang chờ mẫu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
