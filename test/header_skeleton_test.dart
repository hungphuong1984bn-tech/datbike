import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_controller.dart' show BlePhase;
import 'package:mybike_app/core/proximity/smart_key_state.dart';
import 'package:mybike_app/features/home/overview_header.dart';
import 'package:mybike_app/ui/ds/ds.dart';

Widget _wrap(Widget c) => MaterialApp(home: Scaffold(body: c));

void main() {
  testWidgets('header: Smart Key + chuông hiện số cảnh báo và gọi callback', (t) async {
    var bell = 0, key = 0;
    await t.pumpWidget(_wrap(OverviewHeader(
      phase: BlePhase.connected,
      bikeName: 'Quantum S1',
      onSwitchBike: () {},
      onConnect: () {},
      onHud: () {},
      smartKey: const SmartKeyView(
          SmartKeyState.unlocked, SmartKeyTone.green, 'Đã mở khóa', ''),
      onSmartKey: () => key++,
      alertCount: 2,
      onNotifications: () => bell++,
    )));
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byTooltip('Thông báo'));
    expect(bell, 1);
    await t.tap(find.byIcon(Icons.lock_open_rounded));
    expect(key, 1);
  });

  testWidgets('header: không truyền smartKey/chuông → không hiện', (t) async {
    await t.pumpWidget(_wrap(OverviewHeader(
      phase: BlePhase.idle,
      bikeName: null,
      onSwitchBike: () {},
      onConnect: () {},
      onHud: () {},
    )));
    expect(find.byTooltip('Thông báo'), findsNothing);
    expect(find.byIcon(Icons.key_rounded), findsNothing);
  });

  testWidgets('SkeletonGrid dựng đủ số ô, không chứa chữ số liệu', (t) async {
    await t.pumpWidget(_wrap(const SingleChildScrollView(child: SkeletonGrid(count: 4))));
    expect(find.byType(SkeletonCard), findsNWidgets(4));
    expect(find.byType(Text), findsNothing);
    await t.pumpWidget(const SizedBox()); // dừng animation lặp
  });
}
