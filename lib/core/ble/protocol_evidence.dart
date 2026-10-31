// Sổ bằng chứng giao thức BLE — module THUẦN Dart, CHỈ để minh bạch.
//
// Mục đích: phân biệt rõ điều gì có bằng chứng và điều gì chỉ là tài liệu/giả
// thuyết, theo yêu cầu "không tự suy đoán giao thức BLE/BMS".
//
// QUY TẮC:
//  • Mức [EvidenceLevel.capturedVector] chỉ được dùng khi có test dùng vector
//    lấy từ capture thật (btsnoop). Test `protocol_evidence_test.dart` kiểm tra
//    file test và tên test được tham chiếu có thật trong thư mục test/.
//  • Sổ này KHÔNG tự xác minh gì thêm: nó chỉ phản ánh những gì mã nguồn, test
//    và tài liệu trong dự án tuyên bố. Chưa có mục nào được kiểm thử trên xe thật
//    trong phạm vi các test tự động.
//  • Muốn nâng mức một mục: thêm test với vector thật rồi sửa mục ở đây.

enum EvidenceLevel {
  /// Có test dùng vector lấy từ capture thật của app gốc.
  capturedVector,

  /// Có test đối chiếu với cài đặt độc lập (ví dụ Python): chứng minh công thức
  /// khớp, KHÔNG chứng minh khớp xe thật.
  crossChecked,

  /// Chỉ theo tài liệu / decompile / ghi chú trong mã; không có test đối chiếu
  /// dữ liệu thật.
  docOnly,

  /// Giả thuyết hoặc chưa có tài liệu — không được dựa vào.
  hypothesis,
}

extension EvidenceLevelX on EvidenceLevel {
  String get label {
    switch (this) {
      case EvidenceLevel.capturedVector:
        return 'Có vector capture thật';
      case EvidenceLevel.crossChecked:
        return 'Đối chiếu chéo (chưa so với xe thật)';
      case EvidenceLevel.docOnly:
        return 'Chỉ theo tài liệu';
      case EvidenceLevel.hypothesis:
        return 'Giả thuyết / chưa có tài liệu';
    }
  }

  /// Chỉ mức có capture thật được coi là "đã xác minh".
  bool get isVerified => this == EvidenceLevel.capturedVector;
}

class ProtocolEvidence {
  const ProtocolEvidence({
    required this.id,
    required this.title,
    required this.level,
    required this.basis,
    this.testFile,
    this.testName,
    this.controlRelated = false,
  });

  final String id;
  final String title;
  final EvidenceLevel level;

  /// Căn cứ: nguồn tuyên bố và giới hạn.
  final String basis;

  /// File test (tương đối từ gốc dự án) và tên test chứng minh mức bằng chứng.
  final String? testFile;
  final String? testName;

  /// Liên quan đến lệnh GHI/điều khiển xe.
  final bool controlRelated;
}

