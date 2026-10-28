// Mô-đun Regen (phanh tái sinh) — LỚP GIAO THỨC + MÁY TRẠNG THÁI.
//
// TÌNH TRẠNG XÁC MINH (kiểm tra mã nguồn v2.8.0, docs/BLE_PROTOCOL_SPEC.md,
// Firmware Lab, Ghidra RE2 mainPcb-1.14.0): CHƯA có characteristic nào được
// xác minh là đọc/ghi mức Regen. Vì vậy [RegenProtocolSpec.unverified] là mặc
// định: không có UUID, không có mức, và KHÔNG có đường ghi nào được mở.
//
// Khi (và chỉ khi) có bằng chứng, xem docs/REGEN_VERIFICATION.md, cập nhật
// [RegenProtocolSpec.verified] và cung cấp một [RegenTransport] thật.

import 'package:flutter/foundation.dart';

import '../ble/gatt.dart';

/// Một mức Regen ĐÃ XÁC MINH trên xe.
@immutable
class RegenLevel {
  final int index; // thứ tự hiển thị 0..n-1
  final String label; // nhãn hiển thị
  final int rawValue; // giá trị thô đọc/ghi trên xe

  /// true = xe lưu/đọc lại được giá trị này nhưng HIỆU ỨNG Regen chưa xác minh.
  final bool experimental;

  const RegenLevel({
    required this.index,
    required this.label,
    required this.rawValue,
    this.experimental = false,
  });
}

/// Mô tả giao thức Regen. Chỉ dùng được khi [verified] = true.
@immutable
class RegenProtocolSpec {
  final bool verified;
  final String? characteristicUuid;
  final List<RegenLevel> levels;

  /// Chỉ cho đổi khi xe đứng yên (mặc định BẮT BUỘC, do chưa có tài liệu nhà
  /// sản xuất cho phép đổi khi đang chạy).
  final bool requiresStandstill;

  /// Nguồn bằng chứng (offset firmware, btsnoop, ngày test...).
  final String evidence;

  const RegenProtocolSpec({
    required this.verified,
    required this.characteristicUuid,
    required this.levels,
    required this.requiresStandstill,
    required this.evidence,
  });

  /// Mặc định hiện tại: CHƯA xác minh → mọi thao tác ghi bị khóa.
  static const RegenProtocolSpec unverified = RegenProtocolSpec(
    verified: false,
    characteristicUuid: null,
    levels: [],
    requiresStandstill: true,
    evidence: 'Chưa tìm thấy characteristic Regen trong fw 1.14.0 / btsnoop.',
  );

  /// Regen qua char Grab (a1d8e7c4).
  /// Bằng chứng: (1) Lab 23/10: ghi '1' đọc lại 01 (parser boolean, Ghidra
  /// onWriteGrabMode @0x40153e30); (2) người dùng xác nhận 28/10/2026: đổi Grab
  /// làm dòng nạp ngược thay đổi. CHƯA biết mức nào mạnh/yếu hơn.
  /// Mức 0/1 là đã xác minh; mức >= 2 chỉ có khi bước dò ([maxLevel]) cho thấy
  /// xe ghi và đọc lại được đúng giá trị, và luôn gắn cờ experimental.
  static RegenProtocolSpec grab({int maxLevel = 1}) {
    final top = maxLevel < 1 ? 1 : (maxLevel > 9 ? 9 : maxLevel);
    return RegenProtocolSpec(
      verified: true,
      characteristicUuid: Gatt.grabModeChar,
      requiresStandstill: true,
      evidence: 'Grab a1d8e7c4: parser boolean (Ghidra) + người dùng xác nhận '
          'đổi Grab làm đổi dòng nạp ngược. Mức >= 2 chưa xác minh hiệu ứng.',
      levels: [
        for (var i = 0; i <= top; i++)
          RegenLevel(
            index: i,
            rawValue: i,
            experimental: i >= 2,
            label: i == 0
                ? 'Regen mức 0'
                : (i == 1 ? 'Regen mức 1' : 'Regen mức $i (thử nghiệm)'),
          ),
      ],
    );
  }

  RegenLevel? levelByRaw(int raw) {
    for (final l in levels) {
      if (l.rawValue == raw) return l;
    }
    return null;
  }

