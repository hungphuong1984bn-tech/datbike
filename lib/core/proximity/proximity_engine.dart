// ProximityEngine — bộ quyết định Smart Unlock / Auto Lock theo RSSI.
//
// THUẦN DART (không phụ thuộc Flutter/BLE) để kiểm thử được. Engine KHÔNG gửi
// lệnh; nó chỉ trả về [ProximityDecision]. BleController là nơi duy nhất thực
// thi lệnh (qua các hàm đã có: unlockBike / _runAutoSecureSequence).
//
// GIỚI HẠN VẬT LÝ (đọc trước khi chỉnh số):
//   RSSI KHÔNG phải khoảng cách. Cùng một vị trí, RSSI dao động vài dB theo
//   hướng cầm máy, túi quần, người che, phản xạ. Vì vậy "1 m" ở đây nghĩa là
//   "mức RSSI người dùng đo được khi đứng cách xe ~1 m" (hiệu chỉnh), cộng/trừ
//   biên độ theo độ nhạy. Không có bảo đảm chính xác tuyệt đối 1 m.
//
// BẢO VỆ:
//   • Lọc: cửa sổ trung vị + loại outlier + Kalman 1D.
//   • Hysteresis: ngưỡng vào/ra khác nhau (chống dao động quanh ngưỡng).
//   • Dwell: phải ở trong vùng liên tục đủ lâu và đủ số mẫu.
//   • Armed: mở khóa chỉ sau khi đã rời xa; khóa chỉ sau khi đã từng ở gần.
//   • Giới hạn tần suất + khóa tạm khi lặp lệnh quá nhiều.
//   • Mất mẫu (stale) / mất kết nối KHÔNG phải bằng chứng rời xe: không quyết
//     định gì khi không có mẫu mới.

import '../utils/kalman_filter.dart';

enum ProximityZone { unknown, near, middle, far }

enum ProximityAction { none, unlock, lock }

/// Trạng thái hiển thị cho người dùng.
enum ProximityStatus {
  off, // cả hai tính năng đang tắt
  searching, // chưa có tín hiệu hợp lệ từ xe
  idle, // đang theo dõi, chưa có gì để làm
  detected, // đã phát hiện vào/ra vùng, đang chờ xác nhận (dwell)
  verifying, // chờ điều kiện xác thực/an toàn
  running, // đang gửi lệnh
  success, // lệnh đã được xe nhận ghi (CHƯA phải xác nhận trạng thái khóa)
  failed, // lệnh thất bại
  blocked, // bị chặn bởi điều kiện an toàn / giới hạn tần suất
}

class ProximityEvent {
  final DateTime at;
  final String kind;
  final String detail;
  const ProximityEvent(this.at, this.kind, this.detail);
  @override
  String toString() => '${at.toIso8601String()} $kind $detail';
}

/// Cấu hình (tách khỏi trạng thái để dễ test).
class ProximityConfig {
  final bool unlockEnabled;
  final bool lockEnabled;

  /// 0 = Thấp (khó kích hoạt, ít nhầm), 1 = Vừa, 2 = Cao (dễ kích hoạt).
  final int sensitivity;

  /// RSSI trung vị đo khi đứng cách xe ~1 m (null = chưa hiệu chỉnh).
  final double? calibratedRssi1m;

  /// Ngưỡng cũ (dBm) dùng khi CHƯA hiệu chỉnh — giữ tương thích bản trước.
  final double legacyNearThreshold;
  final double legacyFarThreshold;

  /// Thời gian phải liên tục ở ngoài vùng trước khi khóa (giây).
  final int lockConfirmSeconds;

  const ProximityConfig({
    this.unlockEnabled = false,
    this.lockEnabled = false,
    this.sensitivity = 1,
    this.calibratedRssi1m,
    this.legacyNearThreshold = -55.0,
    this.legacyFarThreshold = -83.0,
    this.lockConfirmSeconds = 5,
  });

  bool get calibrated => calibratedRssi1m != null;
}

