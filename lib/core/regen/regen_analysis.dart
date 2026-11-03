// Phân tích bằng chứng Regen — LOGIC THUẦN DART (không phụ thuộc Flutter/BLE).
//
// Đầu vào: chuỗi mẫu telemetry (tốc độ, dòng pha, điện áp) + các mốc do người
// dùng đánh dấu mức Regen theo app gốc. Đầu ra: báo cáo gồm
//   1. KIỂM CHỨNG DẤU dòng pha: dương = nạp ngược (regen) hay âm?
//   2. Các ĐỢT regen (nhả ga, dòng pha cùng chiều nạp): đỉnh, trung bình, năng
//      lượng thu hồi, độ giảm tốc.
//   3. SO SÁNH các mức Regen đã đánh dấu + độ nhất quán với thứ tự mức.
//
// KẾT QUẢ CHỈ LÀ BẰNG CHỨNG QUAN SÁT, KHÔNG PHẢI GIAO THỨC. Dòng nạp phụ thuộc
// tốc độ, dốc, tải, độ đồng đều khi nhả ga; vài lần thử mỗi mức không đủ để kết
// luận chắc chắn. Mô-đun này KHÔNG ghi gì xuống xe.

import 'dart:convert';
import 'dart:math' as math;

/// Một mẫu telemetry dùng cho phân tích.
class RegenPoint {
  final int ms;
  final double speedKmh;
  final double phaseA;
  final double voltageV;
  final double powerKw; // V × I / 1000, giữ dấu của dòng pha
  final int stateIndex;

  const RegenPoint({
    required this.ms,
    required this.speedKmh,
    required this.phaseA,
    required this.voltageV,
    required this.powerKw,
    this.stateIndex = 0,
  });

  factory RegenPoint.fromJson(Map<String, dynamic> j) => RegenPoint(
        ms: (j['ms'] as num).toInt(),
        speedKmh: (j['speed'] as num).toDouble(),
        phaseA: (j['phaseA'] as num).toDouble(),
        voltageV: (j['voltageV'] as num).toDouble(),
        powerKw: (j['powerKw'] as num).toDouble(),
        stateIndex: (j['state'] as num?)?.toInt() ?? 0,
      );
}

/// Mốc đánh dấu mức Regen (theo app gốc).
class RegenMark {
  final int ms;
  final String label;
  const RegenMark(this.ms, this.label);
}

// ─────────────────────────────────────────────────────────────────────────
// 1. Kiểm chứng dấu
// ─────────────────────────────────────────────────────────────────────────

/// Kết quả kiểm chứng dấu của dòng pha.
class PhaseSignVerdict {
  /// Số mẫu dùng (tốc độ > [RegenAnalysis.signMinSpeedKmh]).
  final int samples;

  /// Hệ số tương quan Pearson giữa dòng pha và gia tốc (m/s²). Âm mạnh nghĩa
  /// là dòng pha DƯƠNG đi cùng GIẢM tốc → dương = nạp ngược.
  final double correlation;

  /// Trong các mẫu dòng pha > +2 A: tỉ lệ mẫu xe đang giảm tốc.
  final double decelWhenPositive;

  /// Trong các mẫu dòng pha < −2 A: tỉ lệ mẫu xe đang tăng tốc.
  final double accelWhenNegative;

  /// true = dương là nạp ngược (regen); false = ngược lại; null = chưa đủ chắc.
  final bool? positiveIsRegen;

  const PhaseSignVerdict({
    required this.samples,
    required this.correlation,
    required this.decelWhenPositive,
    required this.accelWhenNegative,
    required this.positiveIsRegen,
  });

  bool get conclusive => positiveIsRegen != null;

