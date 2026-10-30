// Advanced Cell Balancing Monitor — CHỈ GIÁM SÁT.
//  • Không có đặc tính BLE nào để ghi lệnh cân bằng → app không điều khiển BMS.
//  • Không giả lập trạng thái cân bằng: ON/OFF lấy từ cờ `balancing` BMS gửi lên.
//  • Kiểu cân bằng (thụ động/chủ động) và cell nào đang cân bằng: chưa xác minh.
//  • Không có trường tiến trình → không hiển thị % tiến trình, chỉ ΔV trước/sau.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/battery/balancing_monitor.dart';
import '../../../core/battery/battery_hub.dart';
import '../../../core/battery/cell_model.dart';
import '../../../core/battery/cell_protection_engine.dart';
import '../bms_theme.dart';
import '../cell_detail_screen.dart';
import '../widgets/bms_charts.dart';

class BalancingView extends ConsumerWidget {
  const BalancingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(batteryHubProvider);
    ref.watch(batteryHubProvider.select((s) => s.revision));
    final history = ref.read(batteryHubProvider.notifier).history;
    final pack = hub.latest;
    final live = hub.freshness == BmsFreshness.live;
    final advice = BalancingAdvisor.advise(
      pack: pack,
      cfg: hub.config,
      freshness: hub.freshness,
    );

    final deltaSeries = history.deltaMv.values();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataStateBanner(freshness: hub.freshness, receivedAt: pack?.receivedAt),
        _StatusCard(hub: hub),
        const SizedBox(height: 14),
        const SectionHeader('Độ lệch điện áp (ΔV)'),
        _DeltaCard(hub: hub, live: live),
        const SizedBox(height: 14),
        const SectionHeader('Trước / sau cân bằng'),
        _BeforeAfterCard(hub: hub),
        const SizedBox(height: 14),
        const SectionHeader('So sánh điện áp các cell'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CellCompareChart(
                cells: pack?.cells ?? const <CellSnapshot>[],
                average: pack?.vAvg ?? 0,
                onSelect: pack == null
                    ? null
                    : (i) => Navigator.of(context)
                        .push(Bms.route(CellDetailScreen(initialIndex: i))),
              ),
              const SizedBox(height: 6),
              Text('Chạm một cột để xem chi tiết cell. Trục Y cắt quanh dữ liệu (không bắt đầu từ 0 V).',
                  style: Bms.body(11, Bms.textFaint)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('ΔV theo thời gian'),
        GlassCard(
          child: BmsLineChart(
            series: [
              ChartSeries(
                label: 'ΔV (mV)',
                values: deltaSeries,
                color: Bms.accent2,
                fill: true,
              ),
            ],
            minSpan: 4,
            fractionDigits: 0,
            unit: '',
            height: 140,
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Khuyến nghị'),
        _AdviceCard(advice: advice),
        const SizedBox(height: 14),
        const SectionHeader('Nhật ký cân bằng'),
        _EventLog(events: hub.balancingEvents),
        const SizedBox(height: 14),
        const _LimitationsCard(),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BatteryHubState hub;
  const _StatusCard({required this.hub});

  @override
  Widget build(BuildContext context) {
    final st = hub.balancing;
    final live = hub.freshness == BmsFreshness.live;
    final Color color;
    final String big;
    switch (st) {
      case BalancingState.on:
        color = Bms.accent2;
        big = 'Đang cân bằng';
      case BalancingState.off:
        color = Bms.textDim;
        big = 'Không cân bằng';
      case BalancingState.unknown:
        color = Bms.invalid;
        big = 'Không xác định';
    }
    final ongoing = hub.balancingEvents.isNotEmpty && hub.balancingEvents.first.isOngoing
        ? hub.balancingEvents.first
        : null;

    return GlassCard(
      blur: true,
      glow: (st == BalancingState.on && live) ? color : null,
      borderColor: color.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseIcon(active: st == BalancingState.on && live, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TRẠNG THÁI DO BMS BÁO', style: Bms.body(10.5, Bms.textFaint)),
                    const SizedBox(height: 2),
                    Text(big, style: Bms.number(24, color)),
                  ],
                ),
              ),
              const SourceTag(DataSource.measured),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FreshnessPill(hub.freshness),
              StatusPill(
                text: 'Kiểu: ${BalancingMethod.unverified.label}',
                color: Bms.warning,
                icon: Icons.help_outline_rounded,
              ),
              const StatusPill(
                text: 'Điều khiển từ app: không hỗ trợ',
                color: Bms.textDim,
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
          if (ongoing != null && live) ...[
            const SizedBox(height: 12),
            Text(
              'Đã báo cân bằng ${formatDuration(ongoing.durationUntil(DateTime.now()))} '
              '(từ ${formatClock(ongoing.start)}).',
              style: Bms.body(12.5, Bms.text),
            ),
          ],
          const SizedBox(height: 8),
          Text(BalancingMethod.unverified.explanation, style: Bms.body(11.5, Bms.textFaint)),
        ],
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final bool active;
  final Color color;
  const _PulseIcon({required this.active, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PulseIcon old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.12 + 0.12 * _c.value),
          border: Border.all(color: widget.color.withValues(alpha: 0.6), width: 1.4),
          boxShadow: widget.active
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.5 * _c.value), blurRadius: 22)]
              : null,
        ),
        child: Icon(Icons.balance_rounded, color: widget.color, size: 28),
      ),
    );
  }
}

