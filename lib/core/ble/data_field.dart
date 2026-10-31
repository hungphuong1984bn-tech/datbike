// Trường dữ liệu có metadata — module THUẦN Dart.
//
// Mỗi giá trị đọc từ xe mang theo: giá trị, đơn vị, nguồn, thời điểm nhận,
// trạng thái hợp lệ và độ mới. UI dùng [DataField.freshness] để quyết định có
// được trình bày như "trực tiếp" hay phải gắn nhãn "cũ"/"chưa có".
//
// QUY TẮC TRUNG THỰC:
//  • Nguồn [FieldSource.cache] KHÔNG BAO GIỜ được coi là trực tiếp.
//  • Proto3 không phân biệt "trường vắng" và "giá trị 0". Với các đại lượng mà
//    0 không thể là số đo thật khi xe đang gửi dữ liệu (điện áp pack, nhiệt độ
//    chính xác 0,0), 0 được đánh dấu KHÔNG hợp lệ thay vì hiển thị như số đo.
//    Đây là chính sách hiển thị của ứng dụng, không phải đặc tả của xe.
//  • Đơn vị lấy từ chú thích trong decoder (bike_log.dart); trường nào không có
//    đơn vị rõ ràng thì không đưa vào đây.

import '../proto/bike_log.dart';

/// Nguồn của một giá trị.
enum FieldSource {
  /// Khung dashboard (telemetry) đọc từ xe qua BLE.
  bleDashboard,

  /// Log BMS đọc từ xe qua BLE.
  bleBatteryLog,

  /// Tính từ các trường khác của cùng khung (ví dụ chênh lệch cell).
  derived,

  /// Giá trị lưu từ lần trước (không phải dữ liệu trực tiếp).
  cache,
}

extension FieldSourceX on FieldSource {
  String get label {
    switch (this) {
      case FieldSource.bleDashboard:
        return 'BLE · dashboard';
      case FieldSource.bleBatteryLog:
        return 'BLE · log BMS';
      case FieldSource.derived:
        return 'Tính từ dữ liệu BLE';
      case FieldSource.cache:
        return 'Bộ nhớ đệm';
    }
  }
}

/// Độ mới của giá trị tại một thời điểm.
enum Freshness {
  /// Chưa có giá trị.
  none,

  /// Nhận trong cửa sổ "mới".
  live,

  /// Nhận đã lâu hơn cửa sổ "mới".
  stale,

  /// Đến từ bộ nhớ đệm — không bao giờ là trực tiếp.
  cached,
}

extension FreshnessX on Freshness {
  String get label {
    switch (this) {
      case Freshness.none:
        return 'Chưa có dữ liệu';
      case Freshness.live:
        return 'Mới';
      case Freshness.stale:
        return 'Dữ liệu cũ';
      case Freshness.cached:
        return 'Từ bộ nhớ đệm';
    }
  }
}

class DataField<T> {
  const DataField({
    required this.value,
    required this.unit,
    required this.source,
    required this.receivedAt,
    this.valid = true,
    this.invalidReason,
  });

  /// Trường chưa có giá trị.
  const DataField.missing({required this.unit, required this.source})
      : value = null,
        receivedAt = null,
        valid = false,
        invalidReason = 'Chưa nhận được';

  final T? value;
  final String unit;
  final FieldSource source;
  final DateTime? receivedAt;
  final bool valid;
  final String? invalidReason;

  bool get hasValue => value != null;

  Freshness freshness(DateTime now, Duration window) {
    if (value == null || receivedAt == null) return Freshness.none;
    if (source == FieldSource.cache) return Freshness.cached;
    return now.difference(receivedAt!) <= window ? Freshness.live : Freshness.stale;
  }

  /// true khi giá trị hợp lệ VÀ mới. Chỉ khi true mới được dùng để ra quyết
  /// định hoặc hiển thị như số liệu trực tiếp.
  bool isLive(DateTime now, Duration window) =>
      valid && freshness(now, window) == Freshness.live;

  /// Giá trị chỉ khi đang trực tiếp; ngược lại null.
  T? liveValue(DateTime now, Duration window) =>
      isLive(now, window) ? value : null;

