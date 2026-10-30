// Test LOGIC của ProximityEngine bằng chuỗi RSSI MÔ PHỎNG.
// Đây là kiểm thử tự động (đơn vị) — KHÔNG phải kiểm thử trên xe thật.
// Chuỗi RSSI ở đây do test tự dựng, không phải dữ liệu đo từ xe.

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/proximity/proximity_engine.dart';

const _cfgBoth = ProximityConfig(
  unlockEnabled: true,
  lockEnabled: true,
  sensitivity: 1,
  calibratedRssi1m: -50.0,
);

ProximityContext _ctx({
  bool connected = true,
  bool authorized = true,
  bool fresh = true,
  double? speed = 0.0,
  bool on = true,
  bool locked = false,
  bool gear = false,
  bool busy = false,
  bool user = false,
  bool lab = false,
  bool autoPower = false,
}) => ProximityContext(
  connected: connected,
  authorized: authorized,
  telemetryFresh: fresh,
  speedKmh: speed,
  bikeOn: on,
  bikeLocked: locked,
  bikeInDriveGear: gear,
  commandBusy: busy,
  userRecentlyActed: user,
  labMode: lab,
  autoPowerOn: autoPower,
);

/// Nạp [seconds] giây mẫu RSSI [rssi] (1 mẫu/giây) rồi trả về quyết định cuối.
ProximityDecision _feed(
  ProximityEngine e,
  ProximityConfig c,
  ProximityContext ctx,
  DateTime start,
  double rssi,
  int seconds, {
  double jitter = 0,
}) {
  var d = ProximityDecision.none;
  for (var i = 0; i <= seconds; i++) {
    final t = start.add(Duration(seconds: i));
    final j = jitter == 0 ? 0.0 : (i.isEven ? jitter : -jitter);
    e.addSample(rssi + j, t);
    d = e.evaluate(c, ctx, t);
    if (d.action != ProximityAction.none) return d;
  }
  return d;
}

