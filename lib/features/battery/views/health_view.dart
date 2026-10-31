// Trung tâm sức khỏe pin. Mỗi chỉ số gắn nhãn nguồn: BMS đo / Tính toán / Ước tính /
// Không có — không bao giờ trình bày giá trị ước tính như số đo thực tế.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/battery/battery_hub.dart';
import '../../../core/battery/battery_sessions.dart';
import '../../../core/battery/cell_model.dart';
import '../../../core/services/battery_diagnostics_service.dart';
import '../bms_theme.dart';
import '../widgets/bms_charts.dart';

class HealthView extends ConsumerWidget {
  final BatteryHealthReport report;

  /// SOC (%) từ telemetry xe — dự phòng khi gói BMS không có SOC.
  final int telemetryPercent;
  final bool telemetryLive;

  const HealthView({
    super.key,
    required this.report,
    required this.telemetryPercent,
    required this.telemetryLive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(batteryHubProvider);
    ref.watch(batteryHubProvider.select((s) => s.revision));
    final history = ref.read(batteryHubProvider.notifier).history;
    final p = hub.latest;
    final live = hub.freshness == BmsFreshness.live;

    // SOC: ưu tiên số của BMS; nếu không có dùng telemetry xe (ghi rõ nguồn).
    double? soc;
    String socSource = '';
    if (live && p != null && p.socPercent > 0) {
      soc = p.socPercent.clamp(0, 100).toDouble();
      socSource = 'Từ BMS';
    } else if (telemetryLive && telemetryPercent > 0) {
      soc = telemetryPercent.toDouble();
      socSource = 'Từ telemetry xe';
    }

    final ongoing = hub.activitySessions.isNotEmpty && hub.activitySessions.first.isOngoing
        ? hub.activitySessions.first
        : null;
    final power = (live && p != null && p.packVoltage > 0) ? (p.packVoltage * p.current).abs() : null;

    final ntcText = (live && p != null && p.ntcs.isNotEmpty)
        ? p.ntcs.map((t) => t.toStringAsFixed(1)).join(' / ')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataStateBanner(freshness: hub.freshness, receivedAt: p?.receivedAt),
        GlassCard(
          blur: true,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox(
                width: 118,
                height: 118,
                child: CustomPaint(
                  painter: _SocRingPainter(soc == null ? null : soc / 100.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(soc == null ? '--' : soc.toStringAsFixed(0),
                            style: Bms.number(34, soc == null ? Bms.invalid : Bms.text)),
                        Text('% SOC', style: Bms.body(11)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FreshnessPill(hub.freshness),
                    const SizedBox(height: 8),
                    Text(socSource.isEmpty ? 'Chưa có SOC trực tiếp' : 'SOC $socSource',
                        style: Bms.body(12.5, Bms.text)),
                    const SizedBox(height: 4),
                    Text(
                      ongoing == null
                          ? 'Hoạt động: nghỉ / chưa rõ'
                          : 'Hoạt động: ${ongoing.activity.label}',
                      style: Bms.body(12.5),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('Gói cuối: ', style: Bms.body(11.5, Bms.textFaint)),
                      AgeText(at: p?.receivedAt),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Chỉ số bộ pin'),
        _grid([
          _Metric('Điện áp pack', live && p != null && p.packVoltage > 0 ? '${p.packVoltage.toStringAsFixed(2)} V' : '--',
              DataSource.measured, live && p != null && p.packVoltage > 0),
          _Metric('Tổng điện áp cell', live && p != null && p.validCount > 0 ? '${p.sumCellsV.toStringAsFixed(2)} V' : '--',
              DataSource.calculated, live && p != null && p.validCount > 0),
          _Metric('Dòng (BMS)', live && p != null ? '${p.current.toStringAsFixed(1)} A' : '--',
              DataSource.measured, live && p != null,
              note: 'Dấu dòng BMS chưa xác minh'),
          _Metric('Công suất |V×I|', power == null ? '--' : '${power.toStringAsFixed(0)} W',
              DataSource.calculated, power != null),
          _Metric('Nhiệt độ NTC (°C)', ntcText ?? '--', DataSource.measured, ntcText != null),
          _Metric('Số chu kỳ sạc',
              live && p != null && p.cycles > 0 ? p.cycles.toStringAsFixed(0) : 'BMS không gửi',
              DataSource.measured, live && p != null && p.cycles > 0),
          _Metric('Nội trở',
              live && p != null && p.resistorMo > 0 ? '${p.resistorMo.toStringAsFixed(1)} mΩ' : 'BMS không gửi',
              DataSource.measured, live && p != null && p.resistorMo > 0),
          _Metric('Chênh áp giữa cell (Delta)',
              live && p != null && p.validCount >= 2 ? '${p.deltaMv.toStringAsFixed(1)} mV' : '--',
              DataSource.calculated, live && p != null && p.validCount >= 2),
          _Metric('Cell bất thường',
              live && p != null && p.hasCells ? '${p.abnormalCount} / ${p.cellCount}' : '--',
              DataSource.calculated, live && p != null && p.hasCells),
          _Metric('Cân bằng (BMS báo)',
              live && p != null ? (p.isBalancingReported ? 'ON' : 'OFF') : '--',
              DataSource.measured, live && p != null),
          // BMS không gửi SOH và app chưa có thuật toán SOH được xác minh,
          // nên KHÔNG hiển thị phần trăm tự suy ra (xem BatteryHealthReport.healthPercentage).
          const _Metric('Sức khỏe pin (SOH)',
              'Chưa đủ dữ liệu đánh giá sức khỏe pin',
              DataSource.unavailable, false),
        ]),
        const SizedBox(height: 14),
        const SectionHeader('Điện áp pack'),
        GlassCard(
          child: BmsLineChart(
            series: [
              ChartSeries(
                label: 'Điện áp pack (V)',
                values: history.packVoltage.values(),
                color: Bms.accent,
                fill: true,
              ),
            ],
            minSpan: 0.5,
            fractionDigits: 1,
            height: 140,
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Dòng BMS'),
        GlassCard(
          child: BmsLineChart(
            series: [
              ChartSeries(
                label: 'Dòng (A)',
                values: history.packCurrent.values(),
                color: Bms.accent2,
                fill: true,
              ),
            ],
            minSpan: 2,
            fractionDigits: 1,
            height: 130,
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Lịch sử sạc / xả'),
        _Sessions(sessions: hub.activitySessions),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ref.read(batteryHubProvider.notifier).resetSession(),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Đặt lại lịch sử phiên'),
            style: TextButton.styleFrom(foregroundColor: Bms.textDim),
          ),
        ),
        Text(
          'Lịch sử chỉ lưu trong bộ nhớ của phiên chạy này và mất khi đóng ứng dụng.',
          style: Bms.body(11, Bms.textFaint),
        ),
      ],
    );
  }

  Widget _grid(List<_Metric> items) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final m in items) SizedBox(width: w, child: _MetricCard(m))],
      );
    });
  }
}

class _Metric {
  final String label;
  final String value;
  final DataSource source;
  final bool available;
  final String? note;
  const _Metric(this.label, this.value, this.source, this.available, {this.note});
}

class _MetricCard extends StatelessWidget {
  final _Metric m;
  const _MetricCard(this.m);

