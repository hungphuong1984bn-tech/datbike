import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/battery/balancing_monitor.dart';
import 'package:mybike_app/core/battery/battery_analytics.dart';
import 'package:mybike_app/core/battery/battery_config.dart';
import 'package:mybike_app/core/battery/battery_history.dart';
import 'package:mybike_app/core/battery/battery_sessions.dart';
import 'package:mybike_app/core/battery/cell_model.dart';
import 'package:mybike_app/core/battery/cell_protection_engine.dart';
import 'package:mybike_app/core/proto/bike_log.dart';

final t0 = DateTime(2026, 10, 30, 12, 0, 0);

BatteryLogMsg msg(List<double> cells,
    {double v = 0, double i = 0, int bal = 0, List<double> ntcs = const [], int prot = 0, int err = 0}) {
  final m = BatteryLogMsg()
    ..cellVols = List<double>.of(cells)
    ..voltage = v
    ..current = i
    ..balancing = bal
    ..ntcs = List<double>.of(ntcs)
    ..protection = prot
    ..error = err;
  return m;
}

PackSnapshot pack(List<double> cells,
        {DateTime? at, BatteryConfig cfg = BatteryConfig.defaults, double v = 0, int bal = 0, List<double> ntcs = const [], int prot = 0, int err = 0}) =>
    BatteryAnalytics.analyze(msg(cells, v: v, bal: bal, ntcs: ntcs, prot: prot, err: err), at ?? t0, cfg: cfg);

ProtectionReport eval(PackSnapshot? p,
        {BatteryConfig cfg = BatteryConfig.defaults, bool connected = true, DateTime? now, double? bmsTemp, List<CellTrend> trends = const []}) =>
    CellProtectionEngine.evaluate(
      pack: p,
      now: now ?? t0.add(const Duration(seconds: 1)),
      connected: connected,
      cfg: cfg,
      telemetryBmsTempC: bmsTemp,
      trends: trends,
    );

