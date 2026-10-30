// Dashboard Sync — lớp tích hợp ĐỒNG BỘ LÊN MÀN HÌNH XE (On-Bike Display Sync).
//
// TÌNH TRẠNG XÁC MINH (firmware mainPcb-1.14.0 qua Ghidra RE2 + log GATT thật
// 29/10/2026: 8 service / 38 characteristic): KHÔNG có characteristic nào để
// ghi theme, bitmap, frame hay lệnh hiển thị lên màn hình xe. Đường ghi duy
// nhất chạm "màn hình" là đồng bộ giờ RTC (44e2bde6). Service 5b6d1069 là OTA
// firmware — KHÔNG được dùng cho mục đích này (nguy cơ làm hỏng xe).
//
// Vì vậy [DisplaySyncSpec.unverified] là mặc định: engine KHÔNG BAO GIỜ gọi
// transport và không bao giờ báo thành công. Lớp này tồn tại để khi có bằng
// chứng (btsnoop app gốc + Ghidra handler) chỉ cần cấp [DisplaySyncSpec]
// verified + một [DisplaySyncTransport] thật, không phải viết lại kiến trúc.
//
// Lưu ý kiến trúc: nếu sau này có kênh thật, nó phải đi qua hàng đợi GATT của
// BleController với ưu tiên THẤP hơn lệnh điều khiển (khóa/nguồn/Regen), và
// tần suất ≤ spec.maxHz. Đặt mục tiêu 10–20 Hz chỉ khi spec cho phép.

import 'dart:async';

enum DisplaySyncStatus {
  unsupported, // chưa có bằng chứng giao thức → không thể đồng bộ
  disconnected, // giao thức hỗ trợ nhưng xe chưa kết nối
  ready,
  sending,
  awaitingAck,
  done, // đã nhận ACK từ xe
  failed,
  recovering, // đang thử lại sau lỗi
}

class DisplaySyncSpec {
  final bool verified;
  final String? characteristicUuid;
  final int maxChunkBytes;
  final double maxHz;
  final Duration ackTimeout;
  final int maxRetries;
  final List<String> evidence; // bằng chứng / lý do

  const DisplaySyncSpec({
    required this.verified,
    required this.characteristicUuid,
    required this.maxChunkBytes,
    required this.maxHz,
    required this.ackTimeout,
    required this.maxRetries,
    required this.evidence,
  });

  static const DisplaySyncSpec unverified = DisplaySyncSpec(
    verified: false,
    characteristicUuid: null,
    maxChunkBytes: 0,
    maxHz: 0,
    ackTimeout: Duration(seconds: 2),
    maxRetries: 0,
    evidence: [
      'Firmware 1.14.0 (Ghidra RE2) và log GATT thật (8 service, 38 '
          'characteristic) không có characteristic nào cho theme/bitmap/frame '
          'hiển thị của đồng hồ xe.',
      'Đường ghi liên quan màn hình duy nhất đã biết: đồng bộ GIỜ RTC '
          '(44e2bde6) — chỉ đặt giờ, không đổi giao diện.',
      'Service 5b6d1069 là OTA (cập nhật firmware). Không dùng cho giao diện: '
          'ghi sai có thể làm hỏng xe.',
      'Chưa có btsnoop nào của app gốc cho thấy việc đổi giao diện đồng hồ xe.',
    ],
  );
}

/// Cầu nối tới xe — chỉ cần viết SAU khi giao thức được xác minh.
abstract class DisplaySyncTransport {
  bool get connected;

  /// Ghi một khung; ném lỗi nếu thất bại.
  Future<void> writeChunk(List<int> chunk);

  /// Chờ ACK từ xe (true = xe xác nhận); false/timeout = không xác nhận.
  Future<bool> waitAck(Duration timeout);
}

class DisplaySyncState {
  final DisplaySyncStatus status;
  final double progress; // 0..1
  final String message;
  final int attempt;
  const DisplaySyncState(
    this.status, {
    this.progress = 0,
    this.message = '',
    this.attempt = 0,
  });
}

