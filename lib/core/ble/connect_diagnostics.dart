// Chẩn đoán kết nối BLE — module THUẦN Dart (không import Flutter) để test được.
//
// Mục tiêu:
//   1. Mỗi bước của luồng kết nối có tên (ConnectStage) và kết quả + timestamp.
//   2. Mỗi kiểu thất bại có loại riêng (ConnectFailureKind) — KHÔNG gộp thành
//      "connect_failed" chung chung.
//   3. Mọi dữ liệu nhạy cảm (token, password, PIN, session key, response xác
//      thực, nonce thô) bị loại/che trước khi vào log hoặc báo cáo.
//   4. Báo cáo chẩn đoán nêu rõ: bước cuối cùng thành công, bước đầu tiên
//      thất bại.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Các bước của luồng kết nối, theo thứ tự thực hiện.
enum ConnectStage {
  permissions,
  adapter,
  scan,
  selectDevice,
  gattConnect,
  mtu,
  bonding,
  discoverServices,
  readFirmware,
  authChallenge, // đọc 5e9a2c71 (nonce 15B + status 1B)
  appAuth, // challenge-response SHA-256 trên c8eaf27b
  authResponse, // ghi HMAC 16B lên 5e9a2c71 + đọc lại status
  sessionKey, // derive + kiểm tra khóa phiên (ghi time-sync, đọc dashboard)
  sessionRegister, // ghi token lên 87efab0d
  notifications,
  telemetry,
}

/// Loại thất bại — mỗi loại tương ứng một điểm hỏng khác nhau.
enum ConnectFailureKind {
  permissionDenied,
  permissionPermanentlyDenied,
  adapterOff,
  busy, // đang có handshake khác chạy
  storageCorrupt,
  gattConnectFailed,
  gattConnectTimeout,
  linkLostDuringSetup,
  mtuFailed, // chỉ cảnh báo, không chặn kết nối
  serviceDiscoveryFailed,
  requiredServiceMissing,
  bondingFailed,
  bondingRejected,
  encryptionRequired, // ATT 0x05/0x0F/137 chưa xử lý được
  bondMismatchSuspected, // có bằng chứng bond lệch (xem BondEvidence)
  authChallengeUnavailable,
  authRejected, // status 0x00 sau khi ghi response
  appAuthFailed,
  sessionKeyInvalid, // handshake OK nhưng telemetry không giải mã được
  telemetryInvalid,
  operationTimeout,
  unknown,
}

/// Lỗi có kiểu, mang theo bước và mã lỗi gốc.
class ConnectFailure implements Exception {
  ConnectFailure(
    this.stage,
    this.kind,
    this.detail, {
    this.code,
    this.timeout,
    this.messageOverride,
  });

  final ConnectStage stage;
  final ConnectFailureKind kind;

  /// Mô tả KỸ THUẬT, đã được lọc dữ liệu nhạy cảm.
  final String detail;

  /// Mã lỗi GATT/ATT/HCI gốc nếu có (133, 137, 5, 15, 8, 19, 22, 34…).
  final int? code;

  /// Thời gian timeout đã áp dụng khi kind là *Timeout.
  final Duration? timeout;

  /// Thông điệp riêng (nếu có) thay cho thông điệp mặc định theo [kind].
  final String? messageOverride;