  RegenLevel? levelByIndex(int index) {
    for (final l in levels) {
      if (l.index == index) return l;
    }
    return null;
  }
}

/// Cầu nối tới xe. Triển khai thật chỉ được viết SAU khi xác minh giao thức.
abstract class RegenTransport {
  /// Đọc giá trị thô hiện tại từ xe; null nếu không đọc/giải mã được.
  Future<int?> readRaw();

  /// Gửi giá trị thô. true = xe chấp nhận lệnh GHI (chưa phải đã đổi — phải
  /// đọc lại để xác nhận). Ném lỗi/false nếu mất kết nối hay bị từ chối.
  Future<bool> writeRaw(int raw);
}

/// Transport mặc định: không có đường tới xe.
class UnavailableRegenTransport implements RegenTransport {
  const UnavailableRegenTransport();
  @override
  Future<int?> readRaw() async => null;
  @override
  Future<bool> writeRaw(int raw) async => false;
}

/// Ảnh chụp tình trạng liên kết, dùng cho cổng an toàn.
@immutable
class RegenLinkInfo {
  final bool connected;
  final bool authorized;
  final bool telemetryFresh; // telemetry < 4 giây
  final double? speedKmh; // null = chưa biết

  const RegenLinkInfo({
    required this.connected,
    required this.authorized,
    required this.telemetryFresh,
    required this.speedKmh,
  });
}

/// Cổng an toàn. Trả về lý do chặn, hoặc null nếu được phép.
/// "Chưa biết tốc độ" KHÔNG được coi là 0 (cùng nguyên tắc v2.8.0).
String? regenBlockReason(RegenLinkInfo link, {required bool requiresStandstill}) {
  if (!link.connected) return 'Chưa kết nối xe qua Bluetooth.';
  if (!link.authorized) return 'Xe chưa xác thực phiên.';
  if (requiresStandstill) {
    if (!link.telemetryFresh || link.speedKmh == null) {
      return 'Chưa có dữ liệu tốc độ mới từ xe (< 4 giây) nên không xác nhận được xe đang đứng yên.';
    }
    if (link.speedKmh! > 0.5) {
      return 'Xe đang chạy (${link.speedKmh!.toStringAsFixed(1)} km/h). Dừng hẳn xe rồi đổi Regen.';
    }
  }
  return null;
}

enum RegenSyncStatus {
  unsupported, // chưa xác minh giao thức → không điều khiển được
  disconnected, // chưa kết nối
  unknown, // chưa đọc được mức từ xe
  synced, // mức xe == mức đã chọn (đã đọc lại xác nhận)
  pending, // đã chọn mức khác, chưa gửi
  writing, // đang gửi
  verifying, // đang đọc lại
  mismatch, // đã gửi nhưng xe KHÔNG ở mức mong muốn
  failed, // lỗi giao tiếp / bị chặn
}

@immutable
class RegenState {
  final RegenSyncStatus status;
  final int? currentIndex; // mức xe báo cáo (đã đọc), null = chưa biết
  final int? currentRaw; // giá trị thô xe báo cáo nhưng không khớp mức nào
  final int? selectedIndex; // mức người dùng chọn
  final String? message;
  final DateTime? lastReadAt;

  const RegenState({
    this.status = RegenSyncStatus.unsupported,
    this.currentIndex,
    this.currentRaw,
    this.selectedIndex,
    this.message,
    this.lastReadAt,
  });

  RegenState copyWith({
    RegenSyncStatus? status,
    Object? currentIndex = _keep,
    Object? currentRaw = _keep,
    Object? selectedIndex = _keep,
    Object? message = _keep,
    DateTime? lastReadAt,
  }) {
    return RegenState(
      status: status ?? this.status,
      currentIndex: identical(currentIndex, _keep) ? this.currentIndex : currentIndex as int?,
      currentRaw: identical(currentRaw, _keep) ? this.currentRaw : currentRaw as int?,
      selectedIndex: identical(selectedIndex, _keep) ? this.selectedIndex : selectedIndex as int?,
      message: identical(message, _keep) ? this.message : message as String?,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  static const Object _keep = Object();
}