  /// Tuổi của giá trị (null nếu chưa có).
  Duration? age(DateTime now) =>
      receivedAt == null ? null : now.difference(receivedAt!);

  Map<String, Object?> toJson(DateTime now, Duration window) => {
        'value': value,
        'unit': unit,
        'source': source.name,
        'receivedAt': receivedAt?.toIso8601String(),
        'valid': valid,
        if (invalidReason != null) 'invalidReason': invalidReason,
        'freshness': freshness(now, window).name,
      };
}

/// Cửa sổ "mới" mặc định cho dữ liệu dashboard (khớp cửa sổ an toàn 4 giây của
/// BleController; dashboard được đọc chu kỳ ~700 ms).
const Duration kDashboardFreshWindow = Duration(seconds: 4);

/// Log BMS được đọc thưa hơn dashboard nên dùng cửa sổ dài hơn. Đây là giá trị
/// hiển thị do ứng dụng chọn, không phải chu kỳ do nhà sản xuất quy định.
const Duration kBatteryFreshWindow = Duration(seconds: 15);

/// Các trường telemetry xe có đơn vị rõ ràng trong decoder.
class TelemetryFields {
  const TelemetryFields({
    required this.speed,
    required this.packVoltage,
    required this.packPercent,
    required this.phaseCurrent,
    required this.ecuTemp,
    required this.motorTemp,
    required this.bmsTemp,
    required this.odometer,
    required this.rangeLeft,
  });

  final DataField<double> speed; // km/h
  final DataField<double> packVoltage; // V
  final DataField<double> packPercent; // %
  final DataField<double> phaseCurrent; // A (dòng pha, không phải dòng pin)
  final DataField<double> ecuTemp; // °C
  final DataField<double> motorTemp; // °C
  final DataField<double> bmsTemp; // °C
  final DataField<double> odometer; // km
  final DataField<double> rangeLeft; // km (do xe tự báo)

  static const TelemetryFields empty = TelemetryFields(
    speed: DataField.missing(unit: 'km/h', source: FieldSource.bleDashboard),
    packVoltage: DataField.missing(unit: 'V', source: FieldSource.bleDashboard),
    packPercent: DataField.missing(unit: '%', source: FieldSource.bleDashboard),
    phaseCurrent: DataField.missing(unit: 'A', source: FieldSource.bleDashboard),
    ecuTemp: DataField.missing(unit: '°C', source: FieldSource.bleDashboard),
    motorTemp: DataField.missing(unit: '°C', source: FieldSource.bleDashboard),
    bmsTemp: DataField.missing(unit: '°C', source: FieldSource.bleDashboard),
    odometer: DataField.missing(unit: 'km', source: FieldSource.bleDashboard),
    rangeLeft: DataField.missing(unit: 'km', source: FieldSource.bleDashboard),
  );

  /// Dựng từ một khung dashboard đã giải mã, nhận lúc [at].
  factory TelemetryFields.fromBike(BikeLogMsg m, DateTime at,
      {FieldSource source = FieldSource.bleDashboard}) {
    DataField<double> f(double v, String unit,
            {bool Function(double)? ok, String? why}) =>
        DataField<double>(
          value: v,
          unit: unit,
          source: source,
          receivedAt: at,
          valid: ok == null ? v.isFinite : (v.isFinite && ok(v)),
          invalidReason: (ok != null && !(v.isFinite && ok(v))) ? why : null,
        );

    const zeroNote = 'Giá trị 0 — xe có thể không gửi trường này';
    return TelemetryFields(
      speed: f(m.speed, 'km/h', ok: (v) => v >= 0, why: 'Tốc độ âm'),
      packVoltage: f(m.voltage, 'V', ok: (v) => v > 0, why: zeroNote),
      packPercent: f(m.percent.toDouble(), '%',
          ok: (v) => v >= 0 && v <= 100, why: 'Ngoài khoảng 0–100%'),
      phaseCurrent: f(m.phase, 'A'),
      ecuTemp: f(m.ecu, '°C', ok: (v) => v != 0, why: zeroNote),
      motorTemp: f(m.motor, '°C', ok: (v) => v != 0, why: zeroNote),
      bmsTemp: f(m.bmsTemp, '°C', ok: (v) => v != 0, why: zeroNote),
      odometer: f(m.odo, 'km', ok: (v) => v >= 0, why: 'Số ODO âm'),
      rangeLeft: f(m.kmLeft, 'km', ok: (v) => v >= 0, why: 'Quãng đường âm'),
    );
  }