  /// Thông điệp cho người dùng (tiếng Việt), nói rõ hỏng ở bước nào.
  String get userMessage {
    final o = messageOverride;
    if (o != null && o.isNotEmpty) return o;
    final where = stageLabel(stage);
    switch (kind) {
      case ConnectFailureKind.permissionDenied:
        return 'Thiếu quyền Bluetooth. Hãy cấp quyền "Thiết bị ở gần" '
            '(Android 12+) hoặc "Vị trí" (Android 11 trở xuống) rồi thử lại.';
      case ConnectFailureKind.permissionPermanentlyDenied:
        return 'Quyền Bluetooth đã bị từ chối vĩnh viễn. Mở Cài đặt > Ứng '
            'dụng > THBIKE > Quyền để bật lại.';
      case ConnectFailureKind.adapterOff:
        return 'Bluetooth của điện thoại đang tắt. Hãy bật Bluetooth.';
      case ConnectFailureKind.busy:
        return 'Đang có một lần kết nối khác chạy. Đợi nó kết thúc rồi thử lại.';
      case ConnectFailureKind.storageCorrupt:
        return 'Dữ liệu ghép nối đã lưu trên máy bị hỏng. Chọn "Quên xe" rồi '
            'ghép nối lại (cần quẹt thẻ NFC vào xe).';
      case ConnectFailureKind.gattConnectFailed:
      case ConnectFailureKind.gattConnectTimeout:
        return 'Không mở được kết nối GATT tới xe (bước: $where'
            '${code != null ? ', mã $code' : ''}). Lại gần xe, bật khóa điện, '
            'và đảm bảo không có điện thoại/app Dat Bike khác đang giữ kết nối.';
      case ConnectFailureKind.linkLostDuringSetup:
        return 'Xe ngắt kết nối giữa chừng ở bước: $where'
            '${code != null ? ' (mã $code)' : ''}.';
      case ConnectFailureKind.mtuFailed:
        return 'Không thương lượng được MTU (không chặn kết nối).';
      case ConnectFailureKind.serviceDiscoveryFailed:
        return 'Không đọc được danh sách dịch vụ GATT của xe '
            '(bước: $where${code != null ? ', mã $code' : ''}).';
      case ConnectFailureKind.requiredServiceMissing:
        return 'Xe không có dịch vụ/characteristic bắt buộc: $detail. '
            'Có thể không phải đúng xe Dat Bike hoặc cache GATT cũ.';
      case ConnectFailureKind.bondingFailed:
        return 'Ghép nối Bluetooth (bonding) với xe không hoàn tất.';
      case ConnectFailureKind.bondingRejected:
        return 'Ghép nối Bluetooth bị từ chối/hủy. Hãy chấp nhận hộp thoại '
            'ghép nối khi nó hiện ra.';
      case ConnectFailureKind.encryptionRequired:
        return 'Xe yêu cầu liên kết được mã hóa nhưng chưa thiết lập được '
            '(bước: $where${code != null ? ', mã $code' : ''}).';
      case ConnectFailureKind.bondMismatchSuspected:
        return 'Có dấu hiệu khóa ghép nối (bond) giữa điện thoại và xe bị '
            'lệch. App KHÔNG tự xóa bond. Nếu muốn khôi phục: vào Cài đặt '
            'Bluetooth của điện thoại, "Bỏ qua/Quên" thiết bị xe, hoặc chọn '
            '"Quên xe" trong app, rồi ghép lại.';
      case ConnectFailureKind.authChallengeUnavailable:
        return 'Không đọc được challenge xác thực từ xe (bước: $where).';
      case ConnectFailureKind.authRejected:
        return 'Xe từ chối xác thực (status 0x00). Nếu đổi điện thoại hoặc '
            'xe vừa khởi động lại, hãy quẹt thẻ NFC vào xe.';
      case ConnectFailureKind.appAuthFailed:
        return 'Bước xác thực ứng dụng (c8eaf27b) thất bại: $detail';
      case ConnectFailureKind.sessionKeyInvalid:
        return 'Xác thực xe thành công nhưng khóa phiên không giải mã được '
            'dữ liệu. Có thể password đã lưu không còn khớp với xe.';
      case ConnectFailureKind.telemetryInvalid:
        return 'Không đọc được dữ liệu telemetry hợp lệ từ xe.';
      case ConnectFailureKind.operationTimeout:
        return 'Quá thời gian chờ ở bước: $where'
            '${timeout != null ? ' (${timeout!.inMilliseconds} ms)' : ''}.';
      case ConnectFailureKind.unknown:
        return 'Lỗi không xác định ở bước: $where. Chi tiết: $detail';
    }
  }

  @override
  String toString() =>
      'ConnectFailure(stage: ${stage.name}, kind: ${kind.name}'
      '${code != null ? ', code: $code' : ''}'
      '${timeout != null ? ', timeoutMs: ${timeout!.inMilliseconds}' : ''}'
      ', detail: $detail)';
}

