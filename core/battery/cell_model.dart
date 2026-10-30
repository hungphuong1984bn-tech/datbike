// Cell Data Model — mô hình dữ liệu bất biến cho từng cell và toàn bộ pack.
// Chỉ chứa dữ liệu lấy từ gói BMS thực (BatteryLogMsg) và các đại lượng tính từ
// chúng; không có bất kỳ giá trị giả lập nào.

enum CellStatus {
  ok('Bình thường'),
  warning('Cảnh báo'),
  critical('Nghiêm trọng'),
  invalid('Dữ liệu lỗi');

  final String label;
  const CellStatus(this.label);
}

/// Độ tươi của dữ liệu BMS.
enum BmsFreshness {
  /// Gói BMS mới nhận trong ngưỡng cho phép, đang kết nối.
  live('Trực tiếp'),

  /// Đang kết nối nhưng gói cuối đã cũ.
  stale('Dữ liệu cũ'),

  /// Đã mất kết nối BLE — dữ liệu còn lại chỉ là bản cuối cùng.
  lost('Mất kết nối'),

  /// Chưa từng nhận gói BMS.
  none('Chưa có dữ liệu');

  final String label;
  const BmsFreshness(this.label);

  static const Duration defaultLiveWindow = Duration(seconds: 8);

  static BmsFreshness evaluate({
    required DateTime? receivedAt,
    required DateTime now,
    required bool connected,
    Duration liveWithin = defaultLiveWindow,
  }) {
    if (receivedAt == null) return BmsFreshness.none;
    if (!connected) return BmsFreshness.lost;
    final age = now.difference(receivedAt);
    return age <= liveWithin ? BmsFreshness.live : BmsFreshness.stale;
  }
}

class CellSnapshot {
  /// Chỉ số 0-based trong mảng cellVols của BMS.
  final int index;

  /// Điện áp nhận được (V). Chỉ có nghĩa khi [valid] = true.
  final double voltage;
  final bool valid;

  /// Độ lệch so với điện áp trung bình các cell hợp lệ (mV).
  final double deviationMv;
  final CellStatus status;
  final bool isMax;
  final bool isMin;

  const CellSnapshot({
    required this.index,
    required this.voltage,
    required this.valid,
    required this.deviationMv,
    required this.status,
    required this.isMax,
    required this.isMin,
  });

  int get number => index + 1;
  String get label => 'Cell ${number.toString().padLeft(2, '0')}';
  double get millivolts => voltage * 1000.0;

  @override
  bool operator ==(Object other) =>
      other is CellSnapshot &&
      other.index == index &&
      other.voltage == voltage &&
      other.valid == valid &&
      other.deviationMv == deviationMv &&
      other.status == status &&
      other.isMax == isMax &&
      other.isMin == isMin;

  @override
  int get hashCode =>
      Object.hash(index, voltage, valid, deviationMv, status, isMax, isMin);
}

class PackSnapshot {
  final DateTime receivedAt;
  final List<CellSnapshot> cells;

  // ── Thống kê tính từ các cell hợp lệ (CALCULATED từ số đo) ──
  final int validCount;
  final double vMax;
  final double vMin;
  final double vAvg;
  final int maxIndex; // -1 nếu không có
  final int minIndex;
  final double deltaMv;
  final double sumCellsV;

  // ── Số đo trực tiếp từ BMS (MEASURED) ──
  final double packVoltage;
  final double current;
  final bool chargeFlag;
  final bool dischargeFlag;
  final int balancingRaw;
  final int protectionRaw;
  final List<int> protections;
  final int errorCode;
  final List<double> ntcs;
  final double resistorMo;
  final double fetTemp;
  final double socPercent;
  final double cycles;

  const PackSnapshot({
    required this.receivedAt,
    required this.cells,
    required this.validCount,
    required this.vMax,
    required this.vMin,
    required this.vAvg,
    required this.maxIndex,
    required this.minIndex,
    required this.deltaMv,
    required this.sumCellsV,
    required this.packVoltage,
    required this.current,
    required this.chargeFlag,
    required this.dischargeFlag,
    required this.balancingRaw,
    required this.protectionRaw,
    required this.protections,
    required this.errorCode,
    required this.ntcs,
    required this.resistorMo,
    required this.fetTemp,
    required this.socPercent,
    required this.cycles,
  });

  int get cellCount => cells.length;
  bool get hasCells => cells.isNotEmpty;
  bool get hasStats => validCount > 0;
  bool get isBalancingReported => balancingRaw != 0;

  int get abnormalCount =>
      cells.where((c) => c.status == CellStatus.warning || c.status == CellStatus.critical || c.status == CellStatus.invalid).length;

  CellSnapshot? cellAt(int index) =>
      index >= 0 && index < cells.length ? cells[index] : null;
}