  List<MapEntry<String, DataField<double>>> get entries => [
        MapEntry('Tốc độ', speed),
        MapEntry('Điện áp pack', packVoltage),
        MapEntry('Dung lượng pin (SOC)', packPercent),
        MapEntry('Dòng pha', phaseCurrent),
        MapEntry('Nhiệt độ ECU', ecuTemp),
        MapEntry('Nhiệt độ động cơ', motorTemp),
        MapEntry('Nhiệt độ BMS (dashboard)', bmsTemp),
        MapEntry('ODO', odometer),
        MapEntry('Quãng đường còn lại (xe báo)', rangeLeft),
      ];
}

/// Các trường log BMS có đơn vị rõ ràng trong decoder.
class BatteryFields {
  const BatteryFields({
    required this.packVoltage,
    required this.packCurrent,
    required this.cellCount,
    required this.cellMaxV,
    required this.cellMinV,
    required this.deltaMv,
  });

  final DataField<double> packVoltage; // V
  final DataField<double> packCurrent; // A
  final DataField<double> cellCount; // cell
  final DataField<double> cellMaxV; // V
  final DataField<double> cellMinV; // V
  final DataField<double> deltaMv; // mV, tính từ max−min của các cell đã nhận

  static const BatteryFields empty = BatteryFields(
    packVoltage: DataField.missing(unit: 'V', source: FieldSource.bleBatteryLog),
    packCurrent: DataField.missing(unit: 'A', source: FieldSource.bleBatteryLog),
    cellCount: DataField.missing(unit: 'cell', source: FieldSource.bleBatteryLog),
    cellMaxV: DataField.missing(unit: 'V', source: FieldSource.bleBatteryLog),
    cellMinV: DataField.missing(unit: 'V', source: FieldSource.bleBatteryLog),
    deltaMv: DataField.missing(unit: 'mV', source: FieldSource.derived),
  );

  factory BatteryFields.fromMsg(BatteryLogMsg m, DateTime at,
      {FieldSource source = FieldSource.bleBatteryLog}) {
    final hasCells = m.cellVols.isNotEmpty;
    DataField<double> cellField(double v, String unit, FieldSource s,
            {bool allowZero = false}) =>
        DataField<double>(
          value: hasCells ? v : null,
          unit: unit,
          source: s,
          receivedAt: hasCells ? at : null,
          valid: hasCells && v.isFinite && (allowZero ? v >= 0 : v > 0),
          invalidReason: hasCells ? null : 'Không có điện áp cell',
        );
    return BatteryFields(
      packVoltage: DataField<double>(
        value: m.voltage,
        unit: 'V',
        source: source,
        receivedAt: at,
        valid: m.voltage.isFinite && m.voltage > 0,
        invalidReason: m.voltage > 0 ? null : 'Giá trị 0 — BMS có thể không gửi trường này',
      ),
      packCurrent: DataField<double>(
        value: m.current,
        unit: 'A',
        source: source,
        receivedAt: at,
        valid: m.current.isFinite,
      ),
      cellCount: DataField<double>(
        value: m.cellVols.length.toDouble(),
        unit: 'cell',
        source: source,
        receivedAt: at,
        valid: hasCells,
        invalidReason: hasCells ? null : 'Không có điện áp cell',
      ),
      cellMaxV: cellField(m.maxCellVol, 'V', source),
      cellMinV: cellField(m.minCellVol, 'V', source),
      deltaMv: cellField(m.deltaCellMv, 'mV', FieldSource.derived, allowZero: true),
    );
  }

  List<MapEntry<String, DataField<double>>> get entries => [
        MapEntry('Điện áp pack (BMS)', packVoltage),
        MapEntry('Dòng pack (BMS)', packCurrent),
        MapEntry('Số cell', cellCount),
        MapEntry('Cell cao nhất', cellMaxV),
        MapEntry('Cell thấp nhất', cellMinV),
        MapEntry('Chênh lệch cell', deltaMv),
      ];
}