String stageLabel(ConnectStage s) {
  switch (s) {
    case ConnectStage.permissions:
      return 'xin quyền';
    case ConnectStage.adapter:
      return 'bật Bluetooth';
    case ConnectStage.scan:
      return 'quét thiết bị';
    case ConnectStage.selectDevice:
      return 'chọn thiết bị';
    case ConnectStage.gattConnect:
      return 'kết nối GATT';
    case ConnectStage.mtu:
      return 'thương lượng MTU';
    case ConnectStage.bonding:
      return 'ghép nối/mã hóa (bonding)';
    case ConnectStage.discoverServices:
      return 'khám phá dịch vụ';
    case ConnectStage.readFirmware:
      return 'đọc phiên bản firmware';
    case ConnectStage.authChallenge:
      return 'đọc challenge/nonce';
    case ConnectStage.appAuth:
      return 'xác thực ứng dụng (c8eaf27b)';
    case ConnectStage.authResponse:
      return 'ghi phản hồi xác thực';
    case ConnectStage.sessionKey:
      return 'tạo/kiểm tra khóa phiên';
    case ConnectStage.sessionRegister:
      return 'đăng ký phiên (87efab0d)';
    case ConnectStage.notifications:
      return 'đăng ký notification';
    case ConnectStage.telemetry:
      return 'đọc telemetry';
  }
}

// ---------------------------------------------------------------------------
// Phân loại lỗi GATT/ATT/HCI
// ---------------------------------------------------------------------------

/// Mô tả mã lỗi Android BluetoothGatt / ATT / HCI hay gặp.
String describeGattCode(int code) {
  switch (code) {
    case 0:
      return 'GATT_SUCCESS';
    case 5:
      return 'ATT insufficient authentication';
    case 8:
      return 'HCI connection timeout (supervision)';
    case 15:
      return 'ATT insufficient encryption (0x0F)';
    case 19:
      return 'HCI remote user terminated';
    case 22:
      return 'HCI connection terminated by local host';
    case 34:
      return 'HCI LMP response timeout';
    case 62:
      return 'HCI connection failed to be established';
    case 133:
      return 'GATT_ERROR (133, lỗi chung của stack Android)';
    case 137:
      return 'GATT_AUTH_FAIL (137)';
    default:
      return 'mã $code';
  }
}

/// Rút mã GATT/ATT/HCI từ chuỗi lỗi của FlutterBluePlusException khi không có
/// `code` có kiểu. CHỈ nhận mã của nền tảng native (android/apple): mã
/// `fbp-code` là chỉ số FbpErrorCode (1=timeout, 5=removeBondFailed,
/// 6=deviceIsDisconnected…) và TRÙNG SỐ với mã ATT (vd 5, 15) nên tuyệt đối
/// không được coi là mã GATT.
/// Ví dụ: "FlutterBluePlusException | connect | android-code: 133 | ...".
int? extractCodeFromText(String text) {
  final m = RegExp(r'(?:android|apple)-code:\s*(-?\d+)', caseSensitive: false)
      .firstMatch(text);
  if (m != null) return int.tryParse(m.group(1)!);
  return null;
}

/// Lỗi "cần mã hóa/xác thực link" — dựa trên MÃ SỐ, không dò chuỗi con '137'.
bool isEncryptionCode(int? code) => code == 5 || code == 15 || code == 137;

/// Lỗi đứt kết nối (HCI) — dùng để tách "link lost" khỏi lỗi giao thức.
bool isLinkLossCode(int? code) =>
    code == 8 || code == 19 || code == 22 || code == 34 || code == 62;

/// Phân loại một lỗi thô thành ConnectFailure ở bước [stage].
/// [code] nên truyền từ FlutterBluePlusException.code; nếu null sẽ thử rút
/// từ chuỗi lỗi.
ConnectFailure classifyError(
  ConnectStage stage,
  Object error, {
  int? code,
  Duration? timeout,
}) {
  if (error is ConnectFailure) return error;
  final text = error.toString();
  final lower = text.toLowerCase();
  final c = code ?? extractCodeFromText(text);
  final safeDetail = Redactor.scrubText(text);

  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      error.runtimeType.toString() == 'TimeoutException') {
    return ConnectFailure(
      stage,
      stage == ConnectStage.gattConnect
          ? ConnectFailureKind.gattConnectTimeout
          : ConnectFailureKind.operationTimeout,
      safeDetail,
      code: c,
      timeout: timeout,
    );
  }
  if (lower.contains('adapter') && lower.contains('off') ||
      lower.contains('adapterisoff') ||
      lower.contains('bluetooth is off')) {
    return ConnectFailure(stage, ConnectFailureKind.adapterOff, safeDetail,
        code: c);
  }
  if (lower.contains('device is not connected') ||
      lower.contains('deviceisdisconnected') ||
      isLinkLossCode(c)) {
    return ConnectFailure(
        stage, ConnectFailureKind.linkLostDuringSetup, safeDetail,
        code: c);
  }
  if (isEncryptionCode(c) || lower.contains('insufficient')) {
    return ConnectFailure(stage, ConnectFailureKind.encryptionRequired,
        safeDetail,
        code: c);
  }
  if (lower.contains('createbond') || lower.contains('bond')) {
    if (lower.contains('cancel') || lower.contains('reject')) {
      return ConnectFailure(stage, ConnectFailureKind.bondingRejected,
          safeDetail,
          code: c);
    }
    return ConnectFailure(stage, ConnectFailureKind.bondingFailed, safeDetail,
        code: c);
  }
  if (stage == ConnectStage.gattConnect) {
    return ConnectFailure(
        stage, ConnectFailureKind.gattConnectFailed, safeDetail,
        code: c);
  }
  if (stage == ConnectStage.discoverServices) {
    return ConnectFailure(
        stage, ConnectFailureKind.serviceDiscoveryFailed, safeDetail,
        code: c);
  }
  return ConnectFailure(stage, ConnectFailureKind.unknown, safeDetail,
      code: c);
}

