// Kiểu dữ liệu dùng chung cho các chế độ vận hành BẬT/TẮT điều khiển thủ công
// (Grab, ECE). THUẦN Dart: không phụ thuộc BLE để test được.
//
// Nguyên tắc (xem docs/CONTROL_CENTER.md):
//  • Giá trị hiển thị CHỈ lấy từ lần ĐỌC từ xe, không lấy từ cache cục bộ.
//  • Không có "thành công" nếu chưa đọc lại được đúng giá trị từ xe.
//  • Không tự thử lại lệnh ghi.

import 'package:flutter/foundation.dart';

/// Kết quả một lần ghi cờ boolean xuống xe (kèm đọc lại ngay sau khi ghi).
@immutable
class SettingWriteOutcome {
  /// true = khung GHI đã gửi không lỗi GATT (CHƯA phải xe đã đổi).
  final bool sent;

  /// Byte đã giải mã đọc lại ngay sau khi ghi; null = không đọc được.
  final int? readBack;

  final String? error;

  const SettingWriteOutcome({required this.sent, this.readBack, this.error});
}

enum ModeKind { grab, ece }

/// Pha của một chế độ. Giá trị bật/tắt nằm riêng ở [ModeState.on].
enum ModePhase {
  /// Xe/firmware không hỗ trợ — không có đường điều khiển.
  unsupported,

  /// Có đường BLE nhưng chưa đủ bằng chứng — KHÔNG gửi lệnh.
  unverified,

  /// Chưa kết nối / chưa xác thực xe.
  disconnected,

  /// Đã kết nối nhưng chưa đọc trạng thái từ xe.
  unread,

  /// Đã đọc được trạng thái thật từ xe, không có lệnh đang chờ.
  ready,

  /// Đang gửi lệnh ghi.
  sending,

  /// Đã gửi, đang đọc lại để xác nhận.
  verifying,

  /// Đã gửi VÀ đọc lại khớp giá trị mong muốn.
  confirmed,

  /// Đã gửi nhưng xe không xác nhận (đọc lại không khớp / không đọc được /
  /// mất kết nối / xe từ chối). Hiển thị "KHÔNG XÁC NHẬN".
  notConfirmed,

  /// Bị cổng an toàn chặn, KHÔNG có lệnh nào được gửi.
  blocked,
}

/// Giá trị thô đọc từ xe. Với ECE: [primaryRaw] = cờ ECE, [secondaryRaw] = cờ
/// SpeedLimit. Với Grab: chỉ có [primaryRaw].
@immutable
class ModeSnapshot {
  final int? primaryRaw;
  final int? secondaryRaw;

  const ModeSnapshot({this.primaryRaw, this.secondaryRaw});

  bool get isEmpty => primaryRaw == null && secondaryRaw == null;
}

/// Kết quả ghi của một transport (có thể gồm nhiều characteristic).
@immutable
class ModeWriteResult {
  /// true = TẤT CẢ khung ghi cần thiết đã gửi không lỗi.
  final bool sent;

  /// true = đã ghi một phần (vd: char thứ nhất đã ghi, char thứ hai lỗi).
  final bool partial;

  final String? error;

  const ModeWriteResult({required this.sent, this.partial = false, this.error});
}

/// Cầu nối tới xe cho một chế độ.
abstract class ModeTransport {
  /// Đọc giá trị thô hiện tại. Không ghi gì. Trường null = không đọc được.
  Future<ModeSnapshot> read();

  /// Gửi lệnh bật/tắt. [cmdId] để truy vết trong nhật ký.
  Future<ModeWriteResult> write(bool on, String cmdId);
}

/// Transport mặc định cho chế độ chưa có đường điều khiển.
class UnavailableModeTransport implements ModeTransport {
  const UnavailableModeTransport();
  @override
  Future<ModeSnapshot> read() async => const ModeSnapshot();
  @override
  Future<ModeWriteResult> write(bool on, String cmdId) async =>
      const ModeWriteResult(sent: false, error: 'Không có đường điều khiển.');
}

/// Mô tả giao thức + cách diễn giải của một chế độ.
@immutable
abstract class ModeSpec {
  const ModeSpec();

  ModeKind get kind;

  /// false = không được gửi bất kỳ lệnh nào.
  bool get verified;

  /// Chỉ cho đổi khi xe đứng yên (chính sách ứng dụng — chưa có tài liệu nhà
  /// sản xuất cho phép đổi khi đang chạy).
  bool get requiresStandstill;

  /// Nguồn bằng chứng, hiển thị cho người dùng.
  String get evidence;

  /// true/false = trạng thái bật/tắt đọc được; null = không đọc được hoặc
  /// giá trị lạ (không phải 0/1).
  bool? interpret(ModeSnapshot s);

  /// Snapshot có khớp trạng thái mong muốn [target] không.
  bool matches(ModeSnapshot s, bool target) => interpret(s) == target;
}

/// Một dòng truy vết lệnh (cũng được ghi vào BleLogger với cùng [id]).
@immutable
class CommandTrace {
  final String id;
  final bool targetOn;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// 'pending' | 'confirmed' | 'not_confirmed' | 'rejected' | 'blocked'
  final String outcome;

  /// Giá trị thô đọc lại sau khi ghi (nếu có).
  final int? readBackPrimary;
  final int? readBackSecondary;

  const CommandTrace({
    required this.id,
    required this.targetOn,
    required this.startedAt,
    this.endedAt,
    this.outcome = 'pending',
    this.readBackPrimary,
    this.readBackSecondary,
  });

  CommandTrace finish(String outcome, {ModeSnapshot? readBack}) => CommandTrace(
        id: id,
        targetOn: targetOn,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        outcome: outcome,
        readBackPrimary: readBack?.primaryRaw,
        readBackSecondary: readBack?.secondaryRaw,
      );
}

@immutable
class ModeState {
  final ModePhase phase;

  /// Trạng thái bật/tắt ĐỌC ĐƯỢC từ xe; null = chưa biết. Không bao giờ lấy
  /// từ cache cục bộ.
  final bool? on;
  final ModeSnapshot? snapshot;
  final String? message;
  final DateTime? lastReadAt;
  final CommandTrace? lastCommand;

  const ModeState({
    required this.phase,
    this.on,
    this.snapshot,
    this.message,
    this.lastReadAt,
    this.lastCommand,
  });

  bool get busy => phase == ModePhase.sending || phase == ModePhase.verifying;

  ModeState copyWith({
    ModePhase? phase,
    Object? on = _keep,
    Object? snapshot = _keep,
    Object? message = _keep,
    DateTime? lastReadAt,
    Object? lastCommand = _keep,
  }) {
    return ModeState(
      phase: phase ?? this.phase,
      on: identical(on, _keep) ? this.on : on as bool?,
      snapshot: identical(snapshot, _keep) ? this.snapshot : snapshot as ModeSnapshot?,
      message: identical(message, _keep) ? this.message : message as String?,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      lastCommand: identical(lastCommand, _keep) ? this.lastCommand : lastCommand as CommandTrace?,
    );
  }

  static const Object _keep = Object();
}