const List<ProtocolEvidence> kProtocolEvidence = [
  ProtocolEvidence(
    id: 'auth_response',
    title: 'Phản hồi xác thực Phase 1 (HMAC trên nonce)',
    level: EvidenceLevel.capturedVector,
    basis: '3 cặp nonce/response lấy từ btsnoop của app gốc (firmware 1.14.0).',
    testFile: 'test/session_crypto_test.dart',
    testName: 'computeAuthResponse khớp vector THẬT từ btsnoop app gốc',
  ),
  ProtocolEvidence(
    id: 'app_auth_challenge',
    title: 'Challenge–response ứng dụng (SHA-256 trên c8eaf27b)',
    level: EvidenceLevel.capturedVector,
    basis: '1 vector từ btsnoop kết nối thứ hai của app gốc.',
    testFile: 'test/session_crypto_test.dart',
    testName: 'computeAppAuthChallengeResponse khớp vector THẬT từ btsnoop conn2',
  ),
  ProtocolEvidence(
    id: 'session_key',
    title: 'Dẫn xuất khóa phiên (HKDF “DBsess1”)',
    level: EvidenceLevel.crossChecked,
    basis: 'Công thức theo decompile; test khớp vector sinh bằng Python. '
        'Ghi chú trong mã: chưa kiểm lại trên frame thật.',
    testFile: 'test/session_crypto_test.dart',
    testName: 'deriveSessionKey khớp HKDF vector Python',
  ),
  ProtocolEvidence(
    id: 'protected_write',
    title: 'Khung ghi bảo vệ [counter][data][tag 4B]',
    level: EvidenceLevel.crossChecked,
    basis: 'Hình dạng khung khớp btsnoop theo ghi chú trong mã; tag HMAC '
        'khớp vector Python, chưa kiểm lại trên frame thật.',
    testFile: 'test/session_crypto_test.dart',
    testName: 'buildProtectedWrite khớp frame vector Python',
    controlRelated: true,
  ),
  ProtocolEvidence(
    id: 'protected_read',
    title: 'Giải mã đọc bảo vệ (header 4B + keystream XOR)',
    level: EvidenceLevel.crossChecked,
    basis: 'Header 4 byte khớp btsnoop theo ghi chú trong mã; vector giải mã '
        'được tái sinh bằng cài đặt độc lập.',
    testFile: 'test/session_crypto_test.dart',
    testName: 'decryptProtectedRead: header 4B + XOR keystream 2 block + frame <4B trả rỗng',
  ),
  ProtocolEvidence(
    id: 'dashboard_decode',
    title: 'Giải mã telemetry dashboard (protobuf)',
    level: EvidenceLevel.docOnly,
    basis: 'Test dựng byte bằng tay theo bike.proto của app gốc; chưa có gói '
        'dashboard thật làm vector.',
    testFile: 'test/bike_log_test.dart',
    testName: 'BikeLogMsg: speed/state/kmLeft/charging',
  ),
  ProtocolEvidence(
    id: 'battery_decode',
    title: 'Giải mã log BMS (protobuf/JSON, điện áp từng cell)',
    level: EvidenceLevel.docOnly,
    basis: 'Test dựng byte bằng tay; chưa có gói BMS thật làm vector.',
    testFile: 'test/bike_log_test.dart',
    testName: 'BatteryLogMsg: cellVols packed + voltage',
  ),
  ProtocolEvidence(
    id: 'gatt_map',
    title: 'Bản đồ UUID service/characteristic',
    level: EvidenceLevel.docOnly,
    basis: 'docs/BLE_PROTOCOL_SPEC.md tuyên bố đã đối chiếu decompile, firmware '
        'và btsnoop; không có test tự động đối chiếu bản đồ này.',
  ),
  ProtocolEvidence(
    id: 'dashboard_poll',
    title: 'Dashboard đọc theo chu kỳ (không dùng Notify)',
    level: EvidenceLevel.docOnly,
    basis: 'Theo docs/BLE_PROTOCOL_SPEC.md; mã chỉ đăng ký notify nếu '
        'characteristic khai báo hỗ trợ.',
  ),
  ProtocolEvidence(
    id: 'power_command',
    title: 'Lệnh bật/tắt nguồn xe',
    level: EvidenceLevel.docOnly,
    basis: 'Theo docs/BLE_PROTOCOL_SPEC.md; không có test vector. '
        'Chưa được kiểm thử trên xe thật trong phạm vi test tự động.',
    controlRelated: true,
  ),
  ProtocolEvidence(
    id: 'find_bike_beep',
    title: 'Lệnh còi/đèn tìm xe',
    level: EvidenceLevel.docOnly,
    basis: 'Theo docs/BLE_PROTOCOL_SPEC.md; không có test vector.',
    controlRelated: true,
  ),
  ProtocolEvidence(
    id: 'cell_balancing_control',
    title: 'Điều khiển cân bằng cell',
    level: EvidenceLevel.hypothesis,
    basis: 'Không có tài liệu giao thức. Ứng dụng KHÔNG gửi lệnh này.',
    controlRelated: true,
  ),
];

/// Lệnh điều khiển mới chỉ được thêm khi mục bằng chứng tương ứng đã được xác
/// minh bằng capture thật.
bool evidenceAllowsNewControl(ProtocolEvidence e) =>
    e.controlRelated && e.level.isVerified;