// ---------------------------------------------------------------------------
// Chính sách thử lại theo loại lỗi
// ---------------------------------------------------------------------------

/// Loại lỗi nào đáng thử lại tự động. Lỗi cấu hình/quyền/dữ liệu hỏng/thiếu
/// dịch vụ KHÔNG thử lại (thử lại chỉ tốn thời gian và giữ link vô ích).
bool isRetryable(ConnectFailureKind k) {
  switch (k) {
    case ConnectFailureKind.gattConnectFailed:
    case ConnectFailureKind.gattConnectTimeout:
    case ConnectFailureKind.linkLostDuringSetup:
    case ConnectFailureKind.operationTimeout:
    case ConnectFailureKind.serviceDiscoveryFailed:
    case ConnectFailureKind.encryptionRequired:
    case ConnectFailureKind.authChallengeUnavailable:
    case ConnectFailureKind.authRejected:
    case ConnectFailureKind.unknown:
      return true;
    case ConnectFailureKind.permissionDenied:
    case ConnectFailureKind.permissionPermanentlyDenied:
    case ConnectFailureKind.adapterOff:
    case ConnectFailureKind.busy:
    case ConnectFailureKind.storageCorrupt:
    case ConnectFailureKind.mtuFailed:
    case ConnectFailureKind.requiredServiceMissing:
    case ConnectFailureKind.bondingFailed:
    case ConnectFailureKind.bondingRejected:
    case ConnectFailureKind.bondMismatchSuspected:
    case ConnectFailureKind.appAuthFailed:
    case ConnectFailureKind.sessionKeyInvalid:
    case ConnectFailureKind.telemetryInvalid:
      return false;
  }
}

/// Chờ bao lâu trước lần thử kế tiếp. authRejected giữ 3 giây như cơ chế
/// "xe giữ khóa phiên sau khi bị đứt" đã quan sát trước đây; các lỗi link
/// dùng 2 giây để stack Android kịp giải phóng GATT client.
Duration retryDelay(ConnectFailureKind k) =>
    k == ConnectFailureKind.authRejected
        ? const Duration(seconds: 3)
        : const Duration(seconds: 2);

/// Số lần thử tối đa cho loại lỗi (kể cả lần đầu).
int maxAttemptsFor(ConnectFailureKind k) {
  switch (k) {
    case ConnectFailureKind.authRejected:
      return 5; // khớp vòng "recovery" 5 chu kỳ × 3s trước đây
    case ConnectFailureKind.gattConnectFailed:
    case ConnectFailureKind.gattConnectTimeout:
    case ConnectFailureKind.linkLostDuringSetup:
    case ConnectFailureKind.operationTimeout:
    case ConnectFailureKind.serviceDiscoveryFailed:
    case ConnectFailureKind.encryptionRequired:
    case ConnectFailureKind.authChallengeUnavailable:
    case ConnectFailureKind.unknown:
      return 3;
    default:
      return 1;
  }
}

// ---------------------------------------------------------------------------
// Bằng chứng bond lệch — chỉ khi ĐỦ bằng chứng mới gợi ý người dùng xóa bond
// ---------------------------------------------------------------------------

/// Gom bằng chứng để quyết định có nghi bond mismatch hay không.
/// App KHÔNG BAO GIỜ tự gọi removeBond dựa trên số lần reconnect thất bại.
class BondEvidence {
  int encryptionErrorsWhileBonded = 0;
  bool bondDisappearedAfterConnect = false; // từng bonded, nay hệ thống báo none

