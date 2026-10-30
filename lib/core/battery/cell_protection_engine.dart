// Cell Protection Engine — đánh giá an toàn từ PackSnapshot.
//
// - Chỉ đưa ra cảnh báo dựa trên số đo THỰC của BMS và cấu hình do người dùng nhập.
// - Ngưỡng điện áp tuyệt đối theo cell chỉ hoạt động khi đã được cấu hình.
// - Khi dữ liệu không còn trực tiếp (cũ / mất kết nối), engine KHÔNG đánh giá lại
//   các số đo cũ như thể đang đo trực tiếp; chỉ báo tình trạng dữ liệu.
// - Engine thuần Dart: không phát bất kỳ lệnh nào xuống BMS.

import 'battery_config.dart';
import 'battery_history.dart';
import 'cell_model.dart';

enum AlertSeverity {
  normal('NORMAL'),
  warning('WARNING'),
  critical('CRITICAL');

  final String label;
  const AlertSeverity(this.label);
}

enum AlertType {
  cellOverVoltage('Quá áp cell'),
  cellUnderVoltage('Thấp áp cell'),
  packDelta('Chênh lệch điện áp cell'),
  cellOutlier('Cell lệch bất thường'),
  cellDegradation('Dấu hiệu suy giảm cell'),
  bmsTemperature('Nhiệt độ cao'),
  ntcAbnormal('Cảm biến NTC bất thường'),
  cellDataInvalid('Dữ liệu cell lỗi'),
  cellDataMissing('Mất dữ liệu cell'),
  dataTimeout('Dữ liệu BMS quá hạn'),
  linkLost('Mất kết nối BMS'),
  packSyncMismatch('Dữ liệu BMS không đồng bộ'),
  bmsFlags('BMS báo cờ bảo vệ / lỗi');

  final String label;
  const AlertType(this.label);
}

class ProtectionAlert {
  /// Khoá ổn định giữa các lần đánh giá (dùng để biết "thời điểm phát sinh").
  final String id;
  final AlertType type;
  final AlertSeverity severity;
  final String title;

  /// Chỉ số cell (0-based) liên quan; rỗng nếu cảnh báo cấp pack/cảm biến.
  final List<int> cellIndices;

  /// Giá trị đo thực tế dạng chuỗi hiển thị.
  final String measured;
  final DateTime since;
  final String cause;
  final String recommendation;

  const ProtectionAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.cellIndices,
    required this.measured,
    required this.since,
    required this.cause,
    required this.recommendation,
  });

  String get cellLabels => cellIndices.isEmpty
      ? '—'
      : cellIndices.map((i) => 'Cell ${(i + 1).toString().padLeft(2, '0')}').join(', ');
}

class ProtectionReport {
  final AlertSeverity overall;
  final List<ProtectionAlert> alerts;
  final DateTime evaluatedAt;

  /// true nếu các số đo được đánh giá là dữ liệu trực tiếp.
  final bool evaluatedLive;
  final BmsFreshness freshness;

  const ProtectionReport({
    required this.overall,
    required this.alerts,
    required this.evaluatedAt,
    required this.evaluatedLive,
    required this.freshness,
  });

  static ProtectionReport empty(DateTime now) => ProtectionReport(
        overall: AlertSeverity.normal,
        alerts: const [],
        evaluatedAt: now,
        evaluatedLive: false,
        freshness: BmsFreshness.none,
      );

  int count(AlertSeverity s) => alerts.where((a) => a.severity == s).length;
}

class CellProtectionEngine {
  CellProtectionEngine._();

  /// Dải đọc hợp lệ của cảm biến nhiệt NTC (giới hạn vật lý của phép đo).
  static const double ntcMinPlausibleC = -40.0;
  static const double ntcMaxPlausibleC = 125.0;

  static bool isPlausibleTemp(double t) =>
      t.isFinite && t >= ntcMinPlausibleC && t <= ntcMaxPlausibleC;

  static AlertSeverity _max(AlertSeverity a, AlertSeverity b) =>
      a.index >= b.index ? a : b;

