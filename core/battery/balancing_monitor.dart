// Balancing Monitor — GIÁM SÁT trạng thái cân bằng do BMS tự báo.
//
// Giới hạn đã xác minh từ giao thức hiện có (docs/BLE_PROTOCOL_SPEC.md):
//  • BATTERY_LOG_CHAR (84c7be0b…) chỉ có quyền Read. Không có đặc tính nào để ghi
//    lệnh điều khiển cân bằng → module này KHÔNG và không thể gửi lệnh tới BMS.
//  • Trường `balancing` là một số nguyên BMS gửi lên; ý nghĩa từng bit (cell nào
//    đang cân bằng) và kiểu cân bằng (thụ động/chủ động) KHÔNG được tài liệu hoá.
//    Vì vậy app chỉ coi `balancing != 0` là "BMS báo đang cân bằng" ở mức PACK,
//    không gán cho từng cell và không suy đoán kiểu cân bằng.
//  • Không có trường tiến trình cân bằng → không hiển thị phần trăm tiến trình;
//    chỉ hiển thị ΔV trước/sau (số đo thật) và mức ΔV đã giảm.

import 'battery_config.dart';
import 'cell_model.dart';
import 'cell_protection_engine.dart' show AlertSeverity;

enum BalancingState {
  unknown('Chưa có dữ liệu'),
  off('OFF'),
  on('ON');

  final String label;
  const BalancingState(this.label);
}

/// Kiểu cân bằng. Hiện giao thức không cung cấp thông tin này.
enum BalancingMethod {
  unverified('Chưa xác minh',
      'BMS không công bố kiểu cân bằng (thụ động hay chủ động) qua giao thức hiện có. '
          'Ứng dụng không suy đoán để tránh hiển thị sai.');

  final String label;
  final String explanation;
  const BalancingMethod(this.label, this.explanation);
}

enum BalancingEndReason { completed, linkLost, dataInvalid }

class BalancingEvent {
  final DateTime start;
  final DateTime? end;
  final BalancingEndReason? endReason;

  /// ΔV (mV) tại thời điểm BMS bắt đầu báo cân bằng. null nếu lúc đó không đủ cell.
  final double? deltaBeforeMv;

  /// ΔV (mV) tại thời điểm kết thúc (hoặc mới nhất nếu đang diễn ra).
  final double? deltaAfterMv;
  final int? maxCellIndexAtStart;
  final int? minCellIndexAtStart;

  const BalancingEvent({
    required this.start,
    this.end,
    this.endReason,
    this.deltaBeforeMv,
    this.deltaAfterMv,
    this.maxCellIndexAtStart,
    this.minCellIndexAtStart,
  });

  bool get isOngoing => end == null;

  Duration durationUntil(DateTime now) => (end ?? now).difference(start);

  /// Mức ΔV đã giảm (mV), dương = ΔV giảm. null nếu thiếu số liệu.
  double? get deltaReductionMv =>
      (deltaBeforeMv != null && deltaAfterMv != null)
          ? deltaBeforeMv! - deltaAfterMv!
          : null;

  BalancingEvent copyWith({
    DateTime? end,
    BalancingEndReason? endReason,
    double? deltaAfterMv,
  }) =>
      BalancingEvent(
        start: start,
        end: end ?? this.end,
        endReason: endReason ?? this.endReason,
        deltaBeforeMv: deltaBeforeMv,
        deltaAfterMv: deltaAfterMv ?? this.deltaAfterMv,
        maxCellIndexAtStart: maxCellIndexAtStart,
        minCellIndexAtStart: minCellIndexAtStart,
      );
}

/// Theo dõi chuyển trạng thái cờ cân bằng qua từng gói BMS và ghi nhật ký.
/// Không tạo sự kiện nếu không có gói BMS thật báo cờ khác 0.
class BalancingMonitor {
  static const int maxLog = 50;

  final List<BalancingEvent> _log = <BalancingEvent>[]; // cũ → mới
  BalancingEvent? _open;
  BalancingState _state = BalancingState.unknown;

  BalancingState get state => _state;
  BalancingEvent? get ongoing => _open;

  /// Nhật ký mới nhất trước, gồm cả sự kiện đang diễn ra.
  List<BalancingEvent> get events {
    final out = <BalancingEvent>[];
    if (_open != null) out.add(_open!);
    out.addAll(_log.reversed);
    return List<BalancingEvent>.unmodifiable(out);
  }