  void recordEncryptionError({required bool bondedAtTime}) {
    if (bondedAtTime) encryptionErrorsWhileBonded++;
  }

  void recordBondDisappeared() => bondDisappearedAfterConnect = true;

  /// Lỗi "cần mã hóa/xác thực" LẶP LẠI dù hệ thống báo đã bond: đây là bằng
  /// chứng đủ mạnh (khóa lưu ở điện thoại và ở xe không còn khớp). Một lỗi
  /// đơn lẻ KHÔNG đủ — có thể chỉ là link chưa kịp mã hóa.
  bool get repeatedEncryptionFailure => encryptionErrorsWhileBonded >= 2;

  /// Thông tin tổng hợp cho báo cáo. Bond biến mất (người dùng quên thiết bị
  /// trong Cài đặt hệ thống) KHÔNG phải mismatch: createBond sẽ xử lý bình
  /// thường, nên không dùng làm điều kiện ném lỗi.
  bool get suspected => repeatedEncryptionFailure;

  /// Xóa bằng chứng sau khi kết nối thành công hoặc khi người dùng quên xe.
  void reset() {
    encryptionErrorsWhileBonded = 0;
    bondDisappearedAfterConnect = false;
  }

  Map<String, Object?> toJson() => {
        'encryption_errors_while_bonded': encryptionErrorsWhileBonded,
        'bond_disappeared_after_connect': bondDisappearedAfterConnect,
        'repeated_encryption_failure': repeatedEncryptionFailure,
        'suspected': suspected,
      };
}

// ---------------------------------------------------------------------------
// Che dữ liệu nhạy cảm
// ---------------------------------------------------------------------------

class Redactor {
  Redactor._();

  /// Tiền tố loại event thuộc luồng xác thực — áp dụng chế độ che NGHIÊM NGẶT
  /// (kể cả trường 'hex'). Các event khác (Firmware Lab, Battery Log, bảng
  /// GATT…) giữ nguyên để không làm hỏng chức năng log hiện có.
  static const List<String> strictEventPrefixes = [
    'auto_handshake',
    'auth_',
    'phase1',
    'phase2',
    'keepalive',
    'session_key',
    'handshake',
  ];

  /// Tên trường bị coi là nhạy cảm → giá trị luôn bị che (chế độ nghiêm ngặt).
  static final RegExp _sensitiveKey = RegExp(
    r'(token|pin|pass|secret|session_?key|^sk$|key8|^hex$|^raw$|resp|salt|nonce|'
    r'challenge|credential|new_password|candidate)',
    caseSensitive: false,
  );

  /// Trường được phép dù khớp mẫu trên (chỉ chứa độ dài/cờ/dấu vân tay).
  static const Set<String> _allowList = {
    'has_stored',
    'has_stored_password',
    'pin_len',
    'token_len',
    'password_len',
    'nonce_len',
    'challenge_len',
    'resp_len',
    'response_len',
    'status',
    'status_byte',
    'nonce_fp',
    'challenge_fp',
    'resp_fp',
    'candidate_index',
    'candidate_count',
    'candidate_kind',
    'force_register',
    'session_key_derived',
    'session_key_len',
    'session_live',
    'pin_empty',
  };

  /// Các trường chứa UUID GATT công khai — không che UUID trong đó.
  static const Set<String> _publicUuidKeys = {
    'uuid',
    'service',
    'services',
    'characteristics',
    'characteristic',
  };

  static final Set<String> _secrets = <String>{};

  /// Đăng ký một giá trị bí mật lúc chạy (token, password, PIN, khóa phiên
  /// dạng hex). Mọi văn bản qua [scrubText] chứa giá trị này đều bị che.
  /// Chuỗi quá ngắn (< 4 ký tự) bị bỏ qua để tránh che nhầm hàng loạt.
  static void registerSecret(String value) {
    if (value.length >= 4) _secrets.add(value);
  }

  static void clearSecretsForTest() => _secrets.clear();