void main() {
  final t0 = DateTime(2026, 10, 30, 8);

  group('Ngưỡng', () {
    test('hysteresis: ngưỡng xa luôn thấp hơn ngưỡng gần ≥ 4 dB', () {
      final e = ProximityEngine();
      for (final s in [0, 1, 2]) {
        final c = ProximityConfig(sensitivity: s, calibratedRssi1m: -50);
        expect(
          e.unlockThreshold(c) - e.lockThreshold(c) >= ProximityEngine.minGapDb,
          isTrue,
        );
      }
    });
    test('chưa hiệu chỉnh → dùng ngưỡng cũ', () {
      final e = ProximityEngine();
      const c = ProximityConfig();
      expect(e.unlockThreshold(c), equals(-55.0));
      expect(e.lockThreshold(c), equals(-83.0));
    });
    test(
      'độ nhạy cao → mở khóa dễ hơn (ngưỡng cao hơn... ít khắt khe hơn)',
      () {
        final e = ProximityEngine();
        const lo = ProximityConfig(sensitivity: 0, calibratedRssi1m: -50);
        const hi = ProximityConfig(sensitivity: 2, calibratedRssi1m: -50);
        expect(e.unlockThreshold(hi) < e.unlockThreshold(lo), isTrue);
      },
    );
  });

  group('Lọc', () {
    test('một mẫu nhiễu đột biến bị loại', () {
      final e = ProximityEngine();
      for (var i = 0; i < 8; i++) {
        e.addSample(-50, t0.add(Duration(seconds: i)));
      }
      final f = e.addSample(-95, t0.add(const Duration(seconds: 9)));
      expect(f, closeTo(-50, 1.0));
    });
    test('thay đổi thật (liên tục) vẫn được chấp nhận', () {
      final e = ProximityEngine();
      for (var i = 0; i < 8; i++) {
        e.addSample(-50, t0.add(Duration(seconds: i)));
      }
      for (var i = 0; i < 20; i++) {
        e.addSample(-85, t0.add(Duration(seconds: 10 + i)));
      }
      expect(e.filteredRssi!, lessThan(-80));
    });
  });

  group('Smart Unlock', () {
    test('đứng gần đủ lâu + bị khóa → mở khóa', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -49, 6);
      expect(d.action, equals(ProximityAction.unlock));
    });
    test('RSSI trung gian (không đủ gần) → không mở', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -62, 10);
      expect(d.action, equals(ProximityAction.none));
    });
    test('một khoảnh khắc gần (spike) không mở', () {
      final e = ProximityEngine();
      for (var i = 0; i < 8; i++) {
        e.addSample(-70, t0.add(Duration(seconds: i)));
        e.evaluate(_cfgBoth, _ctx(locked: true), t0.add(Duration(seconds: i)));
      }
      e.addSample(-40, t0.add(const Duration(seconds: 8)));
      final d = e.evaluate(
        _cfgBoth,
        _ctx(locked: true),
        t0.add(const Duration(seconds: 8)),
      );
      expect(d.action, equals(ProximityAction.none));
    });
    test('chưa xác thực phiên → không mở, ở trạng thái verifying', () {
      final e = ProximityEngine();
      final d = _feed(
        e,
        _cfgBoth,
        _ctx(locked: true, authorized: false),
        t0,
        -49,
        6,
      );
      expect(d.action, equals(ProximityAction.none));
      expect(e.status, equals(ProximityStatus.verifying));
    });
    test('quá hạn chờ xác thực → blocked (không ép lệnh)', () {
      final e = ProximityEngine();
      _feed(e, _cfgBoth, _ctx(locked: true, authorized: false), t0, -49, 20);
      expect(e.status, equals(ProximityStatus.blocked));
    });
    test('vừa thao tác tay → không tự mở', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(locked: true, user: true), t0, -49, 6);
      expect(d.action, equals(ProximityAction.none));
    });
    test('đã mở rồi → không lặp lệnh khi vẫn đứng gần', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -49, 6);
      expect(d.action, equals(ProximityAction.unlock));
      e.reportResult(
        ProximityAction.unlock,
        true,
        t0.add(const Duration(seconds: 7)),
        'ok',
      );
      // app vẫn nghĩ bị khóa (giả lập lệnh chưa có hiệu lực) — vẫn không lặp.
      final d2 = _feed(
        e,
        _cfgBoth,
        _ctx(locked: true, on: false),
        t0.add(const Duration(seconds: 8)),
        -49,
        60,
      );
      expect(d2.action, equals(ProximityAction.none));
    });
    test('tắt tính năng → không làm gì', () {
      final e = ProximityEngine();
      const off = ProximityConfig(calibratedRssi1m: -50);
      final d = _feed(e, off, _ctx(locked: true), t0, -49, 6);
      expect(d.action, equals(ProximityAction.none));
      expect(e.status, equals(ProximityStatus.off));
    });
    test(
      'khóa tay xong đứng cạnh xe → không tự mở lại; rời xa rồi quay lại → mở',
      () {
        final e = ProximityEngine();
        e.noteUserCommand(t0, locked: true);
        final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -49, 8);
        expect(d.action, equals(ProximityAction.none));
        final t1 = t0.add(const Duration(seconds: 10));
        _feed(e, _cfgBoth, _ctx(locked: true, on: false), t1, -90, 8);
        expect(e.unlockArmed, isTrue);
        final t2 = t1.add(const Duration(seconds: 12));
        final d2 = _feed(
          e,
          _cfgBoth,
          _ctx(locked: true, on: false),
          t2,
          -49,
          8,
        );
        expect(d2.action, equals(ProximityAction.unlock));
      },
    );
  });

  group('Auto Lock', () {
    ProximityEngine armedNear() {
      final e = ProximityEngine();
      _feed(e, _cfgBoth, _ctx(), t0, -49, 5); // từng ở gần → armed
      expect(e.lockArmed, isTrue);
      return e;
    }

    test('rời xa đủ lâu + xe đứng yên ở P → khóa', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      final d = _feed(e, _cfgBoth, _ctx(), t1, -88, 20);
      expect(d.action, equals(ProximityAction.lock));
    });
    test('chưa từng ở gần trong phiên → không khóa', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(), t0, -90, 30);
      expect(d.action, equals(ProximityAction.none));
    });
    test('xe đang chạy → không khóa', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      final d = _feed(e, _cfgBoth, _ctx(speed: 12.0), t1, -90, 30);
      expect(d.action, equals(ProximityAction.none));
    });
    test('đang ở số lái dù tốc độ 0 → không khóa', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      final d = _feed(e, _cfgBoth, _ctx(gear: true), t1, -90, 30);
      expect(d.action, equals(ProximityAction.none));
    });
    test('chưa biết tốc độ / telemetry cũ → không khóa', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      expect(
        _feed(e, _cfgBoth, _ctx(speed: null), t1, -90, 30).action,
        equals(ProximityAction.none),
      );
      final e2 = armedNear();
      expect(
        _feed(e2, _cfgBoth, _ctx(fresh: false), t1, -90, 30).action,
        equals(ProximityAction.none),
      );
    });
    test('tín hiệu yếu thoáng qua (đi qua vật cản) không khóa', () {
      final e = armedNear();
      var t = t0.add(const Duration(seconds: 6));
      // yếu 2 giây rồi trở lại gần
      for (var i = 0; i < 2; i++) {
        e.addSample(-90, t);
        e.evaluate(_cfgBoth, _ctx(), t);
        t = t.add(const Duration(seconds: 1));
      }
      final d = _feed(e, _cfgBoth, _ctx(), t, -49, 10);
      expect(d.action, equals(ProximityAction.none));
    });
    test('mất mẫu RSSI (stale) KHÔNG bị coi là rời xe', () {
      final e = armedNear();
      // không có mẫu mới nữa; chỉ evaluate sau 30 s
      final d = e.evaluate(
        _cfgBoth,
        _ctx(),
        t0.add(const Duration(seconds: 40)),
      );
      expect(d.action, equals(ProximityAction.none));
      expect(e.status, equals(ProximityStatus.searching));
    });
    test('mất kết nối → reset, không khóa', () {
      final e = armedNear();
      e.resetLink(t0.add(const Duration(seconds: 7)));
      final d = e.evaluate(
        _cfgBoth,
        _ctx(connected: false),
        t0.add(const Duration(seconds: 8)),
      );
      expect(d.action, equals(ProximityAction.none));
      expect(e.lockArmed, isFalse);
    });
    test('xe đã tắt/khóa sẵn → không gửi lệnh khóa', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      // Xe đã tắt (không cần khóa thêm) hoặc đã khóa: tuyệt đối không có lệnh KHÓA.
      final off = _feed(
        e,
        _cfgBoth,
        _ctx(on: false, locked: false),
        t1,
        -90,
        30,
      );
      expect(off.action, equals(ProximityAction.none));
      final e2 = armedNear();
      final locked = _feed(
        e2,
        _cfgBoth,
        _ctx(on: false, locked: true),
        t1,
        -90,
        30,
      );
      expect(locked.action == ProximityAction.lock, isFalse);
    });
    test('Lab mode → tạm dừng', () {
      final e = armedNear();
      final t1 = t0.add(const Duration(seconds: 6));
      expect(
        _feed(e, _cfgBoth, _ctx(lab: true), t1, -90, 30).action,
        equals(ProximityAction.none),
      );
    });
  });

  group('Chống lặp / thất bại', () {
    test('thất bại → backoff, không thử lại ngay', () {
      final e = ProximityEngine();
      final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -49, 6);
      expect(d.action, equals(ProximityAction.unlock));
      e.reportResult(
        ProximityAction.unlock,
        false,
        t0.add(const Duration(seconds: 7)),
        'GATT 133',
      );
      expect(e.status, equals(ProximityStatus.failed));
      final d2 = _feed(
        e,
        _cfgBoth,
        _ctx(locked: true, on: false),
        t0.add(const Duration(seconds: 8)),
        -49,
        30,
      );
      expect(d2.action, equals(ProximityAction.none));
    });
    test(
      'báo thành công chỉ nói "xe nhận ghi", không nói đã xác nhận khóa',
      () {
        final e = ProximityEngine();
        _feed(e, _cfgBoth, _ctx(locked: true, on: false), t0, -49, 6);
        e.reportResult(
          ProximityAction.unlock,
          true,
          t0.add(const Duration(seconds: 7)),
          'ok',
        );
        expect(e.status, equals(ProximityStatus.success));
        expect(e.message, contains('chưa có xác nhận'));
      },
    );
    test('giới hạn ≤ 3 lệnh / 10 phút rồi khóa tạm', () {
      final e = ProximityEngine();
      var t = t0;
      var sent = 0;
      for (var round = 0; round < 6; round++) {
        // rời xa → armed mở, rồi lại gần
        _feed(e, _cfgBoth, _ctx(locked: true, on: false), t, -92, 5);
        t = t.add(const Duration(seconds: 6));
        final d = _feed(e, _cfgBoth, _ctx(locked: true, on: false), t, -49, 6);
        t = t.add(const Duration(seconds: 7));
        if (d.action == ProximityAction.unlock) {
          sent++;
          e.reportResult(ProximityAction.unlock, true, t, 'ok');
        }
        t = t.add(const Duration(seconds: 25));
      }
      expect(sent, lessThan(4));
    });
  });

  group('Hiệu chỉnh 1 m', () {
    test('mẫu ổn định → ok, lấy trung vị', () {
      final e = ProximityEngine();
      e.startCalibration(t0);
      for (var i = 0; i < 12; i++) {
        e.addSample(
          -52.0 + (i.isEven ? 1 : -1),
          t0.add(Duration(milliseconds: 700 * i)),
        );
      }
      final r = e.pollCalibration(t0.add(const Duration(seconds: 9)));
      expect(r!.ok, isTrue);
      expect(r.rssi1m!, closeTo(-52, 1.5));
    });
    test('quá ít mẫu → thất bại có lời nhắc', () {
      final e = ProximityEngine();
      e.startCalibration(t0);
      e.addSample(-50, t0);
      final r = e.pollCalibration(t0.add(const Duration(seconds: 9)));
      expect(r!.ok, isFalse);
    });
    test('quá nhiễu → từ chối', () {
      final e = ProximityEngine();
      e.startCalibration(t0);
      for (var i = 0; i < 14; i++) {
        e.addSample(
          i.isEven ? -42.0 : -66.0,
          t0.add(Duration(milliseconds: 600 * i)),
        );
      }
      final r = e.pollCalibration(t0.add(const Duration(seconds: 9)));
      expect(r!.ok, isFalse);
    });
    test('quá yếu (<-75 dBm) → từ chối vì không thể là ~1 m', () {
      final e = ProximityEngine();
      e.startCalibration(t0);
      for (var i = 0; i < 12; i++) {
        e.addSample(-82.0, t0.add(Duration(milliseconds: 600 * i)));
      }
      final r = e.pollCalibration(t0.add(const Duration(seconds: 9)));
      expect(r!.ok, isFalse);
    });
    test('chưa đủ thời gian → chưa có kết quả', () {
      final e = ProximityEngine();
      e.startCalibration(t0);
      expect(e.pollCalibration(t0.add(const Duration(seconds: 2))), isNull);
    });
  });
}
