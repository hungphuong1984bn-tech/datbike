// Mô hình khối pin trực quan: từng cell riêng biệt, chia nhóm, có ánh sáng/viền
// phát sáng theo trạng thái, hiệu ứng khi dữ liệu cập nhật và cảnh báo nhấp nháy.
//
// Hiệu năng: mỗi CellTile chỉ `select` đúng CellSnapshot của chính nó nên khi một
// cell đổi giá trị chỉ tile đó rebuild, không rebuild cả màn hình.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/battery/balancing_monitor.dart';
import '../../../core/battery/battery_hub.dart';
import '../../../core/battery/cell_model.dart';
import '../bms_theme.dart';
import '../cell_detail_screen.dart';

/// Số cell mỗi nhóm hiển thị. Chỉ để dễ đọc — KHÔNG phản ánh cấu trúc nối tiếp/
/// song song thật của bộ pin (giao thức không cung cấp thông tin này).
const int kCellGroupSize = 6;

enum CellFilter {
  all('Tất cả'),
  abnormal('Bất thường'),
  warning('Cảnh báo'),
  critical('Nghiêm trọng'),
  invalid('Dữ liệu lỗi');

  final String label;
  const CellFilter(this.label);

  bool accepts(CellSnapshot c) {
    switch (this) {
      case CellFilter.all:
        return true;
      case CellFilter.abnormal:
        return c.status != CellStatus.ok;
      case CellFilter.warning:
        return c.status == CellStatus.warning;
      case CellFilter.critical:
        return c.status == CellStatus.critical;
      case CellFilter.invalid:
        return c.status == CellStatus.invalid;
    }
  }
}

String _visibleKey(PackSnapshot? p, CellFilter f) {
  if (p == null) return '';
  final ids = [for (final c in p.cells) if (f.accepts(c)) c.index];
  return '${p.cellCount}:${ids.join(',')}';
}

class CellPackView extends ConsumerStatefulWidget {
  const CellPackView({super.key});

  @override
  ConsumerState<CellPackView> createState() => _CellPackViewState();
}

class _CellPackViewState extends ConsumerState<CellPackView>
    with SingleTickerProviderStateMixin {
  CellFilter _filter = CellFilter.all;
  late final AnimationController _alert;

  @override
  void initState() {
    super.initState();
    _alert = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _alert.dispose();
    super.dispose();
  }

  void _open(int index) {
    Navigator.of(context).push(Bms.route(CellDetailScreen(initialIndex: index)));
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(
      batteryHubProvider.select((s) => _visibleKey(s.latest, _filter)),
    );
    final cellCount = ref.watch(
      batteryHubProvider.select((s) => s.latest?.cellCount ?? 0),
    );

    final visible = <int>[];
    if (key.contains(':')) {
      final body = key.substring(key.indexOf(':') + 1);
      for (final part in body.split(',')) {
        if (part.isEmpty) continue;
        final i = int.tryParse(part);
        if (i != null) visible.add(i);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PackStatsStrip(),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in CellFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _filter == f ? Bms.bg : Bms.textDim,
                    ),
                    selectedColor: Bms.accent,
                    backgroundColor: Bms.glassFill,
                    side: const BorderSide(color: Bms.border),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (cellCount == 0)
          const _EmptyPack()
        else if (visible.isEmpty)
          GlassCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Không có cell nào khớp bộ lọc "${_filter.label}".',
                  style: Bms.body(13),
                ),
              ),
            ),
          )
        else
          _PackFrame(
            cellCount: cellCount,
            child: LayoutBuilder(
              builder: (context, c) {
                const cols = 3;
                const gap = 8.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;

                final groups = <int, List<int>>{};
                for (final i in visible) {
                  groups.putIfAbsent(i ~/ kCellGroupSize, () => <int>[]).add(i);
                }
                final keys = groups.keys.toList()..sort();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in keys) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: Text(
                          'NHÓM ${g + 1} · Cell ${(g * kCellGroupSize + 1).toString().padLeft(2, '0')}–'
                          '${((g + 1) * kCellGroupSize).clamp(1, cellCount).toString().padLeft(2, '0')}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Bms.textFaint,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final i in groups[g]!)
                            CellTile(
                              key: ValueKey('cell-$i'),
                              index: i,
                              width: w,
                              alert: _alert,
                              onTap: () => _open(i),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'Số lượng cell lấy đúng theo gói BMS nhận được ($cellCount cell). '
          'Việc chia nhóm chỉ để dễ đọc, không phản ánh cấu trúc vật lý của pack.',
          style: Bms.body(11, Bms.textFaint),
        ),
      ],
    );
  }
}