class _DeltaCard extends StatelessWidget {
  final BatteryHubState hub;
  final bool live;
  const _DeltaCard({required this.hub, required this.live});

  @override
  Widget build(BuildContext context) {
    final p = hub.latest;
    final cfg = hub.config;
    if (p == null || p.validCount < 2) {
      return GlassCard(
        child: Text('Cần tối thiểu 2 cell hợp lệ từ BMS để tính ΔV.', style: Bms.body(12.5)),
      );
    }
    final d = p.deltaMv;
    final AlertSeverity sev = d >= cfg.deltaCritMv
        ? AlertSeverity.critical
        : (d >= cfg.deltaWarnMv ? AlertSeverity.warning : AlertSeverity.normal);
    final color = live ? Bms.severityColor(sev) : Bms.textDim;
    final String grade = sev == AlertSeverity.critical
        ? 'Lệch rất cao'
        : (sev == AlertSeverity.warning ? 'Lệch cao' : 'Đồng đều');

    String cellName(int i) => 'Cell ${(i + 1).toString().padLeft(2, '0')}';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(d.toStringAsFixed(1), style: Bms.number(40, color)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text('mV', style: Bms.number(16, Bms.textDim, FontWeight.w600)),
              ),
              const Spacer(),
              StatusPill(text: grade, color: color),
              const SizedBox(width: 6),
              const SourceTag(DataSource.calculated),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _cellStat('Cao nhất', cellName(p.maxIndex), p.vMax, Bms.warning),
              ),
              Expanded(
                child: _cellStat('Thấp nhất', cellName(p.minIndex), p.vMin, Bms.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Phân loại theo ngưỡng cấu hình: WARNING ≥ ${cfg.deltaWarnMv.toStringAsFixed(0)} mV, '
            'CRITICAL ≥ ${cfg.deltaCritMv.toStringAsFixed(0)} mV.',
            style: Bms.body(11, Bms.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _cellStat(String k, String cell, double v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Bms.body(11, Bms.textFaint)),
          const SizedBox(height: 2),
          Text('${v.toStringAsFixed(3)} V', style: Bms.number(17, c)),
          Text(cell, style: Bms.body(11.5)),
        ],
      );
}

class _BeforeAfterCard extends StatelessWidget {
  final BatteryHubState hub;
  const _BeforeAfterCard({required this.hub});

