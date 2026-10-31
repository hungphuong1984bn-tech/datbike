// Lịch sử pin theo ngày / tuần / tháng (Giai đoạn 2F).
//
// Dữ liệu đọc từ BatteryHistoryStore: chỉ gồm gói BMS thật, đã ghi khi xe kết nối.
// Khoảng không có mẫu được BỎ QUA trên biểu đồ (không nội suy, không điền số giả).

import 'package:flutter/material.dart';

import '../../../core/battery/battery_history_store.dart';
import '../bms_theme.dart';
import '../widgets/bms_charts.dart';

class BatteryHistoryView extends StatefulWidget {
  /// Cho phép tiêm kho dữ liệu khi kiểm thử; mặc định dùng kho thật.
  final BatteryHistoryStore? store;
  const BatteryHistoryView({super.key, this.store});

  @override
  State<BatteryHistoryView> createState() => _BatteryHistoryViewState();
}

class _BatteryHistoryViewState extends State<BatteryHistoryView> {
  late final BatteryHistoryStore _store = widget.store ?? BatteryHistoryStore();
  HistoryRange _range = HistoryRange.day;
  List<BatteryHistoryRecord> _records = const <BatteryHistoryRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _store.load();
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _label(DateTime d) =>
      _range == HistoryRange.day ? '${_two(d.hour)}:00' : '${_two(d.day)}/${_two(d.month)}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: Bms.accent)),
      );
    }

    final header = SectionHeader(
      'Lịch sử pin đã lưu',
      trailing: IconButton(
        tooltip: 'Tải lại lịch sử',
        visualDensity: VisualDensity.compact,
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded, size: 18, color: Bms.textDim),
      ),
    );

    if (_records.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          GlassCard(
            child: Text(
              'Chưa có lịch sử pin được lưu (hoặc không đọc được tệp lịch sử). '
              'Dữ liệu chỉ được ghi khi xe kết nối và BMS gửi gói dữ liệu.',
              style: Bms.body(13, Bms.textDim),
            ),
          ),
        ],
      );
    }

    final buckets = BatteryHistoryAggregator.aggregate(_records, _range, DateTime.now());
    final withData = buckets.where((b) => b.hasData).length;
    final samples = buckets.fold<int>(0, (a, b) => a + b.count);
    final last = _records.last.at;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Wrap(
          spacing: 8,
          children: [
            for (final r in HistoryRange.values)
              ChoiceChip(
                label: Text(r.label),
                selected: r == _range,
                onSelected: (_) => setState(() => _range = r),
                selectedColor: Bms.accent.withValues(alpha: 0.25),
                backgroundColor: Bms.glassFill,
                labelStyle: Bms.body(12.5, r == _range ? Bms.accent : Bms.textDim),
                side: const BorderSide(color: Bms.border),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Khoảng ${_range.label.toLowerCase()}: $samples mẫu, có dữ liệu ở $withData/${buckets.length} khoảng. '
          'Mẫu gần nhất: ${_two(last.day)}/${_two(last.month)} ${_two(last.hour)}:${_two(last.minute)}.',
          style: Bms.body(12, Bms.textFaint),
        ),
        const SizedBox(height: 4),
        Text(
          'Mẫu thưa (khoảng 5 phút/mẫu), giá trị trung bình theo khoảng. Khoảng không có mẫu được bỏ qua, không nội suy.',
          style: Bms.body(11, Bms.textFaint),
        ),
        const SizedBox(height: 12),
        _chartCard(
          title: 'Điện áp pack (trung bình)',
          buckets: buckets,
          digits: 1,
          minSpan: 0.5,
          unit: 'V',
          lines: [
            _Line('Điện áp pack (V)', (b) => b.packVAvg, Bms.accent, fill: true),
          ],
        ),
        const SizedBox(height: 12),
        _chartCard(
          title: 'SOC (trung bình)',
          buckets: buckets,
          digits: 0,
          minSpan: 5,
          unit: '%',
          lines: [
            _Line('SOC (%)', (b) => b.socAvg, Bms.ok, fill: true),
          ],
        ),
        const SizedBox(height: 12),
        _chartCard(
          title: 'Nhiệt độ NTC cao nhất',
          buckets: buckets,
          digits: 1,
          minSpan: 2,
          unit: '°C',
          lines: [
            _Line('Nhiệt độ cao nhất (°C)', (b) => b.tempMax, Bms.warning),
          ],
        ),
        const SizedBox(height: 12),
        _chartCard(
          title: 'Chênh áp giữa cell (Delta)',
          buckets: buckets,
          digits: 1,
          minSpan: 5,
          unit: 'mV',
          lines: [
            _Line('Delta trung bình (mV)', (b) => b.deltaAvgMv, Bms.accent2),
            _Line('Delta lớn nhất (mV)', (b) => b.deltaMaxMv, Bms.critical),
          ],
        ),
      ],
    );
  }

  Widget _chartCard({
    required String title,
    required List<HistoryBucket> buckets,
    required int digits,
    required double minSpan,
    required String unit,
    required List<_Line> lines,
  }) {
    // Chỉ lấy các khoảng mà TẤT CẢ đường đều có giá trị để các đường thẳng hàng.
    final used = <HistoryBucket>[
      for (final b in buckets)
        if (b.hasData && lines.every((l) => l.value(b) != null)) b,
    ];
    final Widget body = used.length < 2
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Chưa đủ dữ liệu trong khoảng này để vẽ biểu đồ (BMS chưa gửi giá trị này hoặc có dưới 2 khoảng có mẫu).',
              style: Bms.body(12, Bms.textFaint),
            ),
          )
        : BmsLineChart(
            series: [
              for (final l in lines)
                ChartSeries(
                  label: l.label,
                  values: [for (final b in used) l.value(b)!],
                  color: l.color,
                  fill: l.fill,
                ),
            ],
            minSpan: minSpan,
            fractionDigits: digits,
            unit: unit,
            height: 140,
            leftCaption: _label(used.first.start),
            rightCaption: _label(used.last.start),
          );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Bms.title(14)),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

class _Line {
  final String label;
  final double? Function(HistoryBucket) value;
  final Color color;
  final bool fill;
  const _Line(this.label, this.value, this.color, {this.fill = false});
}