/// Điều kiện hiện tại của xe/kết nối do BleController cung cấp.
class ProximityContext {
  final bool connected;
  final bool authorized; // đã xác thực phiên với ĐÚNG xe đã ghép đôi
  final bool telemetryFresh;
  final double? speedKmh; // null = chưa biết (KHÔNG coi là 0)
  final bool bikeOn;
  final bool bikeLocked; // trạng thái khóa theo app (không có đọc lại từ xe)
  final bool bikeInDriveGear; // drive/super/cruise/reverse/turtle
  final bool autoPowerOn; // tùy chọn: mở khóa xong thì bật xe
  final bool commandBusy;
  final bool userRecentlyActed; // vừa có thao tác tay (<10 s)
  final bool labMode;

  const ProximityContext({
    required this.connected,
    required this.authorized,
    required this.telemetryFresh,
    required this.speedKmh,
    required this.bikeOn,
    required this.bikeLocked,
    required this.bikeInDriveGear,
    this.autoPowerOn = false,
    this.commandBusy = false,
    this.userRecentlyActed = false,
    this.labMode = false,
  });
}

class ProximityDecision {
  final ProximityAction action;
  final String reason;
  const ProximityDecision(this.action, this.reason);
  static const none = ProximityDecision(ProximityAction.none, '');
}

class CalibrationResult {
  final bool ok;
  final double? rssi1m;
  final int samples;
  final double stdDev;
  final String message;
  const CalibrationResult({
    required this.ok,
    required this.rssi1m,
    required this.samples,
    required this.stdDev,
    required this.message,
  });
}

class ProximityEngine {
  // ---- Tham số lọc ----
  static const int _window = 7;
  static const double _outlierDb = 15.0;
  static const int _maxConsecutiveOutliers = 3;
  static const Duration sampleStale = Duration(seconds: 3);

  // ---- Tham số quyết định ----
  static const Duration nearDwell = Duration(milliseconds: 1500);
  static const int nearMinSamples = 2;
  static const int farMinSamples = 4;
  static const double hysteresisDb = 2.0;
  static const double minGapDb = 4.0; // khoảng cách tối thiểu ngưỡng gần–xa
  static const Duration minActionInterval = Duration(seconds: 20);
  static const int maxActionsPerWindow = 3;
  static const Duration actionWindow = Duration(minutes: 10);
  static const Duration failureBackoff = Duration(seconds: 60);
  static const Duration verifyTimeout = Duration(seconds: 10);

  // Biên độ theo độ nhạy [thấp, vừa, cao] — dB so với RSSI@1m.
  static const List<double> unlockMarginDb = [1.0, 3.0, 5.0];
  static const List<double> lockDropDb = [11.0, 9.0, 7.0];

  final List<ProximityEvent> _events = [];
  static const int _maxEvents = 60;

  final List<double> _win = [];
  final KalmanFilter1D _kalman = KalmanFilter1D(
    processNoise: 0.02,
    measurementNoise: 3.0,
  );
  int _consecutiveOutliers = 0;
  DateTime? _lastSampleAt;
  double? _raw;
  double? _filtered;
  int _samplesInZone = 0;

  ProximityZone _zone = ProximityZone.unknown;
  DateTime? _zoneSince;

  bool _unlockArmed =
      true; // sau khi mở khóa/ khóa tay → phải rời xa mới armed lại
  bool _lockArmed = false; // phải từng ở gần (sau lần khóa gần nhất) mới armed

  DateTime? _lastActionAt;
  final List<DateTime> _actionTimes = [];
  DateTime? _backoffUntil;
  DateTime? _blockedUntil;
  DateTime? _verifySince;

  ProximityStatus _status = ProximityStatus.off;
  String _message = '';
  ProximityAction _activeAction = ProximityAction.none;

  // ---- Hiệu chỉnh ----
  bool _calibrating = false;
  DateTime? _calStart;
  final List<double> _calSamples = [];
  static const Duration calibrationDuration = Duration(seconds: 8);
  static const int calibrationMinSamples = 6;

  // ================= Truy cập trạng thái =================
  ProximityZone get zone => _zone;
  double? get filteredRssi => _filtered;
  double? get rawRssi => _raw;
  ProximityStatus get status => _status;
  String get message => _message;
  ProximityAction get activeAction => _activeAction;
  bool get calibrating => _calibrating;
  bool get unlockArmed => _unlockArmed;
  bool get lockArmed => _lockArmed;
  List<ProximityEvent> get events => List.unmodifiable(_events);

