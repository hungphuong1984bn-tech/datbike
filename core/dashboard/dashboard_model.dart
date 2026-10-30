// Mô hình App Dashboard (đồng hồ chạy TRÊN ĐIỆN THOẠI) + bộ phân giải dữ liệu.
//
// THUẦN DART để kiểm thử được. Nguyên tắc dữ liệu:
//  • Giá trị từ xe chỉ hiển thị khi đang kết nối VÀ khung tin mới (< 4 s).
//  • Thiếu dữ liệu → "--" (không bao giờ hiển thị số giả).
//  • Mỗi giá trị gắn nguồn: Xe / Điện thoại (GPS) / Tính toán / Không có.
//  • Đèn pha, ga: giao thức telemetry 45 B KHÔNG cung cấp → luôn "--".

import 'dart:convert';

import '../proto/bike_log.dart';

enum DashTheme { sport, premium, cyber, touring, minimal, night }

enum DashLayout { classic, focus, split }

enum DashWidgetId {
  speed,
  gpsSpeed,
  battery,
  voltage,
  current,
  power,
  odo,
  trip,
  range,
  regen,
  mode,
  indicators,
  sideStand,
  temps,
  headlight,
  bluetooth,
}

enum DashSource { bike, phone, derived, none }

extension DashThemeInfo on DashTheme {
  String get label => switch (this) {
    DashTheme.sport => 'Sport',
    DashTheme.premium => 'Premium',
    DashTheme.cyber => 'Cyber',
    DashTheme.touring => 'Touring',
    DashTheme.minimal => 'Minimal',
    DashTheme.night => 'Night Mode',
  };
  String get blurb => switch (this) {
    DashTheme.sport => 'Tốc độ cực lớn, nhấn đỏ cam.',
    DashTheme.premium => 'Tối giản sang trọng, nhấn vàng đồng.',
    DashTheme.cyber => 'Công nghệ tương lai, nhấn neon.',
    DashTheme.touring => 'Ưu tiên pin, quãng đường, hành trình.',
    DashTheme.minimal => 'Ít chi tiết, dễ quan sát.',
    DashTheme.night => 'Nền đen, giảm chói cho ban đêm.',
  };
}

extension DashWidgetInfo on DashWidgetId {
  String get label => switch (this) {
    DashWidgetId.speed => 'Tốc độ xe',
    DashWidgetId.gpsSpeed => 'Tốc độ GPS',
    DashWidgetId.battery => 'Pin %',
    DashWidgetId.voltage => 'Điện áp',
    DashWidgetId.current => 'Dòng điện',
    DashWidgetId.power => 'Công suất',
    DashWidgetId.odo => 'ODO',
    DashWidgetId.trip => 'Trip',
    DashWidgetId.range => 'Còn chạy được',
    DashWidgetId.regen => 'Regen',
    DashWidgetId.mode => 'Chế độ lái',
    DashWidgetId.indicators => 'Xi nhan',
    DashWidgetId.sideStand => 'Chân chống',
    DashWidgetId.temps => 'Nhiệt độ',
    DashWidgetId.headlight => 'Đèn pha',
    DashWidgetId.bluetooth => 'Bluetooth',
  };
}

extension DashSourceInfo on DashSource {
  String get label => switch (this) {
    DashSource.bike => 'XE',
    DashSource.phone => 'GPS ĐT',
    DashSource.derived => 'TÍNH TOÁN',
    DashSource.none => 'KHÔNG CÓ',
  };
}

class DashValue {
  final String text; // đã định dạng; "--" khi không có
  final String unit;
  final DashSource source;
  final bool available;

  /// Ghi chú ngắn (vd. "ước tính", "xe không cung cấp").
  final String? note;

  /// Chỉ dùng cho xi-nhan: true = đang bật.
  final bool? flagLeft;
  final bool? flagRight;

  const DashValue(
    this.text,
    this.unit,
    this.source, {
    this.available = true,
    this.note,
    this.flagLeft,
    this.flagRight,
  });

  static const DashValue missing = DashValue(
    '--',
    '',
    DashSource.none,
    available: false,
  );
  factory DashValue.unavailable(DashSource s, {String? note}) =>
      DashValue('--', '', s, available: false, note: note);
}

/// Đầu vào cho bộ phân giải — KHÔNG phụ thuộc Riverpod/BLE.
class DashInput {
  final BikeLogMsg? bike;
  final bool bikeLive; // kết nối + khung tin < 4 s
  final bool bleConnected;
  final double? gpsKmh;
  final bool gpsLive;
  final int? regenLevel; // mức đã ĐỌC LẠI từ xe; null = chưa biết
  final double? tripKm;
  final Duration? tripDuration;