  String get summary {
    if (!conclusive) {
      return 'Chưa đủ dữ liệu để kết luận dấu dòng pha (cần đoạn có cả tăng '
          'tốc lẫn nhả ga, tốc độ > ${RegenAnalysis.signMinSpeedKmh.toStringAsFixed(0)} km/h).';
    }
    final r = correlation.toStringAsFixed(2);
    return positiveIsRegen!
        ? 'Dấu đã kiểm chứng: dòng pha DƯƠNG = nạp ngược (regen), ÂM = kéo ga '
            '(tương quan với gia tốc r=$r, ${(decelWhenPositive * 100).round()}% '
            'mẫu dương đi cùng giảm tốc).'
        : 'Dấu đã kiểm chứng NGƯỢC: dòng pha ÂM = nạp ngược (r=$r).';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 2. Đợt regen
// ─────────────────────────────────────────────────────────────────────────

/// Một đợt nạp ngược liên tục.
class RegenEvent {
  final int startMs;
  final int endMs;
  final int samples;
  final double peakA;
  final double meanA;
  final double peakKw;
  final double energyWh;
  final double speedStartKmh;
  final double speedEndKmh;

  /// Độ giảm tốc trung bình (m/s², dương = giảm). null nếu < 2 mẫu.
  final double? decelMs2;

  const RegenEvent({
    required this.startMs,
    required this.endMs,
    required this.samples,
    required this.peakA,
    required this.meanA,
    required this.peakKw,
    required this.energyWh,
    required this.speedStartKmh,
    required this.speedEndKmh,
    required this.decelMs2,
  });

  double get durationS => (endMs - startMs) / 1000.0;
}

// ─────────────────────────────────────────────────────────────────────────
// 3. Thống kê theo mức
// ─────────────────────────────────────────────────────────────────────────

class RegenLevelStats {
  final String label;
  final int samples;
  final int regenSamples;
  final int events;
  final double meanRegenA;
  final double peakA;
  final double meanRegenKw;
  final double peakKw;
  final double energyWh;
  final double? meanDecelMs2;
  final double meanSpeedKmh; // tốc độ trung bình trong lúc nạp

  const RegenLevelStats({
    required this.label,
    required this.samples,
    required this.regenSamples,
    required this.events,
    required this.meanRegenA,
    required this.peakA,
    required this.meanRegenKw,
    required this.peakKw,
    required this.energyWh,
    required this.meanDecelMs2,
    required this.meanSpeedKmh,
  });

  /// Ít mẫu nạp → kết quả kém tin cậy.
  bool get lowData =>
      regenSamples < RegenAnalysis.minRegenSamplesForConfidence || events < 2;
}

class RegenReport {
  final PhaseSignVerdict sign;
  final List<RegenEvent> events;
  final List<RegenLevelStats> levels; // theo thứ tự xuất hiện của mốc

  /// Hệ số Spearman giữa SỐ của mức (nhãn là số) và dòng nạp trung bình.
  /// null nếu < 3 mức có nhãn số hoặc dữ liệu quá ít.
  final double? levelOrderSpearman;

  /// Nhãn các mức xếp từ nạp YẾU → MẠNH theo dòng nạp trung bình.
  final List<String> rankWeakToStrong;

  final double totalRecoveredWh;
  final List<String> notes;

  const RegenReport({
    required this.sign,
    required this.events,
    required this.levels,
    required this.levelOrderSpearman,
    required this.rankWeakToStrong,
    required this.totalRecoveredWh,
    required this.notes,
  });

  RegenLevelStats? level(String label) {
    for (final l in levels) {
      if (l.label == label) return l;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'kind': 'regen_analysis',
        'phaseSign': {
          'positiveIsRegen': sign.positiveIsRegen,
          'correlation': sign.correlation,
          'decelWhenPositive': sign.decelWhenPositive,
          'accelWhenNegative': sign.accelWhenNegative,
          'samples': sign.samples,
        },
        'levelOrderSpearman': levelOrderSpearman,
        'rankWeakToStrong': rankWeakToStrong,
        'totalRecoveredWh': totalRecoveredWh,
        'levels': [
          for (final l in levels)
            {
              'label': l.label,
              'samples': l.samples,
              'regenSamples': l.regenSamples,
              'events': l.events,
              'meanRegenA': l.meanRegenA,
              'peakA': l.peakA,
              'meanRegenKw': l.meanRegenKw,
              'peakKw': l.peakKw,
              'energyWh': l.energyWh,
              'meanDecelMs2': l.meanDecelMs2,
              'meanSpeedKmh': l.meanSpeedKmh,
            },
        ],
        'notes': notes,
      };
}

// ─────────────────────────────────────────────────────────────────────────
// Bộ phân tích
// ─────────────────────────────────────────────────────────────────────────

class RegenAnalysis {
  /// Dòng pha tối thiểu (A, theo chiều nạp) để tính là đang nạp ngược.
  static const double regenMinPhaseA = 3.0;

  /// Tốc độ tối thiểu (km/h) để tính đợt regen (loại nhiễu khi dừng).
  static const double regenMinSpeedKmh = 5.0;

  /// Tốc độ tối thiểu để dùng mẫu cho kiểm chứng dấu.
  static const double signMinSpeedKmh = 3.0;

  /// Số mẫu nạp tối thiểu một mức để coi là đủ tin.
  static const int minRegenSamplesForConfidence = 12;

  /// Mẫu cách nhau quá lâu (ms) thì không tích phân qua khoảng trống.
  static const int maxGapMs = 2500;

  /// Kiểm chứng dấu dòng pha bằng quan hệ với gia tốc.
  static PhaseSignVerdict verifySign(List<RegenPoint> pts) {
    final xs = <double>[];
    final ys = <double>[];
    var posN = 0, posDecel = 0, negN = 0, negAccel = 0;
    for (var i = 1; i < pts.length - 1; i++) {
      final a = pts[i - 1], c = pts[i], b = pts[i + 1];
      final dt = (b.ms - a.ms) / 1000.0;
      if (dt <= 0 || dt > 3.0) continue;
      if (c.speedKmh <= signMinSpeedKmh) continue;
      final acc = (b.speedKmh - a.speedKmh) / 3.6 / dt; // m/s²
      xs.add(c.phaseA);
      ys.add(acc);
      if (c.phaseA > 2) {
        posN++;
        if (acc < 0) posDecel++;
      } else if (c.phaseA < -2) {
        negN++;
        if (acc > 0) negAccel++;
      }
    }
    final r = _pearson(xs, ys);
    final decelRatio = posN == 0 ? 0.0 : posDecel / posN;
    final accelRatio = negN == 0 ? 0.0 : negAccel / negN;
    bool? positiveIsRegen;
    if (xs.length >= 100 && posN >= 20 && negN >= 20) {
      if (r <= -0.5 && decelRatio >= 0.85 && accelRatio >= 0.7) {
        positiveIsRegen = true;
      } else if (r >= 0.5) {
        // dòng pha dương đi cùng TĂNG tốc → dương là kéo ga.
        positiveIsRegen = false;
      }
    }
    return PhaseSignVerdict(
      samples: xs.length,
      correlation: r,
      decelWhenPositive: decelRatio,
      accelWhenNegative: accelRatio,
      positiveIsRegen: positiveIsRegen,
    );
  }

  /// Tách các đợt nạp ngược. [positiveIsRegen] = chiều dấu đã kiểm chứng.
  static List<RegenEvent> findEvents(
    List<RegenPoint> pts, {
    bool positiveIsRegen = true,
  }) {
    double regenA(RegenPoint p) => positiveIsRegen ? p.phaseA : -p.phaseA;
    bool isRegen(RegenPoint p) =>
        regenA(p) >= regenMinPhaseA && p.speedKmh >= regenMinSpeedKmh;

    final out = <RegenEvent>[];
    var i = 0;
    while (i < pts.length) {
      if (!isRegen(pts[i])) {
        i++;
        continue;
      }
      var j = i;
      // Cho phép 1 mẫu hụt nằm giữa hai mẫu nạp (đo dao động).
      while (j + 1 < pts.length) {
        if (isRegen(pts[j + 1]) && pts[j + 1].ms - pts[j].ms <= maxGapMs) {
          j++;
        } else if (j + 2 < pts.length &&
            isRegen(pts[j + 2]) &&
            pts[j + 2].ms - pts[j].ms <= maxGapMs) {
          j += 2;
        } else {
          break;
        }
      }
      out.add(_buildEvent(pts, i, j, positiveIsRegen));
      i = j + 1;
    }
    return out;
  }

  static RegenEvent _buildEvent(
      List<RegenPoint> pts, int i, int j, bool positiveIsRegen) {
    final seg = pts.sublist(i, j + 1);
    double a(RegenPoint p) => positiveIsRegen ? p.phaseA : -p.phaseA;
    double k(RegenPoint p) => positiveIsRegen ? p.powerKw : -p.powerKw;
    var peakA = 0.0, peakKw = 0.0, sumA = 0.0;
    var wh = 0.0;
    for (var n = 0; n < seg.length; n++) {
      final ra = a(seg[n]);
      if (ra > peakA) peakA = ra;
      final rk = k(seg[n]);
      if (rk > peakKw) peakKw = rk;
      sumA += ra;
      if (n > 0) {
        final dtH = (seg[n].ms - seg[n - 1].ms) / 3.6e6;
        if (seg[n].ms - seg[n - 1].ms <= maxGapMs) {
          wh += (math.max(0.0, k(seg[n])) + math.max(0.0, k(seg[n - 1]))) /
              2 *
              1000 *
              dtH;
        }
      }
    }
    double? decel;
    if (seg.length >= 2) {
      final dt = (seg.last.ms - seg.first.ms) / 1000.0;
      if (dt > 0) decel = (seg.first.speedKmh - seg.last.speedKmh) / 3.6 / dt;
    }
    return RegenEvent(
      startMs: seg.first.ms,
      endMs: seg.last.ms,
      samples: seg.length,
      peakA: peakA,
      meanA: sumA / seg.length,
      peakKw: peakKw,
      energyWh: wh,
      speedStartKmh: seg.first.speedKmh,
      speedEndKmh: seg.last.speedKmh,
      decelMs2: decel,
    );
  }

  /// Phân tích đầy đủ. [marks] có thể rỗng (chỉ có kiểm chứng dấu + đợt regen).
  static RegenReport analyze(List<RegenPoint> pts, List<RegenMark> marks) {
    final sorted = [...pts]..sort((a, b) => a.ms.compareTo(b.ms));
    final sign = verifySign(sorted);
    final positive = sign.positiveIsRegen ?? true; // mặc định theo bộ giải mã
    final events = findEvents(sorted, positiveIsRegen: positive);

    final ms = [...marks]..sort((a, b) => a.ms.compareTo(b.ms));
    final levels = <RegenLevelStats>[];
    for (var m = 0; m < ms.length; m++) {
      final from = ms[m].ms;
      final to = m + 1 < ms.length ? ms[m + 1].ms : 1 << 62;
      final seg = sorted.where((p) => p.ms >= from && p.ms < to).toList();
      final evs = findEvents(seg, positiveIsRegen: positive);
      levels.add(_levelStats(ms[m].label, seg, evs, positive));
    }
    // Gộp các mốc trùng nhãn (đánh dấu cùng mức nhiều lần).
    final merged = _mergeByLabel(levels);

    final notes = <String>[];
    if (!sign.conclusive) {
      notes.add('Chưa kết luận được dấu dòng pha — dùng mặc định "dương = nạp ngược".');
    }
    if (merged.isEmpty) {
      notes.add('Chưa có mốc mức Regen nào — chỉ phân tích được các đợt nạp.');
    }
    for (final l in merged) {
      if (l.lowData) {
        notes.add('Mức "${l.label}": chỉ ${l.regenSamples} mẫu nạp — kém tin cậy, '
            'hãy thử thêm vài lần nhả ga ở tốc độ tương tự.');
      }
    }

    final rankable = merged.where((l) => l.regenSamples > 0).toList()
      ..sort((a, b) => a.meanRegenA.compareTo(b.meanRegenA));
    final spearman = _levelSpearman(rankable);
    if (spearman != null && rankable.length >= 3) {
      notes.add(spearman >= 0.7
          ? 'Mức số càng lớn thì dòng nạp trung bình càng lớn (Spearman '
              '${spearman.toStringAsFixed(2)}) — phù hợp thang "mạnh dần".'
          : 'Dòng nạp KHÔNG tăng rõ theo số mức (Spearman '
              '${spearman.toStringAsFixed(2)}) — có thể do khác tốc độ/độ dốc giữa các lần thử.');
    }
    notes.add('Dòng nạp phụ thuộc tốc độ lúc nhả ga; so sánh công bằng cần cùng '
        'tốc độ, cùng đoạn đường, chỉ nhả ga (không phanh).');

    return RegenReport(
      sign: sign,
      events: events,
      levels: merged,
      levelOrderSpearman: spearman,
      rankWeakToStrong: [for (final l in rankable) l.label],
      totalRecoveredWh: events.fold(0.0, (s, e) => s + e.energyWh),
      notes: notes,
    );
  }

  static RegenLevelStats _levelStats(
    String label,
    List<RegenPoint> seg,
    List<RegenEvent> evs,
    bool positive,
  ) {
    double a(RegenPoint p) => positive ? p.phaseA : -p.phaseA;
    double k(RegenPoint p) => positive ? p.powerKw : -p.powerKw;
    final regen = seg
        .where((p) => a(p) >= regenMinPhaseA && p.speedKmh >= regenMinSpeedKmh)
        .toList();
    double mean(Iterable<double> v) =>
        v.isEmpty ? 0.0 : v.reduce((x, y) => x + y) / v.length;
    final decels = [
      for (final e in evs)
        if (e.decelMs2 != null && e.samples >= 2) e.decelMs2!,
    ];
    return RegenLevelStats(
      label: label,
      samples: seg.length,
      regenSamples: regen.length,
      events: evs.length,
      meanRegenA: mean(regen.map(a)),
      peakA: regen.isEmpty ? 0 : regen.map(a).reduce(math.max),
      meanRegenKw: mean(regen.map(k)),
      peakKw: regen.isEmpty ? 0 : regen.map(k).reduce(math.max),
      energyWh: evs.fold(0.0, (s, e) => s + e.energyWh),
      meanDecelMs2: decels.isEmpty ? null : mean(decels),
      meanSpeedKmh: mean(regen.map((p) => p.speedKmh)),
    );
  }

  static List<RegenLevelStats> _mergeByLabel(List<RegenLevelStats> src) {
    final order = <String>[];
    final groups = <String, List<RegenLevelStats>>{};
    for (final l in src) {
      groups.putIfAbsent(l.label, () {
        order.add(l.label);
        return [];
      }).add(l);
    }
    final out = <RegenLevelStats>[];
    for (final label in order) {
      final g = groups[label]!;
      if (g.length == 1) {
        out.add(g.first);
        continue;
      }
      final n = g.fold<int>(0, (s, x) => s + x.regenSamples);
      double wavg(double Function(RegenLevelStats) f) => n == 0
          ? 0.0
          : g.fold<double>(0, (s, x) => s + f(x) * x.regenSamples) / n;
      final decels = g.where((x) => x.meanDecelMs2 != null).toList();
      out.add(RegenLevelStats(
        label: label,
        samples: g.fold(0, (s, x) => s + x.samples),
        regenSamples: n,
        events: g.fold(0, (s, x) => s + x.events),
        meanRegenA: wavg((x) => x.meanRegenA),
        peakA: g.map((x) => x.peakA).reduce(math.max),
        meanRegenKw: wavg((x) => x.meanRegenKw),
        peakKw: g.map((x) => x.peakKw).reduce(math.max),
        energyWh: g.fold(0.0, (s, x) => s + x.energyWh),
        meanDecelMs2: decels.isEmpty
            ? null
            : decels.fold<double>(0, (s, x) => s + x.meanDecelMs2!) /
                decels.length,
        meanSpeedKmh: wavg((x) => x.meanSpeedKmh),
      ));
    }
    return out;
  }

  /// Spearman giữa số của mức (nhãn là số nguyên) và dòng nạp trung bình.
  static double? _levelSpearman(List<RegenLevelStats> ls) {
    final pairs = <(double, double)>[];
    for (final l in ls) {
      final n = int.tryParse(l.label.trim());
      if (n != null) pairs.add((n.toDouble(), l.meanRegenA));
    }
    if (pairs.length < 3) return null;
    final rx = _ranks([for (final p in pairs) p.$1]);
    final ry = _ranks([for (final p in pairs) p.$2]);
    return _pearson(rx, ry);
  }

  static List<double> _ranks(List<double> v) {
    final idx = List<int>.generate(v.length, (i) => i)
      ..sort((a, b) => v[a].compareTo(v[b]));
    final r = List<double>.filled(v.length, 0);
    var i = 0;
    while (i < idx.length) {
      var j = i;
      while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
        j++;
      }
      final avg = (i + j) / 2 + 1;
      for (var k = i; k <= j; k++) {
        r[idx[k]] = avg;
      }
      i = j + 1;
    }
    return r;
  }

  static double _pearson(List<double> x, List<double> y) {
    final n = x.length;
    if (n < 3 || y.length != n) return 0;
    final mx = x.reduce((a, b) => a + b) / n;
    final my = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (x[i] - mx) * (y[i] - my);
      sxx += (x[i] - mx) * (x[i] - mx);
      syy += (y[i] - my) * (y[i] - my);
    }
    if (sxx <= 0 || syy <= 0) return 0;
    return sxy / math.sqrt(sxx * syy);
  }

  /// Đọc file JSON do màn "Bằng chứng Regen" xuất ra (`kind: regen_evidence`).
  static RegenReport analyzeEvidenceJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final pts = [
      for (final s in (m['samples'] as List? ?? const []))
        RegenPoint.fromJson(s as Map<String, dynamic>),
    ];
    final marks = [
      for (final k in (m['marks'] as List? ?? const []))
        RegenMark((k['ms'] as num).toInt(), '${k['label']}'),
    ];
    return analyze(pts, marks);
  }
}