  /// Dấu vân tay ngắn (4 byte đầu SHA-256) — đủ để đối chiếu hai dòng log
  /// cùng một giá trị mà không lộ giá trị. CHỈ dùng cho nonce/challenge/
  /// response (entropy cao). KHÔNG dùng cho PIN/password (dễ brute-force).
  static String fingerprint(List<int> bytes) {
    final d = sha256.convert(bytes).bytes;
    return d.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool isStrictEvent(String type) =>
      strictEventPrefixes.any((p) => type.startsWith(p));

  /// Che dữ liệu của một event log. [strict] = true cho event xác thực.
  static Map<String, Object?> sanitizeEvent(
      String type, Map<String, Object?> data) {
    return _sanitize(data, strict: isStrictEvent(type));
  }

  /// Che NGHIÊM NGẶT bất kể loại event — dùng khi xuất log để chia sẻ (kể cả
  /// event không thuộc luồng xác thực nhưng có ghi hex của gói thô).
  static Map<String, Object?> sanitizeStrict(Map<String, Object?> data) {
    return _sanitize(data, strict: true);
  }

  static Map<String, Object?> _sanitize(Map<String, Object?> data,
      {required bool strict}) {
    final out = <String, Object?>{};
    data.forEach((k, v) {
      if (strict && !_allowList.contains(k) && _sensitiveKey.hasMatch(k)) {
        out[k] = '«redacted»';
      } else {
        out[k] = _sanitizeValue(k, v, strict: strict);
      }
    });
    return out;
  }

  static Object? _sanitizeValue(String key, Object? v, {required bool strict}) {
    if (v is Map<String, Object?>) return _sanitize(v, strict: strict);
    if (v is List) {
      return [for (final e in v) _sanitizeValue(key, e, strict: strict)];
    }
    if (v is String) {
      // Bí mật đã đăng ký luôn bị che, ở mọi loại event.
      return _maskSecrets(v);
    }
    return v;
  }

  static String _maskSecrets(String s) {
    var t = s;
    for (final secret in _secrets) {
      if (t.contains(secret)) t = t.replaceAll(secret, '«redacted»');
    }
    return t;
  }

  /// Che các mẫu nhạy cảm trong văn bản tự do (thông điệp lỗi, ghi chú,
  /// nhãn): bí mật đã đăng ký, chuỗi hex dài >= 32 ký tự, và cặp
  /// khóa=giá trị kiểu password=..., pin: ..., token=...
  static String scrubText(String s) {
    var t = _maskSecrets(s);
    t = t.replaceAll(RegExp(r'\b[0-9a-fA-F]{32,}\b'), '«hex»');
    t = t.replaceAllMapped(
        RegExp(
            r"""(password|passwd|pin|token|secret|key)\s*[:=]\s*["']?[^\s"',;]+""",
            caseSensitive: false),
        (m) => '${m.group(1)}=«redacted»');
    return t;
  }

  /// Dùng cho test/kiểm tra: trường [key] có bị coi là nhạy cảm không.
  static bool isSensitiveKey(String key) =>
      !_allowList.contains(key) && _sensitiveKey.hasMatch(key);

  static bool isPublicUuidKey(String key) => _publicUuidKeys.contains(key);
}

// ---------------------------------------------------------------------------
// Máy trạng thái + báo cáo
// ---------------------------------------------------------------------------

enum StepOutcome { started, ok, warn, failed }

class StepRecord {
  StepRecord(this.stage, this.outcome, this.at, this.elapsed, this.note,
      {this.code, this.timeout});

  final ConnectStage stage;
  final StepOutcome outcome;
  final DateTime at;
  final Duration elapsed;
  final String note;
  final int? code;
  final Duration? timeout;

  Map<String, Object?> toJson() => {
        'ts': at.toIso8601String(),
        'stage': stage.name,
        'outcome': outcome.name,
        'elapsed_ms': elapsed.inMilliseconds,
        if (note.isNotEmpty) 'note': Redactor.scrubText(note),
        if (code != null) 'code': code,
        if (timeout != null) 'timeout_ms': timeout!.inMilliseconds,
      };
}

typedef Clock = DateTime Function();

/// Theo dõi tiến trình một lần kết nối. Không phụ thuộc BLE thật → test được.
class ConnectStateMachine {
  ConnectStateMachine({Clock? clock}) : _clock = clock ?? DateTime.now {
    _t0 = _clock();
  }

  final Clock _clock;
  late DateTime _t0;
  final List<StepRecord> steps = [];
  final Map<ConnectStage, DateTime> _startedAt = {};

  ConnectStage? current;
  ConnectFailure? firstFailure;
  ConnectStage? lastSuccess;
  final BondEvidence bondEvidence = BondEvidence();
  int? negotiatedMtu;