  const DashInput({
    required this.bike,
    required this.bikeLive,
    required this.bleConnected,
    this.gpsKmh,
    this.gpsLive = false,
    this.regenLevel,
    this.tripKm,
    this.tripDuration,
  });
}

String _f(double v, int d) => v.toStringAsFixed(d);

/// Phân giải toàn bộ widget. Hàm thuần.
Map<DashWidgetId, DashValue> resolveDash(DashInput i) {
  final b = i.bikeLive ? i.bike : null;
  DashValue fromBike(
    String Function(BikeLogMsg) fmt,
    String unit, {
    String? note,
    bool Function(BikeLogMsg)? valid,
  }) {
    if (b == null) return DashValue.unavailable(DashSource.bike);
    if (valid != null && !valid(b))
      return DashValue.unavailable(DashSource.bike);
    return DashValue(fmt(b), unit, DashSource.bike, note: note);
  }

  final out = <DashWidgetId, DashValue>{};
  out[DashWidgetId.speed] = fromBike(
    (m) => _f(m.speed < 0.5 ? 0 : m.speed, 0),
    'km/h',
    valid: (m) => !m.speed.isNaN && m.speed >= 0 && m.speed < 250,
  );

  out[DashWidgetId.gpsSpeed] = (i.gpsLive && i.gpsKmh != null)
      ? DashValue(
          _f(i.gpsKmh! < 0.5 ? 0 : i.gpsKmh!, 0),
          'km/h',
          DashSource.phone,
        )
      : DashValue.unavailable(DashSource.phone);

  out[DashWidgetId.battery] = fromBike(
    (m) => '${m.percent}',
    '%',
    valid: (m) => m.percent >= 0 && m.percent <= 100,
  );
  out[DashWidgetId.voltage] = fromBike(
    (m) => _f(m.voltage, 1),
    'V',
    valid: (m) => !m.voltage.isNaN && m.voltage > 10 && m.voltage < 130,
  );
  out[DashWidgetId.current] = fromBike(
    (m) => _f(m.phase, 1),
    'A',
    note: 'dòng pha động cơ',
    valid: (m) => !m.phase.isNaN,
  );

  if (b != null &&
      !b.voltage.isNaN &&
      !b.phase.isNaN &&
      b.voltage > 10 &&
      b.voltage < 130) {
    out[DashWidgetId.power] = DashValue(
      _f(b.voltage * b.phase / 1000.0, 2),
      'kW',
      DashSource.derived,
      note: 'V × A',
    );
  } else {
    out[DashWidgetId.power] = DashValue.unavailable(DashSource.derived);
  }

  out[DashWidgetId.odo] = fromBike(
    (m) => _f(m.odo, 1),
    'km',
    valid: (m) => !m.odo.isNaN && m.odo >= 0 && m.odo < 500000,
  );

  out[DashWidgetId.trip] = (i.tripKm != null)
      ? DashValue(
          _f(i.tripKm!, 1),
          'km',
          DashSource.derived,
          note: i.tripDuration == null ? null : _dur(i.tripDuration!),
        )
      : DashValue.unavailable(DashSource.derived);

  out[DashWidgetId.range] = fromBike(
    (m) => _f(m.kmLeft, 0),
    'km',
    note: 'ước tính của xe',
    valid: (m) => !m.kmLeft.isNaN && m.kmLeft >= 0 && m.kmLeft < 500,
  );

  out[DashWidgetId.regen] = (i.bleConnected && i.regenLevel != null)
      ? DashValue(
          '${i.regenLevel}',
          'mức',
          DashSource.bike,
          note: 'đã đọc lại từ xe',
        )
      : DashValue.unavailable(DashSource.bike);

  out[DashWidgetId.mode] = b == null
      ? DashValue.unavailable(DashSource.bike)
      : DashValue(b.drivingModeLabel, '', DashSource.bike);

  out[DashWidgetId.indicators] = b == null
      ? DashValue.unavailable(DashSource.bike)
      : DashValue(
          '${b.left ? '◄' : ''}${b.right ? '►' : ''}'.isEmpty
              ? 'TẮT'
              : '${b.left ? '◄' : ''}${b.right ? '►' : ''}',
          '',
          DashSource.bike,
          flagLeft: b.left,
          flagRight: b.right,
        );

  out[DashWidgetId.sideStand] = b == null
      ? DashValue.unavailable(DashSource.bike)
      : DashValue(b.parking ? 'ĐANG HẠ' : 'ĐÃ GẬP', '', DashSource.bike);

  out[DashWidgetId.temps] = b == null
      ? DashValue.unavailable(DashSource.bike)
      : DashValue(
          'M ${_f(b.motor, 0)}° · E ${_f(b.ecu, 0)}° · B ${_f(b.bmsTemp, 0)}°',
          '°C',
          DashSource.bike,
        );

  // Giao thức telemetry 45 B không có trường đèn pha.
  out[DashWidgetId.headlight] = DashValue.unavailable(
    DashSource.none,
    note: 'xe không cung cấp',
  );

  out[DashWidgetId.bluetooth] = DashValue(
    i.bleConnected ? 'ĐÃ KẾT NỐI' : 'MẤT KẾT NỐI',
    '',
    DashSource.phone,
    note: 'trạng thái liên kết của điện thoại',
  );
  return out;
}