class _EmptyPack extends StatelessWidget {
  const _EmptyPack();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            const Icon(Icons.battery_unknown_rounded, size: 44, color: Bms.invalid),
            const SizedBox(height: 10),
            Text('Chưa có dữ liệu cell', style: Bms.title(15)),
            const SizedBox(height: 4),
            Text(
              'Ứng dụng không hiển thị cell giả. Mô hình pack sẽ xuất hiện khi BMS gửi điện áp từng cell.',
              textAlign: TextAlign.center,
              style: Bms.body(12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khung pack: khi BMS báo cờ cân bằng, viền khung phát sáng tím ở mức PACK.
class _PackFrame extends ConsumerWidget {
  final int cellCount;
  final Widget child;
  const _PackFrame({required this.cellCount, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancing = ref.watch(
      batteryHubProvider.select((s) => s.balancing == BalancingState.on),
    );
    final live = ref.watch(
      batteryHubProvider.select((s) => s.freshness == BmsFreshness.live),
    );
    final on = balancing && live;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.black.withValues(alpha: 0.28),
        border: Border.all(
          color: on ? Bms.accent2.withValues(alpha: 0.8) : Bms.border,
          width: on ? 1.6 : 1,
        ),
        boxShadow: on
            ? [BoxShadow(color: Bms.accent2.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -2)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_charging_full_rounded, size: 16, color: Bms.accent),
              const SizedBox(width: 6),
              Text('BỘ PIN · $cellCount cell', style: Bms.title(12.5)),
              const Spacer(),
              if (on)
                const StatusPill(
                  text: 'BMS báo cân bằng',
                  color: Bms.accent2,
                  icon: Icons.balance_rounded,
                ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _PackStatsStrip extends ConsumerWidget {
  const _PackStatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(batteryHubProvider.select((s) {
      final p = s.latest;
      if (p == null || !p.hasStats) return null;
      return (p.vMax, p.maxIndex, p.vMin, p.minIndex, p.vAvg, p.deltaMv, p.validCount);
    }));
    final live = ref.watch(
      batteryHubProvider.select((s) => s.freshness == BmsFreshness.live),
    );

    Widget box(String label, String value, String sub, Color color) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            borderRadius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Bms.body(10.5, Bms.textFaint)),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: Bms.number(17, live ? color : Bms.textDim)),
                ),
                Text(sub, style: Bms.body(10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );

    String cellNo(int i) => 'Cell ${(i + 1).toString().padLeft(2, '0')}';

    if (stats == null) {
      return Row(children: [
        box('CAO NHẤT', '--', 'V', Bms.text),
        const SizedBox(width: 8),
        box('THẤP NHẤT', '--', 'V', Bms.text),
        const SizedBox(width: 8),
        box('TRUNG BÌNH', '--', 'V', Bms.text),
        const SizedBox(width: 8),
        box('ΔV', '--', 'mV', Bms.text),
      ]);
    }
    final (vMax, maxIdx, vMin, minIdx, vAvg, delta, valid) = stats;
    return Row(children: [
      box('CAO NHẤT', vMax.toStringAsFixed(3), cellNo(maxIdx), Bms.warning),
      const SizedBox(width: 8),
      box('THẤP NHẤT', vMin.toStringAsFixed(3), cellNo(minIdx), Bms.accent),
      const SizedBox(width: 8),
      box('TRUNG BÌNH', vAvg.toStringAsFixed(3), '$valid cell', Bms.text),
      const SizedBox(width: 8),
      box('ΔV', delta.toStringAsFixed(1), 'mV', Bms.ok),
    ]);
  }
}

class CellTile extends ConsumerStatefulWidget {
  final int index;
  final double width;
  final Animation<double> alert;
  final VoidCallback onTap;

  const CellTile({
    super.key,
    required this.index,
    required this.width,
    required this.alert,
    required this.onTap,
  });

  @override
  ConsumerState<CellTile> createState() => _CellTileState();
}

class _CellTileState extends ConsumerState<CellTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double?>(
      batteryHubProvider.select((s) => s.cellAt(widget.index)?.voltage),
      (prev, next) {
        if (prev != null && next != null && prev != next) {
          _flash.forward(from: 0);
        }
      },
    );

    final cell = ref.watch(
      batteryHubProvider.select((s) => s.cellAt(widget.index)),
    );
    final live = ref.watch(
      batteryHubProvider.select((s) => s.freshness == BmsFreshness.live),
    );

    if (cell == null) return SizedBox(width: widget.width);

    final color = Bms.cellColor(cell.status);
    final alerting = live &&
        (cell.status == CellStatus.warning || cell.status == CellStatus.critical);
    final devText = cell.valid
        ? '${cell.deviationMv >= 0 ? '+' : ''}${cell.deviationMv.toStringAsFixed(1)} mV'
        : 'lỗi';

    Widget body(double pulse) {
      final glowAlpha = !live
          ? 0.0
          : (alerting ? 0.18 + 0.32 * pulse : (cell.status == CellStatus.ok ? 0.10 : 0.0));
      return AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        width: widget.width,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: live ? 0.20 : 0.07),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(
            color: color.withValues(alpha: live ? (alerting ? 0.55 + 0.35 * pulse : 0.40) : 0.20),
            width: alerting ? 1.6 : 1.1,
          ),
          boxShadow: glowAlpha <= 0
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: glowAlpha),
                    blurRadius: 14,
                    spreadRadius: alerting ? 1 : -2,
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(cell.label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Bms.textDim,
                    )),
                const Spacer(),
                if (cell.isMax) _tag('MAX', Bms.warning),
                if (cell.isMin) _tag('MIN', Bms.accent),
              ],
            ),
            const SizedBox(height: 6),
            if (cell.valid)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: cell.voltage),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: v.toStringAsFixed(3),
                      style: Bms.number(21, live ? Bms.text : Bms.textDim),
                    ),
                    TextSpan(text: ' V', style: Bms.body(11, Bms.textDim)),
                  ])),
                ),
              )
            else
              Text('--', style: Bms.number(21, Bms.invalid)),
            const SizedBox(height: 4),
            Text(devText, style: Bms.number(11.5, live ? color : Bms.textDim, FontWeight.w600)),
            const SizedBox(height: 7),
            _DeviationBar(
              deviationMv: cell.valid ? cell.deviationMv : 0,
              color: color,
              enabled: cell.valid && live,
            ),
          ],
        ),
      );
    }

    final tile = alerting
        ? AnimatedBuilder(animation: widget.alert, builder: (_, _) => body(widget.alert.value))
        : body(0);

    return Semantics(
      button: true,
      label: '${cell.label}, ${cell.valid ? '${cell.voltage.toStringAsFixed(3)} vôn' : 'dữ liệu lỗi'}, '
          '${cell.status.label}${live ? '' : ', dữ liệu không trực tiếp'}',
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            children: [
              tile,
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _flash,
                    builder: (_, _) {
                      final a = (1 - _flash.value) * 0.16;
                      if (_flash.isDismissed || a <= 0.001) return const SizedBox.shrink();
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withValues(alpha: a),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(t,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: c,
            )),
      );
}

/// Thanh lệch so với trung bình: tâm = trung bình, sang phải = cao hơn, trái = thấp hơn.
class _DeviationBar extends StatelessWidget {
  final double deviationMv;
  final Color color;
  final bool enabled;
  const _DeviationBar({
    required this.deviationMv,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    // Thang hiển thị ±60 mV chỉ để trực quan hoá; không phải ngưỡng cảnh báo.
    const scale = 60.0;
    final f = (deviationMv / scale).clamp(-1.0, 1.0);
    return SizedBox(
      height: 5,
      child: LayoutBuilder(builder: (context, c) {
        final half = c.maxWidth / 2;
        final len = half * f.abs();
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              left: f >= 0 ? half : half - len,
              width: enabled ? len : 0,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              left: half - 0.5,
              width: 1,
              top: -1,
              bottom: -1,
              child: Container(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        );
      }),
    );
  }
}