  /// Gọi với mỗi gói BMS thật mới.
  void onPack(PackSnapshot pack) {
    final on = pack.isBalancingReported;
    _state = on ? BalancingState.on : BalancingState.off;
    final delta = pack.validCount >= 2 ? pack.deltaMv : null;

    if (on) {
      if (_open == null) {
        _open = BalancingEvent(
          start: pack.receivedAt,
          deltaBeforeMv: delta,
          deltaAfterMv: delta,
          maxCellIndexAtStart: pack.maxIndex >= 0 ? pack.maxIndex : null,
          minCellIndexAtStart: pack.minIndex >= 0 ? pack.minIndex : null,
        );
      } else if (delta != null) {
        _open = _open!.copyWith(deltaAfterMv: delta);
      }
    } else if (_open != null) {
      _close(pack.receivedAt, BalancingEndReason.completed, delta);
    }
  }

  /// Mất kết nối hoặc dữ liệu hết hiệu lực: kết thúc sự kiện đang mở nhưng đánh
  /// dấu là bị gián đoạn, KHÔNG coi là "cân bằng hoàn tất".
  void onLinkLost(DateTime at) {
    if (_open != null) {
      _close(at, BalancingEndReason.linkLost, null);
    }
    _state = BalancingState.unknown;
  }

  void clear() {
    _log.clear();
    _open = null;
    _state = BalancingState.unknown;
  }

  void _close(DateTime at, BalancingEndReason reason, double? deltaAfter) {
    final done = _open!.copyWith(
      end: at,
      endReason: reason,
      deltaAfterMv: deltaAfter,
    );
    _open = null;
    _log.add(done);
    if (_log.length > maxLog) _log.removeRange(0, _log.length - maxLog);
  }
}

class BalancingAdvice {
  final String headline;
  final List<String> details;
  final AlertSeverity level;
  const BalancingAdvice(this.headline, this.details, this.level);
}

/// Khuyến nghị dựa trên ΔV thực và ngưỡng cấu hình — chỉ là gợi ý để BMS tự thực hiện.
class BalancingAdvisor {
  BalancingAdvisor._();

  static BalancingAdvice advise({
    required PackSnapshot? pack,
    required BatteryConfig cfg,
    required BmsFreshness freshness,
  }) {
    if (pack == null || freshness == BmsFreshness.none) {
      return const BalancingAdvice(
        'Chưa có dữ liệu cell để đánh giá',
        ['Kết nối xe và chờ gói BMS đầu tiên.'],
        AlertSeverity.normal,
      );
    }
    if (freshness != BmsFreshness.live) {
      return const BalancingAdvice(
        'Dữ liệu không còn trực tiếp',
        ['Không đưa khuyến nghị dựa trên số liệu cũ. Kết nối lại để đánh giá.'],
        AlertSeverity.normal,
      );
    }
    if (pack.validCount < 2) {
      return const BalancingAdvice(
        'Không đủ cell hợp lệ để tính ΔV',
        ['BMS cần gửi tối thiểu 2 cell hợp lệ.'],
        AlertSeverity.normal,
      );
    }
    final d = pack.deltaMv;
    const footnote =
        'Việc cân bằng do BMS tự thực hiện; ứng dụng không điều khiển cân bằng. '
        'Thời điểm BMS cân bằng (ví dụ cuối quá trình sạc) tuỳ thiết kế BMS — hãy đối chiếu tài liệu nhà sản xuất.';
    if (d >= cfg.deltaCritMv) {
      return BalancingAdvice(
        'ΔV ${d.toStringAsFixed(0)} mV — nên kiểm tra pin',
        [
          'Sạc đầy và giữ cắm sạc thêm để BMS có thời gian cân bằng, rồi đo lại khi pin nghỉ.',
          'Nếu ΔV vẫn không giảm sau vài chu kỳ sạc, đưa xe đến trạm dịch vụ kiểm tra cell.',
          footnote,
        ],
        AlertSeverity.critical,
      );
    }
    if (d >= cfg.deltaWarnMv) {
      return BalancingAdvice(
        'ΔV ${d.toStringAsFixed(0)} mV — nên sạc đầy để cân bằng',
        [
          'Sạc đầy ít nhất một lần và giữ cắm sạc đến khi BMS hoàn tất.',
          'Theo dõi ΔV sau khi pin nghỉ; nếu vẫn cao hãy kiểm tra pin.',
          footnote,
        ],
        AlertSeverity.warning,
      );
    }
    return BalancingAdvice(
      'ΔV ${d.toStringAsFixed(0)} mV — các cell đồng đều',
      [
        if (pack.isBalancingReported)
          'BMS đang báo cân bằng; không cần can thiệp.'
        else
          'Không cần hành động.',
        footnote,
      ],
      AlertSeverity.normal,
    );
  }
}
