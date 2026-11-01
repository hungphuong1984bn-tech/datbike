// Dải tổng quan BMS cố định phía trên các tab của "Bác sĩ Pin":
// SOC (BMS) · Điện áp pack · Dòng · Nhiệt độ (NTC cao nhất) · Δ cell.
//
// Chỉ ĐỌC gói BMS thật từ batteryHubProvider. Không có gói → "--" + nhãn độ mới.
// Δ cell chỉ tô đỏ khi vượt ngưỡng 30 mV đã dùng sẵn trong BatteryLogMsg.isDeltaCritical.
// Không gửi lệnh, không điều khiển cân bằng cell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/battery/battery_hub.dart';
import '../bms_theme.dart';

class BmsSummaryStrip extends ConsumerWidget {
  const BmsSummaryStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(batteryHubProvider.select((s) => s.latest));
    final freshness = ref.watch(batteryHubProvider.select((s) => s.freshness));

    double? maxTemp;
    if (snap != null) {
      for (final t in snap.ntcs) {
        if (t > 0 && (maxTemp == null || t > maxTemp)) maxTemp = t;
      }
    }
    final hasPack = snap != null;
    final deltaBad = snap != null && snap.hasStats && snap.deltaMv > 30.0;

    String fmt(double? v, int d) => v == null ? '--' : v.toStringAsFixed(d);

    final items = <_Item>[
      _Item('SOC (BMS)', snap != null ? fmt(snap.socPercent, 0) : '--', '%', Bms.text),
      _Item('Điện áp', snap != null && snap.packVoltage > 0 ? fmt(snap.packVoltage, 1) : '--', 'V', Bms.text),
      _Item('Dòng', snap != null ? fmt(snap.current, 1) : '--', 'A', Bms.text),
      _Item('Nhiệt độ', fmt(maxTemp, 0), '°C', Bms.text),
      _Item('Δ cell', snap != null && snap.hasStats ? fmt(snap.deltaMv, 0) : '--', 'mV',
          deltaBad ? Bms.critical : Bms.text),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Bms.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bms.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Tổng quan BMS',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Bms.textDim)),
              ),
              FreshnessPill(freshness),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [for (final i in items) Expanded(child: _Cell(item: i, dim: !hasPack))],
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _Item(this.label, this.value, this.unit, this.color);
}

class _Cell extends StatelessWidget {
  final _Item item;
  final bool dim;
  const _Cell({required this.item, required this.dim});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${item.label}: ${item.value == '--' ? 'chưa có dữ liệu' : '${item.value} ${item.unit}'}',
      excludeSemantics: true,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: dim ? Bms.textFaint : item.color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(item.unit,
              style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: Bms.textDim)),
          const SizedBox(height: 2),
          Text(item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: Bms.textDim)),
        ],
      ),
    );
  }
}
