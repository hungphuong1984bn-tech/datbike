// Thu thập BẰNG CHỨNG để xác minh Regen — CHỈ ĐỌC.
//
// Mục tiêu: có dữ liệu đối chiếu để biết (a) Regen có kênh BLE độc lập không,
// (b) mỗi mức Regen cho dòng/công suất tái sinh khác nhau ra sao.
// Mô-đun này KHÔNG ghi bất kỳ characteristic nào, KHÔNG gửi lệnh nào xuống xe.
// Nó chỉ (1) ghi lại telemetry xe đã gửi, kèm mốc do người dùng đánh dấu,
// (2) so sánh hai bản chụp giá trị ĐỌC được của các characteristic.
// Phần logic thuần (CSV, JSON, so sánh, tóm tắt) tách riêng để kiểm thử.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../proto/bike_log.dart';

/// Giới hạn mẫu giữ trong RAM (~3 giờ ở 2 mẫu/giây) để không đầy bộ nhớ.
const int kEvidenceMaxSamples = 20000;

@immutable
class EvidenceSample {
  /// Mili-giây kể từ lúc bắt đầu ghi.
  final int ms;
  final double speedKmh;
  final double phaseA; // dòng pha có dấu — dấu CHƯA được kiểm chứng
  final double voltageV;
  final double powerKw; // V × I / 1000, giữ dấu của dòng pha
  final double throttle;
  final double adc1;
  final double adc2;
  final int stateIndex; // BikeState.index
  final int percent;
  final int error;
  final bool sideStand;

  const EvidenceSample({
    required this.ms,
    required this.speedKmh,
    required this.phaseA,
    required this.voltageV,
    required this.powerKw,
    required this.throttle,
    required this.adc1,
    required this.adc2,
    required this.stateIndex,
    required this.percent,
    required this.error,
    required this.sideStand,
  });

  factory EvidenceSample.from(BikeLogMsg m, int ms) => EvidenceSample(
        ms: ms,
        speedKmh: m.speed,
        phaseA: m.phase,
        voltageV: m.voltage,
        powerKw: m.voltage > 0 ? m.voltage * m.phase / 1000.0 : 0,
        throttle: m.throttle,
        adc1: m.adc1,
        adc2: m.adc2,
        stateIndex: m.state.index,
        percent: m.percent,
        error: m.error,
        sideStand: m.parking,
      );
}

/// Mốc do người dùng đánh dấu: "đang thử Regen mức X", "nhả ga", "phanh"…
@immutable
class EvidenceMark {
  final int ms;
  final String label; // ví dụ: "Mức 2 (theo app gốc)"
  final String note; // ví dụ: "nhả ga từ 25 km/h, đường bằng"
  const EvidenceMark(this.ms, this.label, this.note);
}

@immutable
class RegenEvidenceState {
  final bool recording;
  final DateTime? startedAt;
  final List<EvidenceSample> samples;
  final List<EvidenceMark> marks;

  const RegenEvidenceState({
    this.recording = false,
    this.startedAt,
    this.samples = const [],
    this.marks = const [],
  });

  RegenEvidenceState copyWith({
    bool? recording,
    DateTime? startedAt,
    List<EvidenceSample>? samples,
    List<EvidenceMark>? marks,
  }) =>
      RegenEvidenceState(
        recording: recording ?? this.recording,
        startedAt: startedAt ?? this.startedAt,
        samples: samples ?? this.samples,
        marks: marks ?? this.marks,
      );
}

final regenEvidenceProvider =
    NotifierProvider<RegenEvidenceController, RegenEvidenceState>(RegenEvidenceController.new);

class RegenEvidenceController extends Notifier<RegenEvidenceState> {
  final Stopwatch _clock = Stopwatch();

  @override
  RegenEvidenceState build() {
    // Chỉ ĐỌC telemetry. Không có nhánh nào gửi dữ liệu xuống xe.
    ref.listen<BikeLogMsg?>(bleProvider.select((s) => s.lastTelemetry), (_, m) {
      if (m == null || !state.recording) return;
      final next = [...state.samples, EvidenceSample.from(m, _clock.elapsedMilliseconds)];
      if (next.length > kEvidenceMaxSamples) next.removeRange(0, next.length - kEvidenceMaxSamples);
      state = state.copyWith(samples: next);
    });
    return const RegenEvidenceState();
  }

  void start() {
    if (state.recording) return;
    _clock
      ..reset()
      ..start();
    state = RegenEvidenceState(recording: true, startedAt: DateTime.now());
  }

  void stop() {
    if (!state.recording) return;
    _clock.stop();
    state = state.copyWith(recording: false);
  }

  void clear() {
    _clock
      ..stop()
      ..reset();
    state = const RegenEvidenceState();
  }

