// Lịch sử pin bền vững (Giai đoạn 2F).
//
// Khác BatteryHistory (chỉ RAM, vài phút/giờ), lớp này ghi MẪU THƯA ra file JSONL
// để xem xu hướng theo ngày/tuần/tháng. Quy tắc:
//  • Chỉ ghi từ gói BMS thật còn mới (hub gọi khi trạng thái "live"); không ghi cache.
//  • Trường BMS không gửi hoặc không hợp lệ được lưu là null — không điền số giả.
//  • Mọi lỗi I/O đều được nuốt (không làm hỏng luồng BLE) và trả về false/rỗng.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'cell_model.dart';
import 'cell_protection_engine.dart' show CellProtectionEngine;

/// Một mẫu lịch sử pin. Trường null = BMS không cung cấp hoặc không hợp lệ.
class BatteryHistoryRecord {
  final DateTime at;
  final double? soc; // %
  final double? packV; // V
  final double? currentA; // A (dấu theo BMS, chưa xác minh)
  final double? tempC; // °C — NTC cao nhất
  final double? cellMaxV; // V
  final double? cellMinV; // V
  final double? deltaMv; // mV

  const BatteryHistoryRecord({
    required this.at,
    this.soc,
    this.packV,
    this.currentA,
    this.tempC,
    this.cellMaxV,
    this.cellMinV,
    this.deltaMv,
  });

  static double? _pos(double v) => v.isFinite && v > 0 ? v : null;

  /// Tạo mẫu từ gói BMS thật. Giá trị 0/không hữu hạn coi là "không có".
  factory BatteryHistoryRecord.fromSnapshot(PackSnapshot s) {
    double? temp;
    for (final t in s.ntcs) {
      // Bỏ NTC ngoài dải hợp lý (hở mạch/chập/dữ liệu lỗi).
      if (CellProtectionEngine.isPlausibleTemp(t) && (temp == null || t > temp)) temp = t;
    }
    return BatteryHistoryRecord(
      at: s.receivedAt,
      soc: s.socPercent > 0 && s.socPercent <= 100 ? s.socPercent : null,
      packV: _pos(s.packVoltage),
      currentA: s.current.isFinite ? s.current : null,
      tempC: temp,
      cellMaxV: s.validCount >= 1 ? _pos(s.vMax) : null,
      cellMinV: s.validCount >= 1 ? _pos(s.vMin) : null,
      deltaMv: s.validCount >= 2 && s.deltaMv.isFinite ? s.deltaMv : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        't': at.millisecondsSinceEpoch,
        if (soc != null) 'soc': soc,
        if (packV != null) 'v': packV,
        if (currentA != null) 'i': currentA,
        if (tempC != null) 'tc': tempC,
        if (cellMaxV != null) 'cmax': cellMaxV,
        if (cellMinV != null) 'cmin': cellMinV,
        if (deltaMv != null) 'dmv': deltaMv,
      };

  /// Trả về null nếu dòng hỏng (thiếu/sai thời gian).
  static BatteryHistoryRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! int || t <= 0) return null;
    double? d(String k) {
      final v = j[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    return BatteryHistoryRecord(
      at: DateTime.fromMillisecondsSinceEpoch(t),
      soc: d('soc'),
      packV: d('v'),
      currentA: d('i'),
      tempC: d('tc'),
      cellMaxV: d('cmax'),
      cellMinV: d('cmin'),
      deltaMv: d('dmv'),
    );
  }
}

/// Quyết định có nên ghi một mẫu mới hay không (mẫu thưa theo thời gian).
class BatteryHistorySampler {
  final Duration interval;
  DateTime? _last;
  BatteryHistorySampler({this.interval = const Duration(minutes: 5)});

  bool shouldRecord(DateTime at) {
    final last = _last;
    if (last != null && !at.isAfter(last)) return false;
    if (last != null && at.difference(last) < interval) return false;
    _last = at;
    return true;
  }
}

enum HistoryRange {
  day('Ngày', 24, Duration(hours: 1)),
  week('Tuần', 7, Duration(days: 1)),
  month('Tháng', 30, Duration(days: 1));

  final String label;
  final int buckets;
  final Duration step;
  const HistoryRange(this.label, this.buckets, this.step);
}

/// Thống kê một khoảng thời gian. Mọi trường null nếu khoảng đó không có dữ liệu.
class HistoryBucket {
  final DateTime start;
  final int count;
  final double? socAvg;
  final double? packVAvg;
  final double? currentAvg;
  final double? tempMax;
  final double? deltaAvgMv;
  final double? deltaMaxMv;
  final double? cellMaxV;
  final double? cellMinV;

  const HistoryBucket({
    required this.start,
    required this.count,
    this.socAvg,
    this.packVAvg,
    this.currentAvg,
    this.tempMax,
    this.deltaAvgMv,
    this.deltaMaxMv,
    this.cellMaxV,
    this.cellMinV,
  });

  bool get hasData => count > 0;
}

class _Avg {
  double _sum = 0;
  int _n = 0;
  void add(double? v) {
    if (v == null) return;
    _sum += v;
    _n++;
  }

  double? get value => _n == 0 ? null : _sum / _n;
}

class BatteryHistoryAggregator {
  BatteryHistoryAggregator._();