  @override
  Widget build(BuildContext context) {
    final src = m.available ? m.source : DataSource.unavailable;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(m.label, style: Bms.body(11.5, Bms.textFaint))),
            SourceTag(src),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(m.value,
                style: Bms.number(m.available ? 19 : 14,
                    m.available ? (m.source == DataSource.estimated ? Bms.estimated : Bms.text) : Bms.textDim)),
          ),
          if (m.note != null && m.available) ...[
            const SizedBox(height: 4),
            Text(m.note!, style: Bms.body(10, Bms.textFaint)),
          ],
        ],
      ),
    );
  }
}

class _Sessions extends StatelessWidget {
  final List<ActivitySession> sessions;
  const _Sessions({required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return GlassCard(
        child: Text(
          'Chưa ghi nhận phiên sạc/xả nào. Hướng dòng lấy từ telemetry xe (quy ước dấu đã xác minh); '
          'chỉ ghi các phiên dài từ 20 giây.',
          style: Bms.body(12.5),
        ),
      );
    }
    final now = DateTime.now();
    String soc(double? v) => v == null ? '--' : '${v.toStringAsFixed(0)}%';
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < sessions.length && i < 15; i++) ...[
            if (i > 0) const Divider(color: Bms.border, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(
                    sessions[i].activity == PackActivity.charging
                        ? Icons.bolt_rounded
                        : Icons.speed_rounded,
                    color: sessions[i].activity == PackActivity.charging ? Bms.ok : Bms.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sessions[i].activity.label}${sessions[i].isOngoing ? ' (đang diễn ra)' : ''}'
                          ' · ${formatDuration(sessions[i].durationUntil(now))}',
                          style: Bms.body(12.5, Bms.text),
                        ),
                        Text(
                          '${formatClock(sessions[i].start)} · SOC ${soc(sessions[i].startSoc)} → ${soc(sessions[i].endSoc)}'
                          ' · ${sessions[i].startPackV.toStringAsFixed(1)} → ${sessions[i].endPackV.toStringAsFixed(1)} V'
                          ' · đỉnh ${sessions[i].peakCurrentA.toStringAsFixed(0)} A',
                          style: Bms.body(11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SocRingPainter extends CustomPainter {
  final double? fraction;
  _SocRingPainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    final f = fraction;
    if (f == null) return;
    final sweep = 2 * math.pi * f.clamp(0.0, 1.0);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Bms.accent2, Bms.accent, Bms.ok],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _SocRingPainter old) => old.fraction != fraction;
}