  void _log(DateTime now, String kind, String detail) {
    _events.add(ProximityEvent(now, kind, detail));
    if (_events.length > _maxEvents) _events.removeAt(0);
  }

  // ================= Ngưỡng =================
  /// Ngưỡng "gần" (dBm): RSSI >= giá trị này nghĩa là trong vùng mở khóa.
  double unlockThreshold(ProximityConfig c) {
    final s = c.sensitivity.clamp(0, 2);
    if (c.calibratedRssi1m == null) return c.legacyNearThreshold;
    return c.calibratedRssi1m! - unlockMarginDb[s];
  }

  /// Ngưỡng "xa" (dBm): RSSI <= giá trị này nghĩa là đã rời xa (vùng khóa).
  double lockThreshold(ProximityConfig c) {
    final s = c.sensitivity.clamp(0, 2);
    final near = unlockThreshold(c);
    final raw = c.calibratedRssi1m == null
        ? c.legacyFarThreshold
        : c.calibratedRssi1m! - lockDropDb[s];
    // Luôn giữ khoảng hysteresis giữa hai ngưỡng.
    return raw > near - minGapDb ? near - minGapDb : raw;
  }

  // ================= Nạp mẫu =================
  /// Nạp một mẫu RSSI thô (dBm). Trả về RSSI đã lọc.
  double addSample(double rssi, DateTime now) {
    _raw = rssi;
    _lastSampleAt = now;
    if (_calibrating) _calSamples.add(rssi);

    // Loại outlier: lệch quá xa trung vị cửa sổ (chỉ khi đã đủ mẫu).
    if (_win.length >= 5) {
      final med = _median(_win);
      if ((rssi - med).abs() > _outlierDb) {
        if (_consecutiveOutliers < _maxConsecutiveOutliers) {
          _consecutiveOutliers++;
          return _filtered ?? rssi;
        }
        // Lệch liên tiếp ≥ 3 mẫu: không còn là nhiễu mà là dịch chuyển thật
        // (người dùng đi xa/lại gần) → bỏ lịch sử cũ, bám mức mới.
        _win.clear();
        _kalman.reset();
      }
    }
    _consecutiveOutliers = 0;
    _win.add(rssi);
    if (_win.length > _window) _win.removeAt(0);
    _filtered = _kalman.filter(_median(_win));
    return _filtered!;
  }

  /// Gọi khi mất kết nối / đổi xe: xóa bộ lọc, KHÔNG suy diễn là đã rời xe.
  void resetLink(DateTime now, {String why = 'mất kết nối'}) {
    _win.clear();
    _kalman.reset();
    _filtered = null;
    _raw = null;
    _lastSampleAt = null;
    _zone = ProximityZone.unknown;
    _zoneSince = null;
    _samplesInZone = 0;
    _lockArmed = false; // chưa thấy gần trong phiên mới
    _verifySince = null;
    _activeAction = ProximityAction.none;
    _status = ProximityStatus.searching;
    _message = 'Đang tìm xe ($why).';
    _log(now, 'reset', why);
  }

  /// Người dùng tự thao tác tay.
  void noteUserCommand(DateTime now, {required bool locked}) {
    if (locked) {
      // Vừa khóa tay → không được tự mở lại ngay khi đang đứng cạnh xe.
      _unlockArmed = false;
      _log(now, 'user_lock', 'khóa tay → chờ rời xa mới tự mở lại');
    }
    _lockArmed = false;
  }

  // ================= Vùng với hysteresis =================
  ProximityZone _classify(ProximityConfig c, double f) {
    final nearT = unlockThreshold(c);
    final farT = lockThreshold(c);
    switch (_zone) {
      case ProximityZone.near:
        if (f >= nearT - hysteresisDb) return ProximityZone.near;
        break;
      case ProximityZone.far:
        if (f <= farT + hysteresisDb) return ProximityZone.far;
        break;
      default:
        break;
    }
    if (f >= nearT) return ProximityZone.near;
    if (f <= farT) return ProximityZone.far;
    return ProximityZone.middle;
  }