  @override
  Widget build(BuildContext context) {
    final events = hub.balancingEvents;
    if (events.isEmpty) {
      return GlassCard(
        child: Text(
          'Chưa ghi nhận lần BMS báo cân bằng nào trong phiên này. '
          'ΔV trước/sau chỉ hiển thị khi BMS thật sự báo cân bằng.',
          style: Bms.body(12.5),
        ),
      );
    }
    final e = events.first;
    final red = e.deltaReductionMv;
    String mv(double? v) => v == null ? '--' : '${v.toStringAsFixed(1)} mV';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.isOngoing ? 'Lần cân bằng đang diễn ra' : 'Lần cân bằng gần nhất',
              style: Bms.title(13.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _col('ΔV TRƯỚC', mv(e.deltaBeforeMv), Bms.warning)),
              const Icon(Icons.arrow_forward_rounded, color: Bms.textFaint),
              Expanded(
                child: _col(e.isOngoing ? 'ΔV HIỆN TẠI' : 'ΔV SAU', mv(e.deltaAfterMv), Bms.ok),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            red == null
                ? 'Không đủ số liệu để so sánh.'
                : (red >= 0
                    ? 'ΔV đã giảm ${red.toStringAsFixed(1)} mV so với lúc BMS bắt đầu báo cân bằng.'
                    : 'ΔV tăng ${(-red).toStringAsFixed(1)} mV so với lúc bắt đầu (có thể do tải/sạc).'),
            style: Bms.body(12.5, Bms.text),
          ),
          if (e.endReason == BalancingEndReason.linkLost) ...[
            const SizedBox(height: 4),
            Text('Sự kiện bị gián đoạn do mất kết nối — "sau" không phải kết quả cuối cùng.',
                style: Bms.body(11.5, Bms.warning)),
          ],
        ],
      ),
    );
  }

  Widget _col(String k, String v, Color c) => Column(
        children: [
          Text(k, style: Bms.body(10.5, Bms.textFaint)),
          const SizedBox(height: 3),
          Text(v, style: Bms.number(20, c)),
        ],
      );
}

class _AdviceCard extends StatelessWidget {
  final BalancingAdvice advice;
  const _AdviceCard({required this.advice});

  @override
  Widget build(BuildContext context) {
    final c = Bms.severityColor(advice.level);
    return GlassCard(
      borderColor: c.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: c, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(advice.headline, style: Bms.title(13.5, c))),
            ],
          ),
          const SizedBox(height: 8),
          for (final d in advice.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Bms.textFaint),
                    ),
                  ),
                  Expanded(child: Text(d, style: Bms.body(12.5, Bms.text))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  final List<BalancingEvent> events;
  const _EventLog({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return GlassCard(
        child: Text('Nhật ký trống: chưa có lần BMS báo cân bằng trong phiên này.',
            style: Bms.body(12.5)),
      );
    }
    final now = DateTime.now();
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < events.length && i < 20; i++) ...[
            if (i > 0) const Divider(color: Bms.border, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    events[i].isOngoing
                        ? Icons.sync_rounded
                        : (events[i].endReason == BalancingEndReason.linkLost
                            ? Icons.link_off_rounded
                            : Icons.check_circle_outline_rounded),
                    size: 18,
                    color: events[i].isOngoing ? Bms.accent2 : Bms.textDim,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatClock(events[i].start)} → '
                          '${events[i].end == null ? 'đang diễn ra' : formatClock(events[i].end!)}'
                          '  ·  ${formatDuration(events[i].durationUntil(now))}',
                          style: Bms.body(12.5, Bms.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ΔV ${events[i].deltaBeforeMv?.toStringAsFixed(1) ?? '--'} → '
                          '${events[i].deltaAfterMv?.toStringAsFixed(1) ?? '--'} mV'
                          '${events[i].endReason == BalancingEndReason.linkLost ? '  ·  gián đoạn do mất kết nối' : ''}',
                          style: Bms.body(11.5),
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

class _LimitationsCard extends StatelessWidget {
  const _LimitationsCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: Bms.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: Bms.textDim),
            const SizedBox(width: 8),
            Text('Giới hạn đã xác minh', style: Bms.title(13)),
          ]),
          const SizedBox(height: 8),
          for (final t in const [
            'Nhật ký pin của xe chỉ có quyền đọc; không có kênh nào được xác minh để ghi lệnh cân bằng. Ứng dụng không điều khiển BMS.',
            'Trường "balancing" chỉ được hiểu là BMS đang/không báo cân bằng ở cấp pack. Ý nghĩa từng bit (cell nào) chưa có tài liệu nên không hiển thị theo cell.',
            'Cân bằng thụ động hay chủ động chưa xác định được từ giao thức; ứng dụng không suy đoán.',
            'BMS không gửi tiến trình cân bằng nên không có thanh % tiến trình — chỉ có ΔV trước/sau là số đo thật.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('•  $t', style: Bms.body(12)),
            ),
        ],
      ),
    );
  }
}