void main() {
  group('Delta V & phân loại cell', () {
    test('ΔV tính đúng và xác định cell cao/thấp nhất', () {
      final p = pack([3.650, 3.700, 3.640, 3.660]);
      expect(p.deltaMv, closeTo(60.0, 1e-6));
      expect(p.maxIndex, 1);
      expect(p.minIndex, 2);
      expect(p.vAvg, closeTo(3.6625, 1e-9));
      expect(p.cells[1].isMax, isTrue);
      expect(p.cells[2].isMin, isTrue);
      expect(p.cells[0].deviationMv, closeTo(-12.5, 1e-6));
    });

    test('deltaMv helper: <2 cell hợp lệ → null, bỏ qua cell lỗi', () {
      expect(BatteryAnalytics.deltaMv(const []), isNull);
      expect(BatteryAnalytics.deltaMv(const [3.6]), isNull);
      expect(BatteryAnalytics.deltaMv(const [3.6, 0.0, double.nan, 9.9]), isNull);
      expect(BatteryAnalytics.deltaMv(const [3.6, 3.62, 0.0]), closeTo(20.0, 1e-6));
    });

    test('cell giá trị lỗi bị đánh dấu invalid và không làm sai thống kê', () {
      final p = pack([3.65, 0.0, 3.66, double.nan, 3.67]);
      expect(p.cellCount, 5);
      expect(p.validCount, 3);
      expect(p.cells[1].status, CellStatus.invalid);
      expect(p.cells[3].status, CellStatus.invalid);
      expect(p.deltaMv, closeTo(20.0, 1e-6));
      expect(p.vAvg, closeTo(3.66, 1e-9));
    });

    test('phân loại theo độ lệch cấu hình (không có ngưỡng điện áp tuyệt đối mặc định)', () {
      // 10 cell 3.70, một cell thấp hơn 70 mV → CRITICAL (≥60 mV so với TB).
      final cells = [...List.filled(9, 3.700), 3.630];
      final p = pack(cells);
      expect(p.cells.last.status, CellStatus.critical);
      expect(p.cells.first.status, CellStatus.ok);
      // Điện áp thấp tuyệt đối KHÔNG được tự coi là lỗi khi chưa cấu hình.
      final low = pack(List.filled(8, 2.9));
      expect(low.cells.every((c) => c.status == CellStatus.ok), isTrue);
    });

    test('ngưỡng tuyệt đối chỉ hoạt động sau khi cấu hình', () {
      // Nới ngưỡng độ lệch để chỉ kiểm tra ngưỡng điện áp tuyệt đối.
      const cfg = BatteryConfig(
        cellUnderVoltWarnV: 3.2,
        cellUnderVoltCritV: 3.0,
        cellDeviationWarnMv: 900,
        cellDeviationCritMv: 1000,
      );
      final p = pack([3.5, 3.5, 3.15, 2.95, 3.5], cfg: cfg);
      expect(p.cells[2].status, CellStatus.warning);
      expect(p.cells[3].status, CellStatus.critical);
    });

    test('số cell thay đổi theo dữ liệu đầu vào (20, 23, 24)', () {
      for (final n in [20, 23, 24]) {
        final p = pack(List.generate(n, (i) => 3.6 + i * 0.001));
        expect(p.cellCount, n);
        expect(p.cells.last.label, 'Cell ${n.toString().padLeft(2, '0')}');
      }
      expect(pack(const []).hasCells, isFalse);
    });

    test('dữ liệu rỗng không tạo cell giả', () {
      final p = pack(const []);
      expect(p.cells, isEmpty);
      expect(p.hasStats, isFalse);
      expect(p.deltaMv, 0.0);
    });
  });

  group('Freshness', () {
    test('live / stale / lost / none', () {
      final now = t0.add(const Duration(seconds: 5));
      expect(BmsFreshness.evaluate(receivedAt: t0, now: now, connected: true), BmsFreshness.live);
      expect(BmsFreshness.evaluate(receivedAt: t0, now: t0.add(const Duration(seconds: 20)), connected: true), BmsFreshness.stale);
      expect(BmsFreshness.evaluate(receivedAt: t0, now: now, connected: false), BmsFreshness.lost);
      expect(BmsFreshness.evaluate(receivedAt: null, now: now, connected: true), BmsFreshness.none);
    });
  });

  group('Cell Protection Engine', () {
    test('pack đồng đều, dữ liệu trực tiếp → NORMAL không cảnh báo', () {
      final r = eval(pack(List.filled(20, 3.7), v: 74.0));
      expect(r.overall, AlertSeverity.normal);
      expect(r.alerts, isEmpty);
      expect(r.evaluatedLive, isTrue);
    });

    test('không tự đặt ngưỡng quá/thấp áp khi chưa cấu hình', () {
      final r = eval(pack(List.filled(20, 4.6)));
      expect(r.alerts.where((a) => a.type == AlertType.cellOverVoltage), isEmpty);
    });

    test('quá áp CRITICAL khi đã cấu hình', () {
      const cfg = BatteryConfig(cellOverVoltWarnV: 4.15, cellOverVoltCritV: 4.25);
      final r = eval(pack([...List.filled(9, 4.0), 4.27], cfg: cfg), cfg: cfg);
      final a = r.alerts.firstWhere((x) => x.type == AlertType.cellOverVoltage);
      expect(a.severity, AlertSeverity.critical);
      expect(a.cellIndices, [9]);
      expect(r.overall, AlertSeverity.critical);
    });

    test('ΔV WARNING và CRITICAL theo cấu hình', () {
      final warn = eval(pack([3.70, 3.70, 3.70, 3.61])); // 90 mV
      expect(warn.alerts.any((a) => a.id == 'delta-warn'), isTrue);
      final crit = eval(pack([3.70, 3.70, 3.70, 3.57])); // 130 mV
      expect(crit.alerts.any((a) => a.id == 'delta-crit'), isTrue);
      expect(crit.overall, AlertSeverity.critical);
    });

    test('cảnh báo có đủ thông tin: cell, giá trị đo, thời điểm, nguyên nhân, khuyến nghị', () {
      final r = eval(pack([3.70, 3.70, 3.70, 3.57]));
      final a = r.alerts.firstWhere((x) => x.id == 'delta-crit');
      expect(a.cellIndices, isNotEmpty);
      expect(a.measured, contains('mV'));
      expect(a.cause, isNotEmpty);
      expect(a.recommendation, isNotEmpty);
      expect(a.since, isNotNull);
    });

    test('dữ liệu cũ: không đánh giá số đo cũ như trực tiếp', () {
      final p = pack([3.70, 3.70, 3.70, 3.50]);
      final r = eval(p, now: t0.add(const Duration(seconds: 30)));
      expect(r.freshness, BmsFreshness.stale);
      expect(r.evaluatedLive, isFalse);
      expect(r.alerts.any((a) => a.id == 'delta-crit'), isFalse);
      expect(r.alerts.any((a) => a.type == AlertType.dataTimeout), isTrue);
    });

    test('mất kết nối: báo linkLost, không đánh giá cell', () {
      final r = eval(pack([3.7, 3.7, 3.7, 3.4]), connected: false);
      expect(r.freshness, BmsFreshness.lost);
      expect(r.alerts.single.type, AlertType.linkLost);
    });

    test('chưa có gói nào: không cảnh báo, không giả lập', () {
      final r = eval(null);
      expect(r.alerts, isEmpty);
      expect(r.freshness, BmsFreshness.none);
    });

    test('gói không có cell → cảnh báo mất dữ liệu cell', () {
      final r = eval(pack(const []));
      expect(r.alerts.any((a) => a.type == AlertType.cellDataMissing), isTrue);
    });

    test('cell dữ liệu lỗi được báo', () {
      final r = eval(pack([3.7, 0.0, 3.7, 3.7]));
      expect(r.alerts.any((a) => a.type == AlertType.cellDataInvalid), isTrue);
    });

    test('nhiệt độ NTC cao, NTC lỗi, NTC chênh lệch', () {
      final hot = eval(pack(List.filled(6, 3.7), ntcs: const [30, 60]));
      expect(hot.alerts.any((a) => a.id == 'temp-crit'), isTrue);
      final bad = eval(pack(List.filled(6, 3.7), ntcs: const [30, 300]));
      expect(bad.alerts.any((a) => a.id == 'ntc-invalid'), isTrue);
      final spread = eval(pack(List.filled(6, 3.7), ntcs: const [25, 40]));
      expect(spread.alerts.any((a) => a.id == 'ntc-spread'), isTrue);
      final bms = eval(pack(List.filled(6, 3.7)), bmsTemp: 50);
      expect(bms.alerts.any((a) => a.id == 'temp-warn'), isTrue);
    });

    test('dữ liệu không đồng bộ: tổng cell lệch xa điện áp pack', () {
      final bad = eval(pack(List.filled(20, 3.7), v: 60.0)); // tổng 74 V
      expect(bad.alerts.any((a) => a.type == AlertType.packSyncMismatch), isTrue);
      final ok = eval(pack(List.filled(20, 3.7), v: 74.2));
      expect(ok.alerts.any((a) => a.type == AlertType.packSyncMismatch), isFalse);
    });

    test('cờ bảo vệ/lỗi của BMS được báo nhưng không diễn giải bit', () {
      final r = eval(pack(List.filled(6, 3.7), prot: 4, err: 0));
      final a = r.alerts.firstWhere((x) => x.type == AlertType.bmsFlags);
      expect(a.cause, contains('CHƯA'));
    });

    test('suy giảm bất thường chỉ khi đủ mẫu lịch sử', () {
      final p = pack([3.70, 3.70, 3.70, 3.70, 3.70, 3.70, 3.70, 3.655]);
      expect(eval(p).alerts.any((a) => a.id == 'degradation'), isFalse);
      final r = eval(p, trends: const [CellTrend(7, -45.0, 120)]);
      expect(r.alerts.any((a) => a.id == 'degradation'), isTrue);
    });

    test('thời điểm phát sinh giữ nguyên qua các lần đánh giá', () {
      final p = pack([3.70, 3.70, 3.70, 3.57]);
      final first = eval(p);
      final since = {for (final a in first.alerts) a.id: a.since};
      final second = CellProtectionEngine.evaluate(
        pack: p,
        now: t0.add(const Duration(seconds: 4)),
        connected: true,
        cfg: BatteryConfig.defaults,
        activeSince: since,
      );
      final a1 = first.alerts.firstWhere((x) => x.id == 'delta-crit');
      final a2 = second.alerts.firstWhere((x) => x.id == 'delta-crit');
      expect(a2.since, a1.since);
    });
  });

  group('Balancing Monitor', () {
    test('cờ = 0 không tạo sự kiện giả', () {
      final m = BalancingMonitor();
      m.onPack(pack([3.7, 3.7, 3.7], at: t0));
      expect(m.state, BalancingState.off);
      expect(m.events, isEmpty);
    });

    test('ghi nhận bắt đầu/kết thúc với ΔV trước-sau', () {
      final m = BalancingMonitor();
      m.onPack(pack([3.70, 3.70, 3.64], at: t0, bal: 1)); // 60 mV
      expect(m.state, BalancingState.on);
      expect(m.ongoing, isNotNull);
      m.onPack(pack([3.70, 3.69, 3.67], at: t0.add(const Duration(minutes: 5)), bal: 1)); // 30 mV
      m.onPack(pack([3.69, 3.69, 3.685], at: t0.add(const Duration(minutes: 9)), bal: 0)); // 5 mV
      expect(m.state, BalancingState.off);
      final e = m.events.single;
      expect(e.isOngoing, isFalse);
      expect(e.deltaBeforeMv, closeTo(60, 1e-6));
      expect(e.deltaAfterMv, closeTo(5, 1e-6));
      expect(e.deltaReductionMv, closeTo(55, 1e-6));
      expect(e.endReason, BalancingEndReason.completed);
    });

    test('mất kết nối không bị coi là cân bằng hoàn tất', () {
      final m = BalancingMonitor();
      m.onPack(pack([3.70, 3.70, 3.64], at: t0, bal: 1));
      m.onLinkLost(t0.add(const Duration(minutes: 1)));
      expect(m.state, BalancingState.unknown);
      expect(m.events.single.endReason, BalancingEndReason.linkLost);
    });

    test('kiểu cân bằng luôn là "chưa xác minh"', () {
      expect(BalancingMethod.values.length, 1);
      expect(BalancingMethod.unverified.label, contains('Chưa'));
    });

    test('khuyến nghị theo ΔV và theo độ tươi dữ liệu', () {
      const cfg = BatteryConfig.defaults;
      final hi = BalancingAdvisor.advise(
          pack: pack([3.70, 3.70, 3.57]), cfg: cfg, freshness: BmsFreshness.live);
      expect(hi.level, AlertSeverity.critical);
      final stale = BalancingAdvisor.advise(
          pack: pack([3.70, 3.70, 3.57]), cfg: cfg, freshness: BmsFreshness.stale);
      expect(stale.level, AlertSeverity.normal);
      expect(stale.headline, contains('không còn trực tiếp'));
    });
  });

  group('Battery History', () {
    test('giới hạn bộ nhớ theo dung lượng', () {
      final s = Series(100);
      for (var i = 0; i < 1000; i++) {
        s.add(t0.add(Duration(seconds: i)), i.toDouble());
      }
      expect(s.values().length, lessThanOrEqualTo(100));
      expect(s.last, 999.0);
    });

    test('bỏ qua giá trị NaN', () {
      final s = Series(10)..add(t0, double.nan)..add(t0, 1.0);
      expect(s.length, 1);
    });

    test('lịch sử cell reset khi số cell thay đổi', () {
      final h = BatteryHistory();
      h.add(pack(List.filled(20, 3.7), at: t0));
      h.add(pack(List.filled(20, 3.7), at: t0.add(const Duration(seconds: 2))));
      expect(h.cellSeries(0)!.length, 2);
      final reset = h.add(pack(List.filled(23, 3.7), at: t0.add(const Duration(seconds: 4))));
      expect(reset, isTrue);
      expect(h.cellCount, 23);
      expect(h.cellSeries(0)!.length, 1);
      expect(h.resetCount, 1);
    });

    test('cực trị phiên và xu hướng lệch', () {
      final h = BatteryHistory();
      for (var i = 0; i < 80; i++) {
        h.add(pack([3.70, 3.70, 3.70, 3.66 + (i % 2) * 0.001], at: t0.add(Duration(seconds: i * 2))));
      }
      expect(h.minOf(3)!.voltage, closeTo(3.66, 1e-9));
      expect(h.maxOf(3)!.voltage, closeTo(3.661, 1e-9));
      final t = h.trendOf(3, 60);
      expect(t, isNotNull);
      expect(t!.meanDeviationMv, lessThan(-20));
      expect(h.trendOf(0, 60)!.meanDeviationMv.abs(), lessThan(15));
      expect(h.trendOf(3, 1000), isNull);
    });
  });

  group('Activity tracker (sạc/xả)', () {
    test('không có telemetry → không ghi nhận', () {
      final a = ActivityTracker();
      a.onSample(at: t0, phaseA: null, packV: 80);
      expect(a.sessions, isEmpty);
    });

    test('ghi phiên sạc/xả theo dấu phase đã xác minh', () {
      final a = ActivityTracker();
      a.onSample(at: t0, phaseA: -12, packV: 80, soc: 70);
      a.onSample(at: t0.add(const Duration(seconds: 40)), phaseA: -20, packV: 78, soc: 69);
      a.onSample(at: t0.add(const Duration(seconds: 60)), phaseA: 0.1, packV: 79, soc: 69);
      expect(a.ongoing, isNull);
      final s = a.sessions.single;
      expect(s.activity, PackActivity.discharging);
      expect(s.peakCurrentA, 20);
      expect(ActivityTracker.classify(15), PackActivity.charging);
      expect(ActivityTracker.classify(0.2), PackActivity.idle);
    });

    test('phiên quá ngắn bị bỏ', () {
      final a = ActivityTracker();
      a.onSample(at: t0, phaseA: 10, packV: 80);
      a.onSample(at: t0.add(const Duration(seconds: 5)), phaseA: 0, packV: 80);
      expect(a.sessions, isEmpty);
    });
  });

  group('Cấu hình', () {
    test('mặc định: ngưỡng điện áp cell TẮT', () {
      expect(BatteryConfig.defaults.hasAbsoluteVoltageLimits, isFalse);
    });

    test('JSON round-trip và validate', () {
      const c = BatteryConfig(cellOverVoltWarnV: 4.1, cellOverVoltCritV: 4.2, deltaWarnMv: 50, deltaCritMv: 90);
      final r = BatteryConfig.fromJson(c.toJson());
      expect(r.cellOverVoltCritV, 4.2);
      expect(r.cellUnderVoltCritV, isNull);
      expect(r.deltaWarnMv, 50);
      expect(r.validate(), isNull);
      expect(const BatteryConfig(deltaWarnMv: 100, deltaCritMv: 50).validate(), isNotNull);
      expect(const BatteryConfig(cellOverVoltWarnV: 4.2, cellOverVoltCritV: 4.1).validate(), isNotNull);
    });
  });

  group('An toàn: không có lệnh điều khiển BMS', () {
    test('mã BMS mới không chứa lệnh ghi BLE', () {
      final files = <File>[
        ...Directory('lib/core/battery').listSync(recursive: true).whereType<File>(),
        ...Directory('lib/features/battery').listSync(recursive: true).whereType<File>(),
      ].where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      final banned = RegExp(r'\.write\(|writeValue|writeCharacteristic|characteristic\.write|BluetoothCharacteristic|withoutResponse');
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          expect(banned.hasMatch(line), isFalse, reason: '${f.path}:${i + 1} chứa lệnh ghi BLE: $line');
        }
      }
    });
  });
}
