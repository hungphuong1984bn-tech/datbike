// Thống kê chẩn đoán BLE — module THUẦN Dart, chỉ GHI NHẬN, không điều khiển.
//
// BleController gọi các hàm record* tại những điểm đã có sẵn trong luồng kết
// nối. Mọi hàm không bao giờ ném lỗi và không đụng tới logic kết nối.
// Văn bản lỗi do nơi gọi truyền vào phải ĐÃ được lọc bí mật (Redactor.scrubText);
// lớp này không tự ý ghi payload thô.

/// Kết quả đăng ký notification của một characteristic.
enum NotifyOutcome {
  /// Đăng ký thành công.
  subscribed,

  /// Characteristic không hỗ trợ notify (xe dùng poll).
  unsupported,

  /// Đăng ký thất bại.
  failed,
}

extension NotifyOutcomeX on NotifyOutcome {
  String get label {
    switch (this) {
      case NotifyOutcome.subscribed:
        return 'Đã đăng ký notify';
      case NotifyOutcome.unsupported:
        return 'Không hỗ trợ notify (dùng poll)';
      case NotifyOutcome.failed:
        return 'Đăng ký notify thất bại';
    }
  }
}

/// Trạng thái xác thực quan sát được trong phiên chạy này.
enum AuthObserved {
  /// Chưa có lần xác thực nào trong phiên chạy.
  none,

  /// Xe/Ứng dụng chấp nhận phiên.
  accepted,

  /// Xác thực thất bại (xem lý do ở lỗi gần nhất).
  failed,
}

extension AuthObservedX on AuthObserved {
  String get label {
    switch (this) {
      case AuthObserved.none:
        return 'Chưa xác thực trong phiên này';
      case AuthObserved.accepted:
        return 'Phiên đã được chấp nhận';
      case AuthObserved.failed:
        return 'Xác thực thất bại';
    }
  }
}

class NotifyRecord {
  const NotifyRecord(this.outcome, this.at, {this.detail});
  final NotifyOutcome outcome;
  final DateTime at;
  final String? detail;
}

class BleDiagStats {
  BleDiagStats();

  /// Bản dùng chung cho toàn ứng dụng.
  static final BleDiagStats instance = BleDiagStats();

  /// Số khoảng thời gian giữa các gói được giữ để tính trung bình.
  static const int maxIntervals = 50;

  final Map<String, int> _packetsByKind = <String, int>{};
  final List<int> _intervalsMs = <int>[];
  final Map<String, NotifyRecord> _notify = <String, NotifyRecord>{};

  int packetsReceived = 0;
  int packetErrors = 0;
  int connectAttempts = 0;
  int connectFailures = 0;
  int disconnects = 0;
  int unexpectedDisconnects = 0;

  DateTime? connectedAt;
  DateTime? lastPacketAt;
  DateTime? lastErrorAt;
  DateTime? lastDisconnectAt;

  String? lastErrorKind;
  String? lastErrorDetail;
  String? lastFailureStage;
  String? lastFailureKind;
  int? lastFailureCode;

  AuthObserved auth = AuthObserved.none;
  DateTime? authAt;

  Map<String, int> get packetsByKind => Map.unmodifiable(_packetsByKind);
  Map<String, NotifyRecord> get notifyResults => Map.unmodifiable(_notify);

  /// Trung bình khoảng cách giữa các gói gần nhất (ms); null nếu < 2 gói.
  double? get averagePacketIntervalMs {
    if (_intervalsMs.isEmpty) return null;
    var sum = 0;
    for (final v in _intervalsMs) {
      sum += v;
    }
    return sum / _intervalsMs.length;
  }

  /// Tỷ lệ lỗi giải mã trên tổng số gói đã thử giải mã (null khi chưa có gì).
  double? get errorRate {
    final total = packetsReceived + packetErrors;
    if (total == 0) return null;
    return packetErrors / total;
  }

  void recordConnectAttempt() {
    connectAttempts++;
  }