  /// Đánh dấu mốc tại thời điểm hiện tại (chỉ khi đang ghi).
  void mark(String label, {String note = ''}) {
    if (!state.recording || label.trim().isEmpty) return;
    state = state.copyWith(
      marks: [...state.marks, EvidenceMark(_clock.elapsedMilliseconds, label.trim(), note.trim())],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Phân tích thuần
// ─────────────────────────────────────────────────────────────────────────

/// Số liệu của một đoạn (từ một mốc tới mốc kế tiếp hoặc hết dữ liệu).
@immutable
class SegmentSummary {
  final EvidenceMark mark;
  final int sampleCount;
  final double durationS;
  final double? speedStartKmh;
  final double? speedEndKmh;
  final double? phaseMinA;
  final double? phaseMaxA;
  final double? powerMinKw;
  final double? powerMaxKw;

  const SegmentSummary({
    required this.mark,
    required this.sampleCount,
    required this.durationS,
    this.speedStartKmh,
    this.speedEndKmh,
    this.phaseMinA,
    this.phaseMaxA,
    this.powerMinKw,
    this.powerMaxKw,
  });
}

/// Cắt mẫu theo mốc. Không diễn giải dấu: chỉ báo cả cực tiểu và cực đại.
List<SegmentSummary> summarizeSegments(List<EvidenceSample> samples, List<EvidenceMark> marks) {
  final out = <SegmentSummary>[];
  for (var i = 0; i < marks.length; i++) {
    final from = marks[i].ms;
    final to = i + 1 < marks.length ? marks[i + 1].ms : null;
    final seg = samples.where((s) => s.ms >= from && (to == null || s.ms < to)).toList();
    if (seg.isEmpty) {
      out.add(SegmentSummary(mark: marks[i], sampleCount: 0, durationS: 0));
      continue;
    }
    double minOf(double Function(EvidenceSample) f) =>
        seg.map(f).reduce((a, b) => a < b ? a : b);
    double maxOf(double Function(EvidenceSample) f) =>
        seg.map(f).reduce((a, b) => a > b ? a : b);
    out.add(SegmentSummary(
      mark: marks[i],
      sampleCount: seg.length,
      durationS: (seg.last.ms - seg.first.ms) / 1000.0,
      speedStartKmh: seg.first.speedKmh,
      speedEndKmh: seg.last.speedKmh,
      phaseMinA: minOf((s) => s.phaseA),
      phaseMaxA: maxOf((s) => s.phaseA),
      powerMinKw: minOf((s) => s.powerKw),
      powerMaxKw: maxOf((s) => s.powerKw),
    ));
  }
  return out;
}

/// Một khác biệt giữa hai bản chụp characteristic.
@immutable
class CharChange {
  final String uuid;
  final String name;
  final String? before; // null = không có ở bản chụp trước
  final String? after;
  const CharChange(this.uuid, this.name, this.before, this.after);
}

/// So sánh hai bản chụp {uuid → giá trị hex/lỗi}. Chỉ trả những char KHÁC nhau.
/// Giá trị bắt đầu bằng "ERR" ở cả hai phía coi như không đọc được, không tính là đổi.
List<CharChange> diffSnapshots(
  Map<String, String> before,
  Map<String, String> after, {
  Map<String, String> names = const {},
}) {
  final keys = {...before.keys, ...after.keys}.toList()..sort();
  final out = <CharChange>[];
  for (final k in keys) {
    final b = before[k];
    final a = after[k];
    if (b == a) continue;
    final bothErr = (b?.startsWith('ERR') ?? false) && (a?.startsWith('ERR') ?? false);
    if (bothErr) continue;
    out.add(CharChange(k, names[k] ?? k, b, a));
  }
  return out;
}

String _num(double v, int d) => v.toStringAsFixed(d);

/// CSV: một dòng mỗi mẫu; cột `mark` ghi nhãn mốc gần nhất đã qua.
String evidenceToCsv(List<EvidenceSample> samples, List<EvidenceMark> marks) {
  final b = StringBuffer(
      'ms,speed_kmh,phase_a,voltage_v,power_kw,throttle,adc1,adc2,state,percent,error,side_stand,mark\n');
  for (final s in samples) {
    EvidenceMark? cur;
    for (final m in marks) {
      if (m.ms <= s.ms) cur = m;
    }
    final label = (cur?.label ?? '').replaceAll('"', "'");
    b.writeln('${s.ms},${_num(s.speedKmh, 1)},${_num(s.phaseA, 2)},${_num(s.voltageV, 2)},'
        '${_num(s.powerKw, 3)},${_num(s.throttle, 1)},${_num(s.adc1, 3)},${_num(s.adc2, 3)},'
        '${s.stateIndex},${s.percent},${s.error},${s.sideStand ? 1 : 0},"$label"');
  }
  return b.toString();
}

/// JSON đầy đủ (kèm ghi chú mốc và, nếu có, kết quả so sánh snapshot).
String evidenceToJson({
  required DateTime? startedAt,
  required List<EvidenceSample> samples,
  required List<EvidenceMark> marks,
  List<CharChange> changes = const [],
  String? appVersion,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'kind': 'regen_evidence',
    'note': 'Chỉ đọc. Không có lệnh ghi nào được gửi. Dấu dòng pha chưa kiểm chứng.',
    if (appVersion != null) 'app': appVersion,
    'startedAt': startedAt?.toIso8601String(),
    'marks': [
      for (final m in marks) {'ms': m.ms, 'label': m.label, 'note': m.note},
    ],
    'characteristicChanges': [
      for (final c in changes)
        {'uuid': c.uuid, 'name': c.name, 'before': c.before, 'after': c.after},
    ],
    'samples': [
      for (final s in samples)
        {
          'ms': s.ms,
          'speed': s.speedKmh,
          'phaseA': s.phaseA,
          'voltageV': s.voltageV,
          'powerKw': s.powerKw,
          'throttle': s.throttle,
          'adc1': s.adc1,
          'adc2': s.adc2,
          'state': s.stateIndex,
          'percent': s.percent,
          'error': s.error,
          'sideStand': s.sideStand,
        },
    ],
  });
}
