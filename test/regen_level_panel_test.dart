import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybike_app/features/regen/regen_level_panel.dart';

Widget _app() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RegenLevelPanel())),
      ),
    );

void main() {
  testWidgets('khóa: đủ 5 nút, không mức nào được chọn, Áp dụng bị vô hiệu', (tester) async {
    tester.view.physicalSize = const Size(320 * 2.0, 900 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app());

    for (var i = 0; i < 5; i++) {
      expect(find.byKey(Key('regen_level_btn_$i')), findsOneWidget);
    }
    expect(find.text('Mức trên xe: chưa đọc được'), findsOneWidget);
    expect(find.byKey(const Key('regen_apply')), findsNothing);
    final locked = tester.widget<FilledButton>(find.byKey(const Key('regen_apply_locked')));
    expect(locked.onPressed, isNull);
    expect(find.byKey(const Key('regen_refresh')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('khóa: bấm nút mức → báo lý do, không có "xác nhận" nào', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(const Key('regen_level_btn_2')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Xe xác nhận'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('hiển thị giải thích cả 5 cấp', (tester) async {
    await tester.pumpWidget(_app());
    for (final l in ['ECO', 'LIGHT', 'NORMAL', 'STRONG', 'MAX']) {
      expect(find.textContaining(l, findRichText: true), findsWidgets);
    }
  });
}