  /// Gom [records] thành [range.buckets] khoảng liên tiếp kết thúc ở [now].
  /// Ngày: theo giờ; tuần/tháng: theo ngày lịch (giờ địa phương). Hàm thuần.
  static List<HistoryBucket> aggregate(
    List<BatteryHistoryRecord> records,
    HistoryRange range,
    DateTime now,
  ) {
    final n = range.buckets;
    final DateTime lastStart = range == HistoryRange.day
        ? DateTime(now.year, now.month, now.day, now.hour)
        : DateTime(now.year, now.month, now.day);
    DateTime startOf(int i) {
      final back = n - 1 - i;
      return range == HistoryRange.day
          ? DateTime(lastStart.year, lastStart.month, lastStart.day, lastStart.hour - back)
          : DateTime(lastStart.year, lastStart.month, lastStart.day - back);
    }

    final starts = List<DateTime>.generate(n, startOf);
    final endExclusive = range == HistoryRange.day
        ? DateTime(lastStart.year, lastStart.month, lastStart.day, lastStart.hour + 1)
        : DateTime(lastStart.year, lastStart.month, lastStart.day + 1);

    final groups = List<List<BatteryHistoryRecord>>.generate(n, (_) => <BatteryHistoryRecord>[]);
    final firstMs = starts.first.millisecondsSinceEpoch;
    final endMs = endExclusive.millisecondsSinceEpoch;
    final stepMs = range.step.inMilliseconds;
    for (final r in records) {
      final ms = r.at.millisecondsSinceEpoch;
      if (ms < firstMs || ms >= endMs) continue;
      final idx = math.min(n - 1, ((ms - firstMs) / stepMs).floor());
      groups[idx].add(r);
    }

    return List<HistoryBucket>.generate(n, (i) {
      final g = groups[i];
      if (g.isEmpty) return HistoryBucket(start: starts[i], count: 0);
      final soc = _Avg(), v = _Avg(), cur = _Avg(), dAvg = _Avg();
      double? tMax, dMax, cMax, cMin;
      for (final r in g) {
        soc.add(r.soc);
        v.add(r.packV);
        cur.add(r.currentA);
        dAvg.add(r.deltaMv);
        if (r.tempC != null) tMax = tMax == null ? r.tempC : math.max(tMax, r.tempC!);
        if (r.deltaMv != null) dMax = dMax == null ? r.deltaMv : math.max(dMax, r.deltaMv!);
        if (r.cellMaxV != null) cMax = cMax == null ? r.cellMaxV : math.max(cMax, r.cellMaxV!);
        if (r.cellMinV != null) cMin = cMin == null ? r.cellMinV : math.min(cMin, r.cellMinV!);
      }
      return HistoryBucket(
        start: starts[i],
        count: g.length,
        socAvg: soc.value,
        packVAvg: v.value,
        currentAvg: cur.value,
        tempMax: tMax,
        deltaAvgMv: dAvg.value,
        deltaMaxMv: dMax,
        cellMaxV: cMax,
        cellMinV: cMin,
      );
    });
  }
}

/// Lưu/đọc lịch sử pin trong file JSONL. Không bao giờ throw.
class BatteryHistoryStore {
  /// Giữ tối đa 90 ngày.
  static const Duration retention = Duration(days: 90);

  /// Dọn file khi vượt ngưỡng dung lượng này.
  static const int compactAtBytes = 4 * 1024 * 1024;

  final Future<File> Function() _fileProvider;
  BatteryHistoryStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFile;

  static Future<File> _defaultFile() async {
    final base = (await getApplicationDocumentsDirectory()).path;
    final dir = Directory('$base/battery_history');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/history.jsonl');
  }

  /// Ghi nối một mẫu. Trả về false nếu lỗi I/O.
  Future<bool> append(BatteryHistoryRecord r) async {
    try {
      final f = await _fileProvider();
      await f.writeAsString('${jsonEncode(r.toJson())}\n', mode: FileMode.append, flush: true);
      if (await f.length() > compactAtBytes) await compact(now: DateTime.now());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Đọc mọi mẫu hợp lệ (bỏ qua dòng hỏng), sắp theo thời gian.
  Future<List<BatteryHistoryRecord>> load() async {
    try {
      final f = await _fileProvider();
      if (!await f.exists()) return const <BatteryHistoryRecord>[];
      final out = <BatteryHistoryRecord>[];
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final r = BatteryHistoryRecord.fromJson(jsonDecode(line));
          if (r != null) out.add(r);
        } catch (_) {
          // dòng hỏng: bỏ qua
        }
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return const <BatteryHistoryRecord>[];
    }
  }

  /// Xóa mẫu quá hạn bằng cách ghi lại file qua file tạm rồi đổi tên.
  Future<bool> compact({required DateTime now}) async {
    try {
      final f = await _fileProvider();
      final cutoff = now.subtract(retention);
      final kept = (await load()).where((r) => !r.at.isBefore(cutoff)).toList();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        kept.map((r) => '${jsonEncode(r.toJson())}\n').join(),
        flush: true,
      );
      await tmp.rename(f.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Xóa toàn bộ lịch sử (chỉ khi người dùng yêu cầu).
  Future<bool> clear() async {
    try {
      final f = await _fileProvider();
      if (await f.exists()) await f.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
