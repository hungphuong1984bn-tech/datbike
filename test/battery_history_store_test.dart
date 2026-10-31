import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/battery/battery_analytics.dart';
import 'package:mybike_app/core/battery/battery_history_store.dart';
import 'package:mybike_app/core/proto/bike_log.dart';

final t0 = DateTime(2026, 10, 31, 15, 10, 0);

BatteryLogMsg _msg(List<double> cells, {double v = 0, List<double> ntcs = const []}) => BatteryLogMsg()
  ..cellVols = List<double>.of(cells)
  ..voltage = v
  ..ntcs = List<double>.of(ntcs);

void main() {
  group('BatteryHistoryRecord', () {
    test('fromSnapshot lấy cell cao/thấp, Delta và nhiệt độ cao nhất', () {
      final s = BatteryAnalytics.analyze(_msg([3.9, 3.95], v: 7.85, ntcs: [25, 31]), t0);
      final r = BatteryHistoryRecord.fromSnapshot(s);
      expect(r.cellMaxV, closeTo(3.95, 1e-9));
      expect(r.cellMinV, closeTo(3.9, 1e-9));
      expect(r.deltaMv, closeTo(50, 1e-6));
      expect(r.tempC, 31);
    });

    test('thiếu dữ liệu thì để null, không điền số giả', () {
      final s = BatteryAnalytics.analyze(_msg(const []), t0);
      final r = BatteryHistoryRecord.fromSnapshot(s);
      expect(r.cellMaxV, isNull);
      expect(r.cellMinV, isNull);
      expect(r.deltaMv, isNull);
      expect(r.tempC, isNull);
    });

    test('NTC ngoài dải hợp lý bị bỏ, vẫn lấy NTC hợp lệ cao nhất', () {
      final s = BatteryAnalytics.analyze(_msg([3.9, 3.95], ntcs: [200, 28, -300]), t0);
      expect(BatteryHistoryRecord.fromSnapshot(s).tempC, 28);
      final bad = BatteryAnalytics.analyze(_msg([3.9, 3.95], ntcs: [200]), t0);
      expect(BatteryHistoryRecord.fromSnapshot(bad).tempC, isNull);
    });

    test('chỉ một cell hợp lệ thì không có Delta', () {
      final s = BatteryAnalytics.analyze(_msg([3.9]), t0);
      expect(BatteryHistoryRecord.fromSnapshot(s).deltaMv, isNull);
    });

    test('JSON khứ hồi và bỏ qua dữ liệu hỏng', () {
      final r = BatteryHistoryRecord(at: t0, soc: 80, packV: 72.5, deltaMv: 12.5);
      final back = BatteryHistoryRecord.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back!.at, t0);
      expect(back.soc, 80);
      expect(back.packV, 72.5);
      expect(back.deltaMv, 12.5);
      expect(back.tempC, isNull);
      expect(BatteryHistoryRecord.fromJson({'v': 1}), isNull);
      expect(BatteryHistoryRecord.fromJson({'t': 'x'}), isNull);
      expect(BatteryHistoryRecord.fromJson('rác'), isNull);
    });
  });

  group('BatteryHistorySampler', () {
    test('chỉ ghi khi đủ khoảng thời gian và thời gian tăng dần', () {
      final s = BatteryHistorySampler(interval: const Duration(minutes: 5));
      expect(s.shouldRecord(t0), isTrue);
      expect(s.shouldRecord(t0.add(const Duration(minutes: 2))), isFalse);
      expect(s.shouldRecord(t0.subtract(const Duration(minutes: 1))), isFalse);
      expect(s.shouldRecord(t0.add(const Duration(minutes: 5))), isTrue);
    });
  });

  group('BatteryHistoryAggregator', () {
    final now = DateTime(2026, 10, 31, 15, 30);
    final records = [
      BatteryHistoryRecord(at: DateTime(2026, 10, 31, 15, 10), packV: 70, deltaMv: 10, tempC: 30),
      BatteryHistoryRecord(at: DateTime(2026, 10, 31, 15, 20), packV: 72, deltaMv: 30, tempC: 34),
      BatteryHistoryRecord(at: DateTime(2026, 10, 31, 14, 5), packV: 74),
      BatteryHistoryRecord(at: DateTime(2026, 10, 30, 10, 0), packV: 75),
    ];

    test('ngày: 24 khoảng theo giờ, khoảng cuối chứa mẫu 15h', () {
      final b = BatteryHistoryAggregator.aggregate(records, HistoryRange.day, now);
      expect(b.length, 24);
      expect(b.last.start, DateTime(2026, 10, 31, 15));
      expect(b.last.count, 2);
      expect(b.last.packVAvg, closeTo(71, 1e-9));
      expect(b.last.deltaMaxMv, 30);
      expect(b.last.tempMax, 34);
      expect(b[22].count, 1);
      // Mẫu 10h ngày 30 nằm ngoài cửa sổ 24 giờ.
      expect(b.fold<int>(0, (a, x) => a + x.count), 3);
    });

    test('tuần: 7 khoảng theo ngày, gồm cả mẫu ngày hôm qua', () {
      final b = BatteryHistoryAggregator.aggregate(records, HistoryRange.week, now);
      expect(b.length, 7);
      expect(b.last.count, 3);
      expect(b[5].count, 1);
      expect(b.first.count, 0);
      expect(b.first.packVAvg, isNull);
    });

    test('tháng: 30 khoảng', () {
      final b = BatteryHistoryAggregator.aggregate(records, HistoryRange.month, now);
      expect(b.length, 30);
      expect(b.fold<int>(0, (a, x) => a + x.count), 4);
    });
  });

  group('BatteryHistoryStore', () {
    late Directory dir;
    late BatteryHistoryStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('thbike_hist_');
      store = BatteryHistoryStore(fileProvider: () async => File('${dir.path}/h.jsonl'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('ghi rồi đọc lại đúng thứ tự, bỏ qua dòng hỏng', () async {
      expect(await store.append(BatteryHistoryRecord(at: t0.add(const Duration(minutes: 5)), packV: 71)), isTrue);
      expect(await store.append(BatteryHistoryRecord(at: t0, packV: 70)), isTrue);
      File('${dir.path}/h.jsonl').writeAsStringSync('{hỏng\n', mode: FileMode.append);
      final all = await store.load();
      expect(all.map((r) => r.packV), [70, 71]);
    });

    test('đọc file chưa tồn tại trả về danh sách rỗng', () async {
      expect(await store.load(), isEmpty);
    });

    test('compact xóa mẫu quá 90 ngày', () async {
      final now = DateTime(2026, 10, 31);
      await store.append(BatteryHistoryRecord(at: now.subtract(const Duration(days: 100)), packV: 1));
      await store.append(BatteryHistoryRecord(at: now.subtract(const Duration(days: 1)), packV: 2));
      expect(await store.compact(now: now), isTrue);
      expect((await store.load()).map((r) => r.packV), [2]);
    });

    test('clear xóa toàn bộ', () async {
      await store.append(BatteryHistoryRecord(at: t0, packV: 1));
      expect(await store.clear(), isTrue);
      expect(await store.load(), isEmpty);
    });
  });
}