String _dur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '${h}h$m' : '${d.inMinutes}p';
}

// ======================= Profile =======================

class DashProfile {
  final String id;
  final String name;
  final DashTheme theme;
  final DashLayout layout;
  final int? accent; // ARGB; null = màu theo theme
  final List<DashWidgetId> widgets;
  final bool alwaysOn; // giữ sáng màn hình khi mở đồng hồ

  const DashProfile({
    required this.id,
    required this.name,
    this.theme = DashTheme.sport,
    this.layout = DashLayout.classic,
    this.accent,
    this.widgets = defaultWidgets,
    this.alwaysOn = true,
  });

  static const List<DashWidgetId> defaultWidgets = [
    DashWidgetId.speed,
    DashWidgetId.battery,
    DashWidgetId.range,
    DashWidgetId.odo,
    DashWidgetId.trip,
    DashWidgetId.regen,
    DashWidgetId.mode,
    DashWidgetId.indicators,
    DashWidgetId.bluetooth,
  ];

  DashProfile copyWith({
    String? name,
    DashTheme? theme,
    DashLayout? layout,
    Object? accent = _keep,
    List<DashWidgetId>? widgets,
    bool? alwaysOn,
  }) => DashProfile(
    id: id,
    name: name ?? this.name,
    theme: theme ?? this.theme,
    layout: layout ?? this.layout,
    accent: identical(accent, _keep) ? this.accent : accent as int?,
    widgets: widgets ?? this.widgets,
    alwaysOn: alwaysOn ?? this.alwaysOn,
  );

  static const Object _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'theme': theme.name,
    'layout': layout.name,
    'accent': accent,
    'widgets': widgets.map((w) => w.name).toList(),
    'alwaysOn': alwaysOn,
  };

  /// Giải mã chịu lỗi: giá trị lạ/thiếu → mặc định, không ném lỗi.
  static DashProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    T pick<T extends Enum>(List<T> all, Object? v, T d) {
      for (final e in all) {
        if (e.name == v) return e;
      }
      return d;
    }

    final ws = <DashWidgetId>[];
    final rawW = j['widgets'];
    if (rawW is List) {
      for (final x in rawW) {
        for (final w in DashWidgetId.values) {
          if (w.name == x && !ws.contains(w)) ws.add(w);
        }
      }
    }
    return DashProfile(
      id: id,
      name: (j['name'] is String && (j['name'] as String).trim().isNotEmpty)
          ? j['name'] as String
          : 'Cấu hình',
      theme: pick(DashTheme.values, j['theme'], DashTheme.sport),
      layout: pick(DashLayout.values, j['layout'], DashLayout.classic),
      accent: j['accent'] is int ? j['accent'] as int : null,
      widgets: ws.isEmpty ? defaultWidgets : ws,
      alwaysOn: j['alwaysOn'] is bool ? j['alwaysOn'] as bool : true,
    );
  }
}

class DashStoreData {
  final List<DashProfile> profiles;
  final String activeId;
  const DashStoreData(this.profiles, this.activeId);

  DashProfile get active => profiles.firstWhere(
    (p) => p.id == activeId,
    orElse: () => profiles.first,
  );

  String encode() => jsonEncode({
    'active': activeId,
    'profiles': profiles.map((p) => p.toJson()).toList(),
  });

  static DashStoreData seed() {
    const p = DashProfile(id: 'default', name: 'Mặc định');
    return const DashStoreData([p], 'default');
  }

  /// Khôi phục từ chuỗi đã lưu; hỏng/thiếu → seed (không mất app).
  static DashStoreData decode(String? raw) {
    if (raw == null || raw.isEmpty) return seed();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return seed();
      final list = <DashProfile>[];
      final seen = <String>{};
      if (j['profiles'] is List) {
        for (final x in j['profiles'] as List) {
          final p = DashProfile.fromJson(x);
          if (p != null && seen.add(p.id)) list.add(p);
        }
      }
      if (list.isEmpty) return seed();
      final a = j['active'];
      final active = (a is String && seen.contains(a)) ? a : list.first.id;
      return DashStoreData(list, active);
    } catch (_) {
      return seed();
    }
  }
}