  void recordConnected([DateTime? at]) {
    connectedAt = at ?? DateTime.now();
    // Khoảng cách giữa gói của lần kết nối trước và gói đầu của lần này không có ý nghĩa.
    _intervalsMs.clear();
    lastPacketAt = null;
  }

  void recordConnectFailure({String? stage, String? kind, int? code, DateTime? at}) {
    connectFailures++;
    lastFailureStage = stage;
    lastFailureKind = kind;
    lastFailureCode = code;
    lastErrorAt = at ?? DateTime.now();
    lastErrorKind = kind ?? 'connect_failed';
  }

  /// Ghi nhận một gói đã giải mã thành công. [kind] ví dụ 'dashboard', 'battery'.
  void recordPacket(String kind, [DateTime? at]) {
    final t = at ?? DateTime.now();
    packetsReceived++;
    _packetsByKind[kind] = (_packetsByKind[kind] ?? 0) + 1;
    final prev = lastPacketAt;
    if (prev != null) {
      final ms = t.difference(prev).inMilliseconds;
      if (ms >= 0) {
        _intervalsMs.add(ms);
        if (_intervalsMs.length > maxIntervals) _intervalsMs.removeAt(0);
      }
    }
    lastPacketAt = t;
  }

  /// Ghi nhận một lỗi giải mã/đọc gói. [detail] phải đã được lọc bí mật.
  void recordPacketError(String kind, {String? detail, DateTime? at}) {
    packetErrors++;
    lastErrorAt = at ?? DateTime.now();
    lastErrorKind = kind;
    lastErrorDetail = detail;
  }

  void recordNotify(String uuid, NotifyOutcome outcome,
      {String? detail, DateTime? at}) {
    _notify[uuid.toLowerCase()] =
        NotifyRecord(outcome, at ?? DateTime.now(), detail: detail);
  }

  void recordAuth(AuthObserved result, [DateTime? at]) {
    auth = result;
    authAt = at ?? DateTime.now();
  }

  void recordDisconnect({required bool manual, DateTime? at}) {
    disconnects++;
    if (!manual) unexpectedDisconnects++;
    lastDisconnectAt = at ?? DateTime.now();
    connectedAt = null;
    // Sau khi ngắt, trạng thái xác thực của kết nối cũ không còn hiệu lực.
    auth = AuthObserved.none;
    authAt = null;
  }

  void reset() {
    _packetsByKind.clear();
    _intervalsMs.clear();
    _notify.clear();
    packetsReceived = 0;
    packetErrors = 0;
    connectAttempts = 0;
    connectFailures = 0;
    disconnects = 0;
    unexpectedDisconnects = 0;
    connectedAt = null;
    lastPacketAt = null;
    lastErrorAt = null;
    lastDisconnectAt = null;
    lastErrorKind = null;
    lastErrorDetail = null;
    lastFailureStage = null;
    lastFailureKind = null;
    lastFailureCode = null;
    auth = AuthObserved.none;
    authAt = null;
  }

  Map<String, Object?> toJson() => {
        'packetsReceived': packetsReceived,
        'packetsByKind': packetsByKind,
        'packetErrors': packetErrors,
        'avgPacketIntervalMs': averagePacketIntervalMs,
        'connectAttempts': connectAttempts,
        'connectFailures': connectFailures,
        'disconnects': disconnects,
        'unexpectedDisconnects': unexpectedDisconnects,
        'connectedAt': connectedAt?.toIso8601String(),
        'lastPacketAt': lastPacketAt?.toIso8601String(),
        'lastErrorAt': lastErrorAt?.toIso8601String(),
        'lastDisconnectAt': lastDisconnectAt?.toIso8601String(),
        'lastErrorKind': lastErrorKind,
        'lastFailure': {
          'stage': lastFailureStage,
          'kind': lastFailureKind,
          'code': lastFailureCode,
        },
        'auth': auth.name,
        'authAt': authAt?.toIso8601String(),
        'notify': {
          for (final e in _notify.entries)
            e.key: {
              'outcome': e.value.outcome.name,
              'at': e.value.at.toIso8601String(),
            },
        },
      };
}