  // ================= Quyết định =================
  ProximityDecision evaluate(
    ProximityConfig c,
    ProximityContext ctx,
    DateTime now,
  ) {
    if (!c.unlockEnabled && !c.lockEnabled) {
      _status = ProximityStatus.off;
      _message = 'Mở khóa thông minh và Tự động khóa đang tắt.';
      return ProximityDecision.none;
    }
    if (_activeAction != ProximityAction.none) {
      return ProximityDecision.none; // đang chạy một lệnh
    }
    if (!ctx.connected || _filtered == null || _lastSampleAt == null) {
      _status = ProximityStatus.searching;
      _message = 'Đang tìm xe…';
      return ProximityDecision.none;
    }
    if (now.difference(_lastSampleAt!) > sampleStale) {
      // Mất mẫu ≠ rời xa. Không quyết định gì.
      _status = ProximityStatus.searching;
      _message = 'Tín hiệu cũ — chờ mẫu mới (không coi là rời xe).';
      return ProximityDecision.none;
    }
    if (ctx.labMode) {
      _status = ProximityStatus.blocked;
      _message = 'Đang ở Firmware Lab — tự động tạm dừng.';
      return ProximityDecision.none;
    }
    if (_calibrating) {
      _status = ProximityStatus.idle;
      _message = 'Đang hiệu chỉnh — tự động tạm dừng.';
      return ProximityDecision.none;
    }

    // Cập nhật vùng.
    final z = _classify(c, _filtered!);
    if (z != _zone) {
      _zone = z;
      _zoneSince = now;
      _samplesInZone = 1;
      _log(now, 'zone', '${z.name} @${_filtered!.toStringAsFixed(1)} dBm');
    } else {
      _samplesInZone++;
    }
    final inZone = now.difference(_zoneSince ?? now);

    // Armed: thấy xa → armed mở khóa; thấy gần → armed khóa.
    if (_zone == ProximityZone.far &&
        inZone >= nearDwell &&
        _samplesInZone >= nearMinSamples) {
      if (!_unlockArmed) _log(now, 'armed_unlock', 'đã rời xa');
      _unlockArmed = true;
    }
    if (_zone == ProximityZone.near &&
        inZone >= nearDwell &&
        _samplesInZone >= nearMinSamples) {
      if (!_lockArmed) _log(now, 'armed_lock', 'đã ở gần');
      _lockArmed = true;
    }

    // Khóa tạm do lặp lệnh / thất bại.
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      _status = ProximityStatus.blocked;
      _message =
          'Tạm khóa tự động vì lặp lệnh quá nhiều '
          '(còn ${_blockedUntil!.difference(now).inSeconds} s).';
      return ProximityDecision.none;
    }
    if (_backoffUntil != null && now.isBefore(_backoffUntil!)) {
      _status = ProximityStatus.failed;
      _message =
          'Lệnh trước thất bại — thử lại sau '
          '${_backoffUntil!.difference(now).inSeconds} s.';
      return ProximityDecision.none;
    }

    // ----- MỞ KHÓA -----
    if (c.unlockEnabled && _zone == ProximityZone.near) {
      final needs = ctx.bikeLocked || (ctx.autoPowerOn && !ctx.bikeOn);
      if (needs) {
        if (inZone < nearDwell || _samplesInZone < nearMinSamples) {
          _status = ProximityStatus.detected;
          _message = 'Phát hiện xe ở gần — đang xác nhận…';
          return ProximityDecision.none;
        }
        if (!_unlockArmed) {
          _status = ProximityStatus.idle;
          _message =
              'Đã ở gần nhưng chưa rời xa sau lần khóa/mở trước — '
              'không tự mở lại.';
          return ProximityDecision.none;
        }
        final why = _gateCommon(ctx, now);
        if (why != null) return _verifyOrBlock(why, now);
        final rate = _rateGate(now);
        if (rate != null) return _blockRate(rate, now);
        _verifySince = null;
        return _begin(
          ProximityAction.unlock,
          'RSSI ${_filtered!.toStringAsFixed(1)} ≥ ${unlockThreshold(c).toStringAsFixed(1)} dBm',
          now,
        );
      }
    }

