// Smoke test màn hình Firmware Lab — dựng được, render đủ số test trong catalog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybike_app/features/firmware_lab/firmware_lab_screen.dart';
import 'package:mybike_app/features/firmware_lab/lab_catalog.dart';

void main() {
  testWidgets('FirmwareLabScreen render catalog + custom char card',
      (tester) async {
    // ListView dựng lười — phóng viewport để mọi card được build.
    await tester.binding.setSurfaceSize(const Size(800, 30000));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: FirmwareLabScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🧪 KIỂM NGHIỆM FIRMWARE'), findsOneWidget);
    expect(find.text('CHAR TÙY CHỈNH (không trong danh sách)'), findsOneWidget);
    // Mỗi char trong catalog đều có card (tiêu đề hiện trong ExpansionTile)
    for (final t in labCatalog) {
      expect(find.text(t.name), findsOneWidget,
          reason: 'Thiếu card cho ${t.id}');
    }
  });
}