  /// Đặt lại cho một lần thử mới (giữ nguyên bằng chứng bond qua các lần thử).
  void beginAttempt() {
    steps.clear();
    _startedAt.clear();
    current = null;
    firstFailure = null;
    lastSuccess = null;
    negotiatedMtu = null;
    _t0 = _clock();
  }

  Duration _since(ConnectStage s) {
    final st = _startedAt[s];
    return st == null ? Duration.zero : _clock().difference(st);
  }

  void start(ConnectStage s, [String note = '']) {
    current = s;
    _startedAt[s] = _clock();
    steps.add(StepRecord(s, StepOutcome.started, _clock(), Duration.zero, note));
  }

  void ok(ConnectStage s, [String note = '']) {
    steps.add(StepRecord(s, StepOutcome.ok, _clock(), _since(s), note));
    lastSuccess = s;
  }

  /// Cảnh báo: bước không hoàn hảo nhưng không chặn (vd MTU).
  void warn(ConnectStage s, String note, {int? code}) {
    steps.add(
        StepRecord(s, StepOutcome.warn, _clock(), _since(s), note, code: code));
  }

  /// Ghi thất bại; chỉ giữ thất bại ĐẦU TIÊN làm điểm hỏng.
  ConnectFailure fail(ConnectFailure f) {
    steps.add(StepRecord(f.stage, StepOutcome.failed, _clock(), _since(f.stage),
        '${f.kind.name}: ${f.detail}',
        code: f.code, timeout: f.timeout));
    firstFailure ??= f;
    return f;
  }

  bool get succeeded =>
      firstFailure == null && lastSuccess == ConnectStage.telemetry;

  /// Báo cáo văn bản — KHÔNG chứa bí mật (mọi note đều qua scrubText).
  String buildReport({String appBuild = '', String bikeModel = ''}) {
    final b = StringBuffer();
    b.writeln('BÁO CÁO CHẨN ĐOÁN KẾT NỐI BLE');
    if (appBuild.isNotEmpty) b.writeln('Build: $appBuild');
    if (bikeModel.isNotEmpty) b.writeln('Xe: $bikeModel');
    b.writeln('Tổng thời gian: ${_clock().difference(_t0).inMilliseconds} ms');
    if (negotiatedMtu != null) {
      b.writeln('MTU thực tế: $negotiatedMtu '
          '(payload tối đa ${maxAttPayload(negotiatedMtu!)} byte)');
    }
    b.writeln('Bước cuối cùng thành công: '
        '${lastSuccess == null ? '(chưa có)' : '${lastSuccess!.name} — ${stageLabel(lastSuccess!)}'}');
    if (firstFailure == null) {
      b.writeln('Bước đầu tiên thất bại: (không có)');
    } else {
      final f = firstFailure!;
      b.writeln('Bước đầu tiên thất bại: ${f.stage.name} — '
          '${stageLabel(f.stage)}');
      b.writeln('Loại lỗi: ${f.kind.name}');
      if (f.code != null) {
        b.writeln('Mã lỗi: ${f.code} (${describeGattCode(f.code!)})');
      }
      if (f.timeout != null) {
        b.writeln('Timeout áp dụng: ${f.timeout!.inMilliseconds} ms');
      }
      b.writeln('Chi tiết: ${Redactor.scrubText(f.detail)}');
    }
    b.writeln('Bằng chứng bond: ${jsonEncode(bondEvidence.toJson())}');
    b.writeln('--- Dòng thời gian ---');
    for (final s in steps) {
      final off = s.at.difference(_t0).inMilliseconds;
      b.writeln('+${off}ms ${s.stage.name} ${s.outcome.name}'
          ' (${s.elapsed.inMilliseconds}ms)'
          '${s.code != null ? ' code=${s.code}' : ''}'
          '${s.note.isNotEmpty ? ' — ${Redactor.scrubText(s.note)}' : ''}');
    }
    return b.toString();
  }
}

/// Payload ATT tối đa của một thao tác ghi (MTU − 3 byte header ATT).
int maxAttPayload(int mtu) => mtu < 23 ? 20 : mtu - 3;

/// MTU tối thiểu để ghi nguyên một khung [bytes] không cần long-write.
bool mtuFitsPayload(int mtu, int bytes) => maxAttPayload(mtu) >= bytes;