    // ----- KHÓA -----
    if (c.lockEnabled && _zone == ProximityZone.far) {
      final needs = ctx.bikeOn && !ctx.bikeLocked;
      if (needs) {
        if (!_lockArmed) {
          _status = ProximityStatus.idle;
          _message = 'Chưa thấy bạn ở gần xe trong phiên này — không tự khóa.';
          return ProximityDecision.none;
        }
        final need = Duration(seconds: c.lockConfirmSeconds.clamp(3, 15));
        if (inZone < need || _samplesInZone < farMinSamples) {
          _status = ProximityStatus.detected;
          _message =
              'Phát hiện đang rời xe — xác nhận '
              '${inZone.inSeconds}/${need.inSeconds} s…';
          return ProximityDecision.none;
        }
        final why = _gateCommon(ctx, now) ?? _gateLock(ctx);
        if (why != null) return _verifyOrBlock(why, now);
        final rate = _rateGate(now);
        if (rate != null) return _blockRate(rate, now);
        _verifySince = null;
        return _begin(
          ProximityAction.lock,
          'RSSI ${_filtered!.toStringAsFixed(1)} ≤ ${lockThreshold(c).toStringAsFixed(1)} dBm '
          'liên tục ${inZone.inSeconds} s',
          now,
        );
      }
    }

