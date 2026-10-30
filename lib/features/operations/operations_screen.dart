// Thông số vận hành — tốc độ, điện, nhiệt độ, bộ điều khiển, cảm biến, kết nối.
//
// Chỉ hiển thị số đo THẬT từ telemetry (bleProvider, chỉ đọc). Thiếu dữ liệu → "--".
// Hai đại lượng là TÍNH TOÁN và được ghi rõ: công suất điện = điện áp × |dòng pha|.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/battery/battery_history.dart' show Series;
import '../../core/ble/ble_controller.dart';
import '../../core/proto/bike_log.dart';
import '../../core/telemetry/ops_history.dart';
import '../../core/telemetry/ops_provider.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';

String bikeStateLabel(BikeState s) {
  switch (s) {
    case BikeState.off:
      return 'Đã tắt';
    case BikeState.standBy:
      return 'Chờ';
    case BikeState.parking:
      return 'Đỗ xe (P)';
    case BikeState.drive:
      return 'Chạy (D)';
    case BikeState.super_:
      return 'Thể thao (S)';
    case BikeState.cruiseControl:
      return 'Giữ ga';
    case BikeState.reverse:
      return 'Số lùi (R)';
    case BikeState.lock:
      return 'Đã khóa';
    case BikeState.turtle:
      return 'Tiết kiệm (E)';
  }
}

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _ChartDef {
  final String label;
  final String unit;
  final int decimals;
  final Color Function() color;
  final Series Function(OpsHistory) pick;
  const _ChartDef(this.label, this.unit, this.decimals, this.color, this.pick);
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  int _tab = 0;
  Timer? _clock;

  static final List<_ChartDef> _charts = [
    _ChartDef('Tốc độ', 'km/h', 0, () => AppColors.primary, (h) => h.speed),
    _ChartDef('Điện áp', 'V', 1, () => AppColors.cyan, (h) => h.voltage),
    _ChartDef('Dòng pha', 'A', 1, () => AppColors.amber, (h) => h.phaseA),
    _ChartDef('Công suất', 'W', 0, () => AppColors.tertiary, (h) => h.powerW),
    _ChartDef('Nhiệt độ pin', '°C', 1, () => AppColors.red, (h) => h.bmsTemp),
    _ChartDef('Nhiệt độ ECU', '°C', 1, () => AppColors.amber, (h) => h.ecuTemp),
    _ChartDef('Nhiệt độ động cơ', '°C', 1, () => AppColors.red, (h) => h.motorTemp),
  ];

  @override
  void initState() {
    super.initState();
    // Làm mới "dữ liệu mới nhận cách đây N giây" mỗi giây.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    ref.watch(opsProvider); // vẽ lại biểu đồ khi có mẫu mới
    final history = ref.read(opsProvider.notifier).history;
    final connected = ble.phase == BlePhase.connected;
    final t = connected ? ble.lastTelemetry : null;
    final lastAt = ref.read(bleProvider.notifier).lastTelemetryAt;

    return DsScaffold(
      title: 'Thông số vận hành',
      subtitle: 'Số đo trực tiếp từ bộ điều khiển và pin',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.pageH),
          child: Center(child: ConnectionBadge(phase: ble.phase)),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: [
          if (!connected)
            _pad(const StateView(
              kind: StateKind.offline,
              compact: true,
              title: 'Chưa kết nối xe',
              message:
                  'Thông số vận hành chỉ hiển thị khi kết nối BLE. Biểu đồ giữ lại số liệu của lần kết nối gần nhất.',
            ))
          else if (t == null)
            _pad(const StateView(
              kind: StateKind.loading,
              compact: true,
              title: 'Đang chờ dữ liệu từ xe',
              message: 'Chưa nhận được gói telemetry đầu tiên.',
            )),
          if (t != null && t.error != 0) ...[
            const SizedBox(height: AppSpacing.md),
            _pad(GlassCard(
              accent: AppColors.red,
              child: Row(
                children: [
                  Icon(Icons.error_rounded, color: AppColors.red),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Bộ điều khiển báo mã lỗi ${t.error}. Xem chi tiết trong Nhật ký và chẩn đoán.',
                      style: AppTypography.bodyMd(),
                    ),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: AppSpacing.md),
          _pad(_hero(t)),
          const DsSectionHeader('Điện',
              hint: 'Dòng pha dương = nạp vào pin, âm = xả ra'),
          _pad(_grid([
            MetricCard(
              icon: Icons.electric_meter_rounded,
              label: 'Điện áp pin',
              child: AnimatedMetric(
                  value: (t != null && t.voltage > 0) ? t.voltage : null,
                  decimals: 1,
                  unit: 'V',
                  valueSize: 24),
            ),
            MetricCard(
              icon: Icons.waves_rounded,
              label: 'Dòng pha',
              child: AnimatedMetric(
                  value: t?.phase, decimals: 1, unit: 'A', valueSize: 24),
            ),
            MetricCard(
              icon: Icons.bolt_rounded,
              label: 'Công suất điện (V × A)',
              child: AnimatedMetric(
                  value: (t != null && t.voltage > 0)
                      ? t.voltage * t.phase.abs()
                      : null,
                  unit: 'W',
                  valueSize: 24),
            ),
            MetricCard(
              icon: Icons.speed_rounded,
              label: 'Mở ga',
              child: AnimatedMetric(
                  value: t?.throttle, unit: '%', valueSize: 24),
            ),
          ])),
          const DsSectionHeader('Nhiệt độ'),
          _pad(_grid([
            MetricCard(
              icon: Icons.battery_full_rounded,
              label: 'Pin (BMS)',
              child: AnimatedMetric(
                  value: (t != null && t.bmsTemp > 0) ? t.bmsTemp : null,
                  decimals: 1,
                  unit: '°C',
                  valueSize: 24),
            ),
            MetricCard(
              icon: Icons.memory_rounded,
              label: 'Bộ điều khiển (ECU)',
              child: AnimatedMetric(
                  value: (t != null && t.ecu > 0) ? t.ecu : null,
                  decimals: 1,
                  unit: '°C',
                  valueSize: 24),
            ),
            MetricCard(
              icon: Icons.settings_rounded,
              label: 'Động cơ',
              child: AnimatedMetric(
                  value: (t != null && t.motor > 0) ? t.motor : null,
                  decimals: 1,
                  unit: '°C',
                  valueSize: 24),
            ),
          ])),
          const DsSectionHeader('Biểu đồ theo thời gian',
              hint: 'Lấy mẫu mỗi 2 giây, giữ khoảng 10 phút gần nhất'),
          _pad(_chartCard(history, connected)),
          const DsSectionHeader('Bộ điều khiển và cảm biến',
              hint: 'ADC là giá trị thô của cảm biến, chưa quy đổi đơn vị'),
          _pad(_sensorCard(t)),
          const DsSectionHeader('Kết nối'),
          _pad(_connectionCard(ble, lastAt)),
        ],
      ),
    );
  }

  Widget _pad(Widget c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        child: c,
      );

  Widget _hero(BikeLogMsg? t) {
    final on = t?.isBikeOn ?? false;
    return GlassCard(
      hero: true,
      accent: on ? AppColors.primary : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedMetric(
              value: t?.speed,
              unit: 'km/h',
              label: 'Tốc độ',
              valueSize: 56,
            ),
          ),
          if (t != null)
            StatusPill(
              label: bikeStateLabel(t.state),
              color: on ? AppColors.tertiary : AppColors.textMuted,
              pulse: on,
            ),
        ],
      ),
    );
  }

  Widget _grid(List<Widget> tiles) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chartCard(OpsHistory h, bool connected) {
    final def = _charts[_tab];
    final values = def.pick(h).values();
    final stats = SeriesStats.of(values);
    final color = def.color();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < _charts.length; i++)
                ChoiceChip(
                  label: Text(_charts[i].label),
                  selected: i == _tab,
                  onSelected: (_) => setState(() => _tab = i),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DsLineChart(
            values: values,
            color: color,
            unit: def.unit,
            decimals: def.decimals,
            animationKey: _tab,
            emptyText: connected
                ? 'Đang thu thập số liệu, biểu đồ sẽ hiện sau vài giây.'
                : 'Chưa có số liệu. Kết nối xe để bắt đầu ghi biểu đồ.',
            caption: connected ? 'Đang cập nhật' : 'Đã dừng (mất kết nối)',
          ),
          if (stats != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _stat('Thấp nhất', stats.min, def),
                _stat('Trung bình', stats.avg, def),
                _stat('Cao nhất', stats.max, def),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, double v, _ChartDef d) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: AppTypography.labelSm(color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text('${v.toStringAsFixed(d.decimals)} ${d.unit}',
                style: AppTypography.labelLg()),
          ],
        ),
      );

  Widget _sensorCard(BikeLogMsg? t) {
    final rows = <(String, String)>[
      ('Trạng thái bộ điều khiển', t == null ? '--' : bikeStateLabel(t.state)),
      (
        'Mã lỗi',
        t == null ? '--' : (t.error == 0 ? 'Không có lỗi' : 'Mã ${t.error}')
      ),
      (
        'Chân chống',
        t == null ? '--' : (t.isSideStandDown ? 'Đang hạ' : 'Đã nhấc')
      ),
      ('Đèn pha', t == null ? '--' : (t.headlight ? 'Bật' : 'Tắt')),
      (
        'Xi-nhan',
        t == null
            ? '--'
            : (t.left && t.right
                ? 'Cả hai bên'
                : t.left
                    ? 'Trái'
                    : t.right
                        ? 'Phải'
                        : 'Tắt')
      ),
      ('Cảm biến ADC 1 (thô)', t == null ? '--' : t.adc1.toStringAsFixed(2)),
      ('Cảm biến ADC 2 (thô)', t == null ? '--' : t.adc2.toStringAsFixed(2)),
      (
        'Quãng đường tổng',
        t == null ? '--' : '${t.odo.toStringAsFixed(1)} km'
      ),
    ];
    return GlassCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.panelBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].$1,
                        style: AppTypography.bodyMd(
                            color: AppColors.textSecondary)),
                  ),
                  Text(rows[i].$2, style: AppTypography.labelLg()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectionCard(BleState ble, DateTime? lastAt) {
    final connected = ble.phase == BlePhase.connected;
    String fresh;
    if (lastAt == null) {
      fresh = 'Chưa nhận gói nào';
    } else {
      final s = DateTime.now().difference(lastAt).inSeconds;
      fresh = s <= 1 ? 'Vừa nhận' : '$s giây trước';
    }
    return GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Trạng thái BLE',
                    style:
                        AppTypography.bodyMd(color: AppColors.textSecondary)),
              ),
              ConnectionBadge(phase: ble.phase),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Gói telemetry gần nhất',
                    style:
                        AppTypography.bodyMd(color: AppColors.textSecondary)),
              ),
              Text(fresh,
                  style: AppTypography.labelLg(
                      color: connected ? null : AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