  static String _v(double v) => '${v.toStringAsFixed(3)} V';

  static ProtectionReport evaluate({
    required PackSnapshot? pack,
    required DateTime now,
    required bool connected,
    required BatteryConfig cfg,
    double? telemetryBmsTempC,
    List<CellTrend> trends = const [],
    Map<String, DateTime> activeSince = const {},
    Duration liveWithin = BmsFreshness.defaultLiveWindow,
  }) {
    final freshness = BmsFreshness.evaluate(
      receivedAt: pack?.receivedAt,
      now: now,
      connected: connected,
      liveWithin: liveWithin,
    );
    final alerts = <ProtectionAlert>[];

    DateTime since(String id) => activeSince[id] ?? now;

    void add(
      String id,
      AlertType type,
      AlertSeverity sev,
      String title,
      String measured,
      String cause,
      String rec, {
      List<int> cells = const [],
    }) {
      alerts.add(ProtectionAlert(
        id: id,
        type: type,
        severity: sev,
        title: title,
        cellIndices: List<int>.unmodifiable(cells),
        measured: measured,
        since: since(id),
        cause: cause,
        recommendation: rec,
      ));
    }

    // ── Trạng thái dữ liệu ──────────────────────────────────────────────────
    if (pack == null) {
      // Chưa từng nhận gói BMS: không phải sự cố pin, chỉ là chưa có dữ liệu.
      return ProtectionReport(
        overall: AlertSeverity.normal,
        alerts: const [],
        evaluatedAt: now,
        evaluatedLive: false,
        freshness: freshness,
      );
    }

    final age = now.difference(pack.receivedAt);

    if (freshness == BmsFreshness.lost) {
      add(
        'link-lost',
        AlertType.linkLost,
        AlertSeverity.warning,
        'Mất kết nối với BMS',
        'Gói BMS cuối cách ${age.inSeconds} giây',
        'Bluetooth giữa app và xe đã ngắt (xe tắt, ra khỏi vùng sóng hoặc đang kết nối lại).',
        'Các số liệu cell hiển thị là bản cuối cùng, KHÔNG phải số đo hiện tại. Kết nối lại với xe để đánh giá tiếp.',
      );
    } else if (freshness == BmsFreshness.stale &&
        age.inSeconds > cfg.dataTimeoutSec) {
      add(
        'data-timeout',
        AlertType.dataTimeout,
        AlertSeverity.warning,
        'Không nhận được gói BMS mới',
        'Gói BMS cuối cách ${age.inSeconds} giây (ngưỡng ${cfg.dataTimeoutSec} giây)',
        'Đường truyền BLE chập chờn hoặc xe không phản hồi khi đọc nhật ký pin.',
        'Đưa điện thoại lại gần xe, thử "Quét lại dữ liệu xe"; nếu lặp lại hãy kiểm tra kết nối Bluetooth.',
      );
    }

    final live = freshness == BmsFreshness.live;
    if (!live) {
      return _finish(alerts, now, freshness, false);
    }

    // ── Từ đây: dữ liệu TRỰC TIẾP ───────────────────────────────────────────
    if (!pack.hasCells) {
      add(
        'cells-missing',
        AlertType.cellDataMissing,
        AlertSeverity.warning,
        'Gói BMS không có dữ liệu điện áp cell',
        'Số cell nhận được: 0',
        'BMS không gửi mảng điện áp cell trong gói này hoặc gói bị cắt/lỗi giải mã.',
        'Quét lại dữ liệu xe. Nếu liên tục không có cell, kiểm tra firmware/BMS tại trạm dịch vụ.',
      );
    } else {
      _evaluateCells(pack, cfg, trends, add);
    }

    _evaluateTemperatures(pack, cfg, telemetryBmsTempC, add);
    _evaluateSync(pack, cfg, add);

    final flagged = pack.protectionRaw != 0 ||
        pack.errorCode != 0 ||
        pack.protections.any((p) => p != 0);
    if (flagged) {
      add(
        'bms-flags',
        AlertType.bmsFlags,
        AlertSeverity.warning,
        'BMS báo cờ bảo vệ / mã lỗi',
        'protection=${pack.protectionRaw}, error=${pack.errorCode}'
            '${pack.protections.isEmpty ? '' : ', protections=${pack.protections}'}',
        'BMS đang báo giá trị khác 0. Ý nghĩa từng bit CHƯA được xác minh từ tài liệu nên app không diễn giải.',
        'Ghi lại mã thô này và đối chiếu với tài liệu BMS/nhà sản xuất hoặc mang xe đến trạm dịch vụ.',
      );
    }

    return _finish(alerts, now, freshness, true);
  }