    _verifySince = null;
    _status = ProximityStatus.idle;
    _message = switch (_zone) {
      ProximityZone.near => 'Ở gần xe.',
      ProximityZone.far => 'Đã rời xa xe.',
      ProximityZone.middle => 'Vùng trung gian — chưa kích hoạt gì.',
      ProximityZone.unknown => 'Đang tìm xe…',
    };
    return ProximityDecision.none;
  }

  String? _gateCommon(ProximityContext ctx, DateTime now) {
    if (!ctx.authorized) return 'Chưa xác thực phiên với xe.';
    if (ctx.commandBusy) return 'Xe đang bận xử lý lệnh khác.';
    if (ctx.userRecentlyActed)
      return 'Bạn vừa thao tác tay — tạm dừng tự động.';
    return null;
  }

  String? _gateLock(ProximityContext ctx) {
    if (!ctx.telemetryFresh || ctx.speedKmh == null) {
      return 'Chưa có dữ liệu tốc độ mới (<4 s) nên không xác nhận được xe đứng yên.';
    }
    if (ctx.speedKmh! > 0.5) {
      return 'Xe đang chạy (${ctx.speedKmh!.toStringAsFixed(1)} km/h) — không khóa.';
    }
    if (ctx.bikeInDriveGear) {
      return 'Xe đang ở số lái — chỉ tự khóa khi ở P/STANDBY.';
    }
    return null;
  }

  String? _rateGate(DateTime now) {
    if (_lastActionAt != null &&
        now.difference(_lastActionAt!) < minActionInterval) {
      return 'Vừa gửi lệnh tự động <${minActionInterval.inSeconds} s trước.';
    }
    _actionTimes.removeWhere((t) => now.difference(t) > actionWindow);
    if (_actionTimes.length >= maxActionsPerWindow) {
      _blockedUntil = now.add(actionWindow);
      _log(
        now,
        'rate_block',
        'quá $maxActionsPerWindow lệnh/${actionWindow.inMinutes} phút',
      );
      return 'Quá nhiều lệnh tự động trong ${actionWindow.inMinutes} phút.';
    }
    return null;
  }

  ProximityDecision _blockRate(String why, DateTime now) {
    _status = ProximityStatus.blocked;
    _message = why;
    return ProximityDecision.none;
  }

  /// Điều kiện chưa đạt: nếu chỉ là chờ xác thực/bận thì "verifying" tới hết
  /// timeout, sau đó "blocked". Không bao giờ ép lệnh.
  ProximityDecision _verifyOrBlock(String why, DateTime now) {
    _verifySince ??= now;
    final waited = now.difference(_verifySince!);
    if (waited > verifyTimeout) {
      _status = ProximityStatus.blocked;
      _message = 'Không thực hiện: $why';
    } else {
      _status = ProximityStatus.verifying;
      _message = 'Chờ điều kiện: $why';
    }
    return ProximityDecision.none;
  }

  ProximityDecision _begin(ProximityAction a, String why, DateTime now) {
    _activeAction = a;
    _status = ProximityStatus.running;
    _message = a == ProximityAction.unlock
        ? 'Đang mở khóa…'
        : 'Đang tắt xe và khóa…';
    _lastActionAt = now;
    _actionTimes.add(now);
    _log(now, a.name, why);
    return ProximityDecision(a, why);
  }

  /// BleController báo kết quả sau khi thực thi lệnh.
  /// [ok] = lệnh ghi được xe nhận. KHÔNG có nghĩa là xe đã xác nhận trạng thái
  /// khóa (giao thức không có đọc lại trạng thái khóa).
  void reportResult(ProximityAction a, bool ok, DateTime now, String detail) {
    _activeAction = ProximityAction.none;
    if (ok) {
      _status = ProximityStatus.success;
      _message = a == ProximityAction.unlock
          ? 'Đã gửi lệnh mở khóa — xe nhận ghi (chưa có xác nhận trạng thái khóa).'
          : 'Đã gửi lệnh tắt xe + khóa — xe nhận ghi (chưa có xác nhận trạng thái khóa).';
      if (a == ProximityAction.unlock) _unlockArmed = false;
      if (a == ProximityAction.lock) {
        _lockArmed = false;
        _unlockArmed = false; // phải rời xa/ quay lại rõ ràng mới mở
      }
      _log(now, '${a.name}_ok', detail);
    } else {
      _status = ProximityStatus.failed;
      _message = 'Thất bại: $detail';
      _backoffUntil = now.add(failureBackoff);
      _log(now, '${a.name}_fail', detail);
    }
  }

  // ================= Hiệu chỉnh 1 m =================
  void startCalibration(DateTime now) {
    _calibrating = true;
    _calStart = now;
    _calSamples.clear();
    _log(now, 'calibrate_start', '');
  }

  void cancelCalibration() {
    _calibrating = false;
    _calSamples.clear();
  }

  double? calibrationProgress(DateTime now) {
    if (!_calibrating || _calStart == null) return null;
    final p =
        now.difference(_calStart!).inMilliseconds /
        calibrationDuration.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }

  /// Gọi định kỳ; trả về kết quả khi đủ thời gian, ngược lại null.
  CalibrationResult? pollCalibration(DateTime now) {
    if (!_calibrating || _calStart == null) return null;
    if (now.difference(_calStart!) < calibrationDuration) return null;
    _calibrating = false;
    final s = List<double>.from(_calSamples)..sort();
    _calSamples.clear();
    if (s.length < calibrationMinSamples) {
      return CalibrationResult(
        ok: false,
        rssi1m: null,
        samples: s.length,
        stdDev: 0,
        message:
            'Chỉ thu được ${s.length} mẫu (cần ≥ $calibrationMinSamples). '
            'Kiểm tra kết nối rồi thử lại.',
      );
    }
    final cut = (s.length * 0.1).floor();
    final t = s.sublist(cut, s.length - cut);
    final med = _median(t);
    final mean = t.reduce((a, b) => a + b) / t.length;
    var v = 0.0;
    for (final x in t) {
      v += (x - mean) * (x - mean);
    }
    final sd = t.length > 1 ? _sqrt(v / (t.length - 1)) : 0.0;
    if (sd > 6.0) {
      return CalibrationResult(
        ok: false,
        rssi1m: null,
        samples: s.length,
        stdDev: sd,
        message:
            'Tín hiệu quá nhiễu (độ lệch ${sd.toStringAsFixed(1)} dB). '
            'Đứng yên, cầm máy như khi đi bộ rồi thử lại.',
      );
    }
    if (med < -75) {
      return CalibrationResult(
        ok: false,
        rssi1m: null,
        samples: s.length,
        stdDev: sd,
        message:
            'Tín hiệu quá yếu (${med.toStringAsFixed(0)} dBm) để là ~1 m. '
            'Đứng sát xe hơn rồi thử lại.',
      );
    }
    _log(
      now,
      'calibrate_ok',
      '${med.toStringAsFixed(1)} dBm, n=${s.length}, sd=${sd.toStringAsFixed(1)}',
    );
    return CalibrationResult(
      ok: true,
      rssi1m: med,
      samples: s.length,
      stdDev: sd,
      message:
          'Đã hiệu chỉnh: ${med.toStringAsFixed(1)} dBm tại ~1 m '
          '(${s.length} mẫu, độ lệch ${sd.toStringAsFixed(1)} dB).',
    );
  }

  // ================= Tiện ích =================
  static double _median(List<double> v) {
    final s = List<double>.from(v)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var g = x / 2;
    for (var i = 0; i < 30; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }
}
