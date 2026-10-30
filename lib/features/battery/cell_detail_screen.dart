// Màn hình chi tiết từng cell: điện áp hiện tại, cực trị phiên, đồ thị lịch sử,
// so sánh với trung bình pack, cảnh báo liên quan và trạng thái dữ liệu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/battery/balancing_monitor.dart';
import '../../core/battery/battery_history.dart';
import '../../core/battery/battery_hub.dart';
import '../../core/battery/cell_model.dart';
import '../../core/battery/cell_protection_engine.dart';
import 'bms_theme.dart';
import 'widgets/bms_charts.dart';
import 'widgets/cell_pack_view.dart' show kCellGroupSize;

class CellDetailScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const CellDetailScreen({super.key, required this.initialIndex});

  @override
  ConsumerState<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends ConsumerState<CellDetailScreen> {
  late int _index = widget.initialIndex;
  bool _longRange = false;

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + delta + count) % count);
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(batteryHubProvider);
    final pack = hub.latest;
    final count = pack?.cellCount ?? 0;
    final cell = pack?.cellAt(_index);
    final live = hub.freshness == BmsFreshness.live;
    final history = ref.read(batteryHubProvider.notifier).history;

    return Scaffold(
      backgroundColor: Bms.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Bms.text,
        centerTitle: true,
        title: Text(cell?.label ?? 'Cell ${(_index + 1).toString().padLeft(2, '0')}',
            style: Bms.title(18)),
        actions: [
          IconButton(
            tooltip: 'Cell trước',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: count > 1 ? () => _move(-1, count) : null,
          ),
          IconButton(
            tooltip: 'Cell sau',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: count > 1 ? () => _move(1, count) : null,
          ),
        ],
      ),
      body: BmsBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              DataStateBanner(freshness: hub.freshness, receivedAt: pack?.receivedAt),
              if (cell == null)
                const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Không có dữ liệu cho cell này trong gói BMS hiện tại.',
                          style: TextStyle(color: Bms.textDim)),
                    ),
                  ),
                )
              else ...[
                _hero(cell, pack!, hub, live),
                const SizedBox(height: 14),
                _infoGrid(cell, pack, hub, history),
                const SizedBox(height: 14),
                const SectionHeader('Lịch sử điện áp'),
                _historyCard(history, cell),
                const SizedBox(height: 14),
                const SectionHeader('So sánh với toàn bộ cell'),
                _compareCard(cell, pack),
                const SizedBox(height: 14),
                const SectionHeader('Cảnh báo liên quan'),
                _alertsCard(hub, cell),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(CellSnapshot cell, PackSnapshot pack, BatteryHubState hub, bool live) {
    final color = Bms.cellColor(cell.status);
    return GlassCard(
      blur: true,
      glow: live ? color : null,
      borderColor: color.withValues(alpha: live ? 0.5 : 0.2),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              StatusPill(text: cell.status.label, color: color, icon: Icons.bolt_rounded),
              const SizedBox(width: 8),
              FreshnessPill(hub.freshness),
              const Spacer(),
              const SourceTag(DataSource.measured),
            ],
          ),
          const SizedBox(height: 18),
          if (cell.valid) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(cell.voltage.toStringAsFixed(3),
                    style: Bms.number(52, live ? Bms.text : Bms.textDim)),
                const SizedBox(width: 6),
                Text('V', style: Bms.number(22, Bms.textDim, FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 2),
            Text('${cell.millivolts.toStringAsFixed(0)} mV',
                style: Bms.number(16, Bms.textDim, FontWeight.w600)),
          ] else
            Text('Dữ liệu lỗi', style: Bms.number(28, Bms.invalid)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: Bms.textFaint),
              const SizedBox(width: 5),
              Text(formatClock(pack.receivedAt), style: Bms.body(12)),
              const Text('  ·  ', style: TextStyle(color: Bms.textFaint)),
              AgeText(at: pack.receivedAt),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(CellSnapshot cell, PackSnapshot pack, BatteryHubState hub, BatteryHistory history) {
    final count = pack.cellCount;
    final group = _index ~/ kCellGroupSize + 1;

    // Xếp hạng theo điện áp giảm dần trong các cell hợp lệ (1 = cao nhất).
    int? rank;
    if (cell.valid) {
      final sorted = pack.cells.where((c) => c.valid).toList()
        ..sort((a, b) => b.voltage.compareTo(a.voltage));
      rank = sorted.indexWhere((c) => c.index == cell.index) + 1;
    }

    final mx = history.maxOf(_index);
    final mn = history.minOf(_index);

    final String balText;
    final Color balColor;
    switch (hub.balancing) {
      case BalancingState.on:
        balText = 'BMS báo đang cân bằng (cấp pack, không rõ cell nào)';
        balColor = Bms.accent2;
      case BalancingState.off:
        balText = 'BMS không báo cân bằng';
        balColor = Bms.textDim;
      case BalancingState.unknown:
        balText = 'Chưa rõ (không có dữ liệu trực tiếp)';
        balColor = Bms.invalid;
    }

    Widget item(String k, String v, {Color? color, DataSource? src}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(k, style: Bms.body(11, Bms.textFaint))),
                if (src != null) ...[const SizedBox(width: 4), SourceTag(src)],
              ]),
              const SizedBox(height: 3),
              Text(v, style: Bms.number(15, color ?? Bms.text, FontWeight.w600)),
            ],
          ),
        );

    final dev = cell.valid
        ? '${cell.deviationMv >= 0 ? '+' : ''}${cell.deviationMv.toStringAsFixed(1)} mV'
        : '--';

    return GlassCard(
      child: Column(
        children: [
          Row(children: [
            item('Vị trí trong pack', '${cell.number} / $count · Nhóm $group'),
            item('Lệch so với TB', dev,
                color: Bms.cellColor(cell.status), src: DataSource.calculated),
          ]),
          const Divider(color: Bms.border, height: 22),
          Row(children: [
            item('Điện áp TB toàn pack',
                pack.hasStats ? '${pack.vAvg.toStringAsFixed(3)} V' : '--',
                src: DataSource.calculated),
            item('Xếp hạng (1 = cao nhất)', rank == null ? '--' : '#$rank / ${pack.validCount}',
                src: DataSource.calculated),
          ]),
          const Divider(color: Bms.border, height: 22),
          Row(children: [
            item('Cao nhất phiên',
                mx == null ? '--' : '${mx.voltage.toStringAsFixed(3)} V · ${formatClock(mx.at)}'),
            item('Thấp nhất phiên',
                mn == null ? '--' : '${mn.voltage.toStringAsFixed(3)} V · ${formatClock(mn.at)}'),
          ]),
          const Divider(color: Bms.border, height: 22),
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trạng thái cân bằng', style: Bms.body(11, Bms.textFaint)),
                  const SizedBox(height: 3),
                  Text(balText, style: Bms.body(13, balColor)),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _historyCard(BatteryHistory history, CellSnapshot cell) {
    // Đọc lịch sử trực tiếp (đã được hub cập nhật), vẽ lại theo `revision`.
    final cellSeries = history.cellSeries(_index, longRange: _longRange);
    final avgSeries = _longRange ? history.avgCellLong : history.avgCell;

    final values = cellSeries?.values() ?? <double>[];
    final times = cellSeries?.times() ?? <DateTime>[];

    final avgMap = <int, double>{};
    final avgTimes = avgSeries.times();
    final avgVals = avgSeries.values();
    for (var i = 0; i < avgTimes.length; i++) {
      avgMap[avgTimes[i].millisecondsSinceEpoch] = avgVals[i];
    }
    final avgAligned = <double>[];
    final cellAligned = <double>[];
    for (var i = 0; i < times.length; i++) {
      final a = avgMap[times[i].millisecondsSinceEpoch];
      if (a != null) {
        avgAligned.add(a);
        cellAligned.add(values[i]);
      }
    }

    final span = times.length >= 2 ? times.last.difference(times.first) : Duration.zero;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Điện áp theo thời gian', style: Bms.title(13.5)),
              const Spacer(),
              _rangeChip('10 phút', !_longRange, () => setState(() => _longRange = false)),
              const SizedBox(width: 6),
              _rangeChip('2 giờ', _longRange, () => setState(() => _longRange = true)),
            ],
          ),
          const SizedBox(height: 10),
          BmsLineChart(
            series: [
              ChartSeries(
                label: cell.label,
                values: cellAligned,
                color: Bms.accent,
                fill: true,
              ),
              ChartSeries(
                label: 'Trung bình pack',
                values: avgAligned,
                color: Bms.textDim,
                dashed: true,
              ),
            ],
            unit: '',
            leftCaption: times.isEmpty ? null : formatClock(times.first),
            rightCaption: times.isEmpty ? null : formatClock(times.last),
          ),
          const SizedBox(height: 6),
          Text(
            times.length < 2
                ? 'Lịch sử chỉ gồm các gói BMS thật nhận được trong phiên này.'
                : 'Khoảng ${formatDuration(span)} · ${times.length} mẫu BMS thật. Trục Y cắt quanh dữ liệu (không bắt đầu từ 0 V).',
            style: Bms.body(11, Bms.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Bms.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Bms.accent : Bms.border),
        ),
        child: Text(text, style: Bms.body(11.5, selected ? Bms.accent : Bms.textDim)),
      ),
    );
  }

  Widget _compareCard(CellSnapshot cell, PackSnapshot pack) {
    final diff = cell.valid ? cell.deviationMv : 0.0;
    final word = diff.abs() < 0.5
        ? 'ngang trung bình'
        : (diff > 0 ? 'cao hơn trung bình' : 'thấp hơn trung bình');
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cell.valid
                ? '${cell.label} $word ${diff.abs().toStringAsFixed(1)} mV'
                : '${cell.label}: dữ liệu lỗi, không so sánh được',
            style: Bms.title(13.5),
          ),
          const SizedBox(height: 10),
          CellCompareChart(
            cells: pack.cells,
            average: pack.vAvg,
            selectedIndex: _index,
            onSelect: (i) => setState(() => _index = i),
          ),
          const SizedBox(height: 6),
          Text('Chạm một cột để chuyển sang cell đó. Vạch đứt = điện áp trung bình.',
              style: Bms.body(11, Bms.textFaint)),
        ],
      ),
    );
  }

  Widget _alertsCard(BatteryHubState hub, CellSnapshot cell) {
    final related =
        hub.report.alerts.where((a) => a.cellIndices.contains(cell.index)).toList();
    if (related.isEmpty) {
      return GlassCard(
        child: Row(
          children: [
            Icon(
              hub.freshness == BmsFreshness.live
                  ? Icons.verified_rounded
                  : Icons.help_outline_rounded,
              color: hub.freshness == BmsFreshness.live ? Bms.ok : Bms.invalid,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hub.freshness == BmsFreshness.live
                    ? 'Không có cảnh báo nào liên quan đến ${cell.label}.'
                    : 'Không đánh giá cảnh báo khi dữ liệu không còn trực tiếp.',
                style: Bms.body(13),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final a in related)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AlertMini(alert: a),
          ),
      ],
    );
  }
}

class _AlertMini extends StatelessWidget {
  final ProtectionAlert alert;
  const _AlertMini({required this.alert});

  @override
  Widget build(BuildContext context) {
    final c = Bms.severityColor(alert.severity);
    return GlassCard(
      borderColor: c.withValues(alpha: 0.5),
      glow: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            StatusPill(text: alert.severity.label, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(alert.title, style: Bms.title(13))),
          ]),
          const SizedBox(height: 8),
          Text(alert.measured, style: Bms.number(12.5, Bms.text, FontWeight.w500)),
          const SizedBox(height: 6),
          Text('Khuyến nghị: ${alert.recommendation}', style: Bms.body(12)),
        ],
      ),
    );
  }
}