class DashboardSyncEngine {
  final DisplaySyncSpec spec;
  final DisplaySyncTransport? transport;
  DisplaySyncState _state;
  final StreamController<DisplaySyncState> _ctrl =
      StreamController<DisplaySyncState>.broadcast();
  bool _busy = false;

  DashboardSyncEngine({this.spec = DisplaySyncSpec.unverified, this.transport})
    : _state = spec.verified
          ? const DisplaySyncState(DisplaySyncStatus.ready)
          : const DisplaySyncState(
              DisplaySyncStatus.unsupported,
              message: 'Firmware xe chưa có giao thức đổi giao diện đồng hồ.',
            );

  DisplaySyncState get state => _state;
  Stream<DisplaySyncState> get stream => _ctrl.stream;

  /// Có được phép HIỂN THỊ nút "Đồng bộ lên xe" không.
  bool get canOfferSync => spec.verified && transport != null;

  void _set(DisplaySyncState s) {
    _state = s;
    if (!_ctrl.isClosed) _ctrl.add(s);
  }

  /// Gửi [payload] lên xe. Không bao giờ báo thành công nếu chưa có ACK.
  Future<DisplaySyncState> send(List<int> payload) async {
    if (!spec.verified || transport == null) {
      _set(
        const DisplaySyncState(
          DisplaySyncStatus.unsupported,
          message:
              'Đã chặn: giao thức đồng bộ đồng hồ xe chưa được xác minh. '
              'Không có dữ liệu nào được gửi.',
        ),
      );
      return _state;
    }
    if (_busy) return _state;
    final t = transport!;
    if (!t.connected) {
      _set(
        const DisplaySyncState(
          DisplaySyncStatus.disconnected,
          message: 'Chưa kết nối xe.',
        ),
      );
      return _state;
    }
    if (payload.isEmpty || spec.maxChunkBytes <= 0) {
      _set(
        const DisplaySyncState(
          DisplaySyncStatus.failed,
          message: 'Dữ liệu rỗng hoặc cấu hình chunk không hợp lệ.',
        ),
      );
      return _state;
    }
    _busy = true;
    try {
      for (var attempt = 0; attempt <= spec.maxRetries; attempt++) {
        if (attempt > 0) {
          _set(
            DisplaySyncState(
              DisplaySyncStatus.recovering,
              message: 'Thử lại lần $attempt…',
              attempt: attempt,
            ),
          );
        }
        try {
          final total = payload.length;
          var sent = 0;
          while (sent < total) {
            if (!t.connected) throw StateError('mất kết nối khi gửi');
            final end = (sent + spec.maxChunkBytes) > total
                ? total
                : sent + spec.maxChunkBytes;
            _set(
              DisplaySyncState(
                DisplaySyncStatus.sending,
                progress: sent / total,
                message: 'Đang gửi $sent/$total byte',
                attempt: attempt,
              ),
            );
            await t.writeChunk(payload.sublist(sent, end));
            sent = end;
            if (spec.maxHz > 0) {
              await Future<void>.delayed(
                Duration(milliseconds: (1000 / spec.maxHz).round()),
              );
            }
          }
          _set(
            DisplaySyncState(
              DisplaySyncStatus.awaitingAck,
              progress: 1,
              message: 'Chờ xe xác nhận…',
              attempt: attempt,
            ),
          );
          final ok = await t.waitAck(spec.ackTimeout);
          if (ok) {
            _set(
              DisplaySyncState(
                DisplaySyncStatus.done,
                progress: 1,
                message: 'Xe đã xác nhận.',
                attempt: attempt,
              ),
            );
            return _state;
          }
          throw StateError('xe không xác nhận (timeout)');
        } catch (e) {
          if (attempt >= spec.maxRetries) {
            _set(
              DisplaySyncState(
                DisplaySyncStatus.failed,
                message: 'Thất bại: $e. Chưa có xác nhận từ xe.',
                attempt: attempt,
              ),
            );
            return _state;
          }
        }
      }
      return _state;
    } finally {
      _busy = false;
    }
  }

  void dispose() => _ctrl.close();
}
