// Battery Center — Điện áp & Dòng điện (số đo thật từ gói BMS).
// Hiển thị giá trị hiện tại + min/TB/max của ~10 phút gần nhất và hai biểu đồ.
// Dấu dòng điện do BMS báo, CHƯA xác minh chiều sạc/xả → không gắn nhãn "sạc/xả".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/battery/battery_hub.dart';
import '../../../core/battery/cell_model.dart';
import '../../../core/telemetry/ops_history.dart' show SeriesStats;
import '../bms_theme.dart';
import '../widgets/bms_charts.dart';

class ElectricalView extends ConsumerWidget {
  const ElectricalView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(batteryHubProvider);
    ref.watch(batteryHubProvider.select((s) => s.revision));
    final history = ref.read(batteryHubProvider.notifier).history;
    final p = hub.latest;
    final live = hub.freshness == BmsFreshness.live;

    final volts = history.packVoltage.values();
    final amps = history.packCurrent.values();
    final vNow = (live && p != null && p.packVoltage > 0) ? p.packVoltage : null;
    final iNow = (live && p != null) ? p.current : null;
    final powerNow = (vNow != null && iNow != null) ? (vNow * iNow).abs() : null;
    final vs = SeriesStats.of(volts);
    final isx = SeriesStats.of(amps);

    String f(double? v, int d, String u) => v == null ? '--' : '${v.toStringAsFixed(d)} $u';

    Widget stat(String label, String value, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Bms.body(11, Bms.textFaint)),
              const SizedBox(height: 2),
              Text(value, style: Bms.title(15, c)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!live)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Text(
                'Chưa có gói BMS mới — giá trị hiện tại hiển thị "--". Biểu đồ giữ số liệu của phiên gần nhất.',
                style: Bms.body(12.5, Bms.warning),
              ),
            ),
          ),
        const SectionHeader('Điện áp pack'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                stat('Hiện tại', f(vNow, 2, 'V'), Bms.accent),
                stat('Thấp nhất', f(vs?.min, 2, 'V'), Bms.text),
                stat('Trung bình', f(vs?.avg, 2, 'V'), Bms.text),
                stat('Cao nhất', f(vs?.max, 2, 'V'), Bms.text),
              ]),
              const SizedBox(height: 12),
              BmsLineChart(
                series: [
                  ChartSeries(label: 'Điện áp pack (V)', values: volts, color: Bms.accent, fill: true),
                ],
                minSpan: 0.5,
                fractionDigits: 1,
                unit: 'V',
                height: 150,
                leftCaption: '≈ 10 phút trước',
                rightCaption: 'Bây giờ',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Dòng điện BMS'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                stat('Hiện tại', f(iNow, 1, 'A'), Bms.accent2),
                stat('Nhỏ nhất', f(isx?.min, 1, 'A'), Bms.text),
                stat('Trung bình', f(isx?.avg, 1, 'A'), Bms.text),
                stat('Lớn nhất', f(isx?.max, 1, 'A'), Bms.text),
              ]),
              const SizedBox(height: 12),
              BmsLineChart(
                series: [
                  ChartSeries(label: 'Dòng (A)', values: amps, color: Bms.accent2, fill: true),
                ],
                minSpan: 2,
                fractionDigits: 1,
                unit: 'A',
                height: 150,
                leftCaption: '≈ 10 phút trước',
                rightCaption: 'Bây giờ',
              ),
              const SizedBox(height: 8),
              Text(
                'Dấu (+/−) là dấu BMS báo. Ứng dụng chưa xác minh chiều sạc/xả nên không gắn nhãn.',
                style: Bms.body(11, Bms.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('Công suất tức thời'),
        GlassCard(
          child: Row(children: [
            stat('|V × I| (tính toán)', f(powerNow, 0, 'W'), Bms.text),
          ]),
        ),
      ],
    );
  }
}