  static ProtectionReport _finish(
    List<ProtectionAlert> alerts,
    DateTime now,
    BmsFreshness freshness,
    bool live,
  ) {
    var overall = AlertSeverity.normal;
    for (final a in alerts) {
      overall = _max(overall, a.severity);
    }
    alerts.sort((a, b) {
      final c = b.severity.index.compareTo(a.severity.index);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return ProtectionReport(
      overall: overall,
      alerts: List<ProtectionAlert>.unmodifiable(alerts),
      evaluatedAt: now,
      evaluatedLive: live,
      freshness: freshness,
    );
  }

  static void _evaluateCells(
    PackSnapshot pack,
    BatteryConfig cfg,
    List<CellTrend> trends,
    void Function(String, AlertType, AlertSeverity, String, String, String, String,
            {List<int> cells})
        add,
  ) {
    // Cell dữ liệu lỗi (ngoài dải số liệu hợp lệ).
    final invalid = [for (final c in pack.cells) if (!c.valid) c.index];
    if (invalid.isNotEmpty) {
      add(
        'cells-invalid',
        AlertType.cellDataInvalid,
        AlertSeverity.warning,
        '${invalid.length} cell có dữ liệu không hợp lệ',
        'Giá trị ngoài dải đo hợp lệ hoặc không phải số',
        'Lỗi đọc/giải mã điện áp cell hoặc dây cân bằng/đầu đo của BMS có vấn đề.',
        'Quét lại dữ liệu. Nếu cùng cell lỗi lặp lại, kiểm tra dây đo cell tại trạm dịch vụ.',
        cells: invalid,
      );
    }

    // Quá áp / thấp áp tuyệt đối — CHỈ khi người dùng đã cấu hình ngưỡng.
    List<int> pick(bool Function(double v) test) =>
        [for (final c in pack.cells) if (c.valid && test(c.voltage)) c.index];

    String range(List<int> idx) {
      final vs = idx.map((i) => pack.cells[i].voltage).toList()..sort();
      return vs.length == 1 ? _v(vs.first) : '${_v(vs.first)} … ${_v(vs.last)}';
    }

    final ovCrit = cfg.cellOverVoltCritV;
    final ovWarn = cfg.cellOverVoltWarnV;
    if (ovCrit != null) {
      final idx = pick((v) => v >= ovCrit);
      if (idx.isNotEmpty) {
        add(
          'ovp-crit',
          AlertType.cellOverVoltage,
          AlertSeverity.critical,
          'Quá áp cell (≥ ${_v(ovCrit)})',
          range(idx),
          'Cell vượt ngưỡng CRITICAL do bạn cấu hình: có thể do sạc quá mức hoặc mất cân bằng nặng.',
          'Ngừng sạc, đừng sạc thêm khi chưa kiểm tra. Đối chiếu ngưỡng với thông số cell của nhà sản xuất.',
          cells: idx,
        );
      }
    }
    if (ovWarn != null) {
      final idx = pick((v) => v >= ovWarn && (ovCrit == null || v < ovCrit));
      if (idx.isNotEmpty) {
        add(
          'ovp-warn',
          AlertType.cellOverVoltage,
          AlertSeverity.warning,
          'Điện áp cell cao (≥ ${_v(ovWarn)})',
          range(idx),
          'Cell vượt ngưỡng WARNING đã cấu hình, thường gặp khi sắp sạc đầy hoặc cell lệch.',
          'Theo dõi; nếu tiếp tục tăng hoặc lặp lại khi chưa đầy, hãy kiểm tra pack.',
          cells: idx,
        );
      }
    }
    final uvCrit = cfg.cellUnderVoltCritV;
    final uvWarn = cfg.cellUnderVoltWarnV;
    if (uvCrit != null) {
      final idx = pick((v) => v <= uvCrit);
      if (idx.isNotEmpty) {
        add(
          'uvp-crit',
          AlertType.cellUnderVoltage,
          AlertSeverity.critical,
          'Thấp áp cell (≤ ${_v(uvCrit)})',
          range(idx),
          'Cell xuống dưới ngưỡng CRITICAL đã cấu hình: pin cạn sâu, cell yếu hoặc sụt áp khi tải lớn.',
          'Dừng sử dụng tải nặng, sạc sớm và theo dõi. Nếu cell tụt nhanh bất thường hãy mang xe kiểm tra.',
          cells: idx,
        );
      }
    }
    if (uvWarn != null) {
      final idx = pick((v) => v <= uvWarn && (uvCrit == null || v > uvCrit));
      if (idx.isNotEmpty) {
        add(
          'uvp-warn',
          AlertType.cellUnderVoltage,
          AlertSeverity.warning,
          'Điện áp cell thấp (≤ ${_v(uvWarn)})',
          range(idx),
          'Cell dưới ngưỡng WARNING đã cấu hình: pin gần cạn hoặc sụt áp khi tải.',
          'Nên sạc sớm; theo dõi xem cùng một cell có luôn thấp hơn các cell còn lại không.',
          cells: idx,
        );
      }
    }

    if (pack.validCount < 2) return;

    // Chênh lệch giữa cell cao nhất và thấp nhất.
    final hiLo = [pack.maxIndex, pack.minIndex].where((i) => i >= 0).toList();
    if (pack.deltaMv >= cfg.deltaCritMv) {
      add(
        'delta-crit',
        AlertType.packDelta,
        AlertSeverity.critical,
        'ΔV rất cao giữa các cell',
        'ΔV = ${pack.deltaMv.toStringAsFixed(1)} mV '
            '(${_v(pack.vMax)} − ${_v(pack.vMin)}), ngưỡng ${cfg.deltaCritMv.toStringAsFixed(0)} mV',
        'Các cell mất cân bằng nặng, hoặc một cell yếu/nội trở cao sụt áp mạnh hơn.',
        'Hạn chế tải nặng, sạc đầy và giữ cắm sạc để BMS cân bằng; nếu ΔV không giảm hãy kiểm tra pack.',
        cells: hiLo,
      );
    } else if (pack.deltaMv >= cfg.deltaWarnMv) {
      add(
        'delta-warn',
        AlertType.packDelta,
        AlertSeverity.warning,
        'ΔV cao giữa các cell',
        'ΔV = ${pack.deltaMv.toStringAsFixed(1)} mV '
            '(${_v(pack.vMax)} − ${_v(pack.vMin)}), ngưỡng ${cfg.deltaWarnMv.toStringAsFixed(0)} mV',
        'Các cell lệch nhau đáng kể; có thể do chưa được cân bằng hoặc đang chịu tải.',
        'Sạc đầy và để BMS cân bằng, sau đó đo lại khi pin nghỉ.',
        cells: hiLo,
      );
    }

    // Cell lệch bất thường so với trung bình (cần ≥3 cell hợp lệ).
    if (pack.validCount >= 3) {
      final crit = <int>[];
      final warn = <int>[];
      for (final c in pack.cells) {
        if (!c.valid) continue;
        final d = c.deviationMv.abs();
        if (d >= cfg.cellDeviationCritMv) {
          crit.add(c.index);
        } else if (d >= cfg.cellDeviationWarnMv) {
          warn.add(c.index);
        }
      }
      String devText(List<int> idx) => idx
          .map((i) =>
              '${pack.cells[i].label}: ${pack.cells[i].deviationMv >= 0 ? '+' : ''}${pack.cells[i].deviationMv.toStringAsFixed(1)} mV')
          .join('; ');
      if (crit.isNotEmpty) {
        add(
          'outlier-crit',
          AlertType.cellOutlier,
          AlertSeverity.critical,
          'Cell lệch mạnh so với trung bình',
          devText(crit),
          'Cell này cao/thấp hơn hẳn trung bình pack: cell yếu, tiếp xúc kém hoặc mất cân bằng cục bộ.',
          'Ghi lại cell và kiểm tra tại trạm dịch vụ nếu lặp lại sau một chu kỳ sạc đầy.',
          cells: crit,
        );
      }
      if (warn.isNotEmpty) {
        add(
          'outlier-warn',
          AlertType.cellOutlier,
          AlertSeverity.warning,
          'Cell lệch so với trung bình',
          devText(warn),
          'Cell lệch nhẹ-vừa so với trung bình pack; thường do cân bằng chưa xong hoặc tải.',
          'Theo dõi qua vài lần sạc; nếu cùng cell luôn lệch, đây là dấu hiệu cần kiểm tra.',
          cells: warn,
        );
      }

      // Suy giảm bất thường: độ lệch kéo dài (cần đủ mẫu lịch sử).
      final persistent = [
        for (final t in trends)
          if (t.cellIndex < pack.cellCount &&
              pack.cells[t.cellIndex].valid &&
              t.meanDeviationMv.abs() >= cfg.cellDeviationWarnMv)
            t,
      ];
      if (persistent.isNotEmpty) {
        add(
          'degradation',
          AlertType.cellDegradation,
          AlertSeverity.warning,
          'Cell lệch kéo dài so với trung bình',
          persistent
              .map((t) =>
                  'Cell ${(t.cellIndex + 1).toString().padLeft(2, '0')}: TB ${t.meanDeviationMv >= 0 ? '+' : ''}${t.meanDeviationMv.toStringAsFixed(1)} mV / ${t.samples} mẫu')
              .join('; '),
          'Độ lệch duy trì trong nhiều mẫu liên tiếp. Đây chỉ là gợi ý về cell yếu (dung lượng/nội trở), chưa phải kết luận suy giảm.',
          'So sánh qua nhiều chu kỳ sạc/xả. Nếu cùng cell luôn lệch, đưa xe kiểm tra pack.',
          cells: [for (final t in persistent) t.cellIndex],
        );
      }
    }
  }

  static void _evaluateTemperatures(
    PackSnapshot pack,
    BatteryConfig cfg,
    double? telemetryBmsTempC,
    void Function(String, AlertType, AlertSeverity, String, String, String, String,
            {List<int> cells})
        add,
  ) {
    final readings = <String, double>{};
    for (var i = 0; i < pack.ntcs.length; i++) {
      readings['NTC ${i + 1}'] = pack.ntcs[i];
    }
    if (telemetryBmsTempC != null && telemetryBmsTempC > 0) {
      readings['BMS (telemetry)'] = telemetryBmsTempC;
    }
    if (pack.fetTemp > 0) readings['MOSFET BMS'] = pack.fetTemp;

    final crit = <String>[];
    final warn = <String>[];
    final bad = <String>[];
    final goodNtc = <double>[];
    readings.forEach((name, t) {
      if (!isPlausibleTemp(t)) {
        bad.add('$name = ${t.isFinite ? t.toStringAsFixed(1) : 'NaN'} °C');
        return;
      }
      if (name.startsWith('NTC')) goodNtc.add(t);
      if (t >= cfg.tempCritC) {
        crit.add('$name = ${t.toStringAsFixed(1)} °C');
      } else if (t >= cfg.tempWarnC) {
        warn.add('$name = ${t.toStringAsFixed(1)} °C');
      }
    });

    if (crit.isNotEmpty) {
      add(
        'temp-crit',
        AlertType.bmsTemperature,
        AlertSeverity.critical,
        'Nhiệt độ pack/BMS rất cao (≥ ${cfg.tempCritC.toStringAsFixed(0)} °C)',
        crit.join('; '),
        'Pack hoặc BMS quá nóng do tải/sạc kéo dài, môi trường nóng hoặc tản nhiệt kém.',
        'Dừng sạc và giảm tải, để xe nghỉ nơi thoáng mát. Nếu nhiệt độ không giảm hãy ngắt nguồn và kiểm tra.',
      );
    }
    if (warn.isNotEmpty) {
      add(
        'temp-warn',
        AlertType.bmsTemperature,
        AlertSeverity.warning,
        'Nhiệt độ pack/BMS cao (≥ ${cfg.tempWarnC.toStringAsFixed(0)} °C)',
        warn.join('; '),
        'Nhiệt độ tăng do tải nặng, sạc hoặc thời tiết nóng.',
        'Giảm tải, tránh sạc ngay khi pin còn nóng, theo dõi tiếp.',
      );
    }
    if (bad.isNotEmpty) {
      add(
        'ntc-invalid',
        AlertType.ntcAbnormal,
        AlertSeverity.warning,
        'Cảm biến nhiệt trả giá trị bất thường',
        bad.join('; '),
        'Cảm biến NTC hở mạch/chập hoặc dữ liệu lỗi (ngoài dải ${ntcMinPlausibleC.toStringAsFixed(0)}…${ntcMaxPlausibleC.toStringAsFixed(0)} °C).',
        'Không dựa vào số nhiệt độ này; kiểm tra cảm biến và giắc NTC tại trạm dịch vụ.',
      );
    }
    if (goodNtc.length >= 2) {
      final hi = goodNtc.reduce((a, b) => a > b ? a : b);
      final lo = goodNtc.reduce((a, b) => a < b ? a : b);
      if (hi - lo >= cfg.ntcSpreadWarnC) {
        add(
          'ntc-spread',
          AlertType.ntcAbnormal,
          AlertSeverity.warning,
          'Các cảm biến NTC chênh lệch nhiệt độ lớn',
          'Cao nhất ${hi.toStringAsFixed(1)} °C, thấp nhất ${lo.toStringAsFixed(1)} °C (chênh ${(hi - lo).toStringAsFixed(1)} °C)',
          'Một vùng pack nóng hơn hẳn (cell/đầu nối nóng) hoặc một cảm biến sai.',
          'Kiểm tra vùng nóng hơn và cảm biến tương ứng tại trạm dịch vụ nếu chênh lệch kéo dài.',
        );
      }
    }
  }

  static void _evaluateSync(
    PackSnapshot pack,
    BatteryConfig cfg,
    void Function(String, AlertType, AlertSeverity, String, String, String, String,
            {List<int> cells})
        add,
  ) {
    if (!pack.hasCells ||
        pack.validCount != pack.cellCount ||
        pack.packVoltage <= 0 ||
        pack.sumCellsV <= 0) {
      return;
    }
    final diffPct =
        (pack.sumCellsV - pack.packVoltage).abs() / pack.packVoltage * 100.0;
    if (diffPct > cfg.packSyncTolerancePct) {
      add(
        'sync-mismatch',
        AlertType.packSyncMismatch,
        AlertSeverity.warning,
        'Tổng điện áp cell không khớp điện áp pack',
        'Tổng cell ${pack.sumCellsV.toStringAsFixed(2)} V so với pack ${pack.packVoltage.toStringAsFixed(2)} V '
            '(lệch ${diffPct.toStringAsFixed(1)} %, cho phép ${cfg.packSyncTolerancePct.toStringAsFixed(1)} %)',
        'Các trường dữ liệu trong cùng gói không đồng bộ: BMS lấy mẫu lệch thời điểm, thiếu cell hoặc sai hệ số.',
        'Quét lại dữ liệu; nếu lặp lại, đối chiếu cấu hình số cell của BMS.',
      );
    }
  }
}
