// Tổng quan — Dòng điện, sạc pin và thông tin xe.
//
// Nguyên tắc dữ liệu (giống HomeHeroCard): CHỈ hiển thị giá trị xe/bộ sạc đã gửi thật.
// Thiếu dữ liệu hoặc chưa kết nối → "--". Không dùng số mẫu. Các giá trị suy ra
// (thời gian còn lại theo tốc độ sạc đo được) luôn gắn nhãn "Ước tính".
//
// Chỉ ĐỌC telemetry (bleProvider) và phiên sạc (chargeProvider); không gửi lệnh xuống xe,
// không đổi giao thức BLE hay logic tính pin/sạc. Quy ước dòng điện dùng lại đúng như
// Trung tâm sạc: dòng "phase" > 0 khi đang sạc là dòng nạp; khi không sạc, |phase| là dòng xả.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/charging/charge_provider.dart';
import '../../core/charging/charge_session.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';

/// Dữ liệu thuần cho bảng năng lượng (dễ kiểm thử, không đọc BLE).
class OverviewEnergyData {
  final bool connected;
  final bool charging;
  final int? soc;

  final double? dischargeA;
  final double? chargeA;
  final double? dischargeW;
  final double? chargeW;

  // Phiên sạc đang chạy
  final DateTime? sessionStart;
  final double? sessionWh;
  final double? sessionStartSoc;
  final EtaEstimate? eta;

  // Phiên sạc gần nhất đã kết thúc
  final ChargeSession? lastSession;

  // Thông tin xe
  final double? odoKm;
  final double? motorTempC;
  final double? ecuTempC;
  final String? driveMode;

  const OverviewEnergyData({
    required this.connected,
    required this.charging,
    required this.soc,
    required this.dischargeA,
    required this.chargeA,
    required this.dischargeW,
    required this.chargeW,
    required this.sessionStart,
    required this.sessionWh,
    required this.sessionStartSoc,
    required this.eta,
    required this.lastSession,
    required this.odoKm,
    required this.motorTempC,
    required this.ecuTempC,
    required this.driveMode,
  });
}

/// Bộ đọc: nối telemetry + phiên sạc → [OverviewEnergyData] rồi dựng bảng.
class OverviewEnergySection extends ConsumerWidget {
  final VoidCallback onOpenCharging;
  const OverviewEnergySection({super.key, required this.onOpenCharging});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final charge = ref.watch(chargeProvider);
    final tracker = ref.read(chargeProvider.notifier).tracker;

    final connected = ble.phase == BlePhase.connected;
    final t = connected ? ble.lastTelemetry : null;

    final charging = t != null && (t.charging != null || t.phase > 0.5);
    final int? soc = t?.percent;
    final volt = (t != null && t.voltage > 0) ? t.voltage : null;

    double? dischargeA;
    double? chargeA;
    double? dischargeW;
    double? chargeW;
    if (t != null) {
      if (charging) {
        chargeA = t.phase > 0 ? t.phase : null;
        final w = ChargeCenter.powerOf(t);
        chargeW = w > 0 ? w : null;
      } else {
        dischargeA = t.phase.abs();
        dischargeW = volt != null ? volt * t.phase.abs() : null;
      }
    }

    final session = charging ? charge.ongoing : null;
    final eta = (charging && soc != null)
        ? tracker.eta(
            chargerEtaSec: t?.charging?.etaSec ?? 0,
            currentSoc: soc.toDouble())
        : null;

    final data = OverviewEnergyData(
      connected: connected,
      charging: charging,
      soc: soc,
      dischargeA: dischargeA,
      chargeA: chargeA,
      dischargeW: dischargeW,
      chargeW: chargeW,
      sessionStart: session?.start,
      sessionWh: session?.energyWh,
      sessionStartSoc: session?.startSoc,
      eta: eta,
      lastSession: charge.history.isEmpty ? null : charge.history.first,
      odoKm: (t != null && t.odo > 0) ? t.odo : null,
      motorTempC: (t != null && t.motor > 0) ? t.motor : null,
      ecuTempC: (t != null && t.ecu > 0) ? t.ecu : null,
      driveMode: (t != null && t.isBikeOn) ? t.drivingModeLabel : null,
    );
    return OverviewEnergyPanel(data: data, onOpenCharging: onOpenCharging);
  }
}

class OverviewEnergyPanel extends StatelessWidget {
  final OverviewEnergyData data;
  final VoidCallback onOpenCharging;
  const OverviewEnergyPanel({super.key, required this.data, required this.onOpenCharging});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Dòng điện & công suất'),
        const SizedBox(height: 6),
        _currentCard(),
        const SizedBox(height: 16),
        const SectionTitle('Sạc pin'),
        const SizedBox(height: 6),
        _chargeCard(),
        const SizedBox(height: 16),
        const SectionTitle('Thông tin xe'),
        const SizedBox(height: 6),
        _vehicleCard(),
      ],
    );
  }

  // ── Dòng xả / dòng nạp ──────────────────────────────────────────────
  Widget _currentCard() {
    final d = data;
    final mode = !d.connected
        ? ('Chưa kết nối', AppColors.textMuted)
        : d.charging
            ? ('Đang sạc', AppColors.tertiary)
            : ('Đang xả / nghỉ', AppColors.primary);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: mode.$2),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Trạng thái dòng điện',
                    style: AppTypography.labelLg(color: AppColors.textPrimary)),
              ),
              StatusPill(label: mode.$1, color: mode.$2, pulse: d.charging),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Dòng xả',
                  value: d.dischargeA,
                  unit: 'A',
                  decimals: 1,
                  accent: AppColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Dòng nạp',
                  value: d.chargeA,
                  unit: 'A',
                  decimals: 1,
                  accent: AppColors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.flash_on_rounded,
                  label: 'Công suất xả',
                  value: d.dischargeW,
                  unit: 'W',
                  accent: AppColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.power_rounded,
                  label: 'Công suất nạp',
                  value: d.chargeW,
                  unit: 'W',
                  accent: AppColors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d.connected
                ? 'Chỉ hiển thị chiều dòng điện đang diễn ra; chiều còn lại là "--". '
                    'Số liệu theo bộ điều khiển xe báo về.'
                : 'Kết nối xe để xem dòng xả, dòng nạp và công suất.',
            style: AppTypography.bodySm(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Sạc pin: thời gian đã sạc / còn lại ─────────────────────────────
  Widget _chargeCard() {
    final d = data;
    if (!d.connected) {
      return _chargeIdle(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Chưa kết nối xe',
        body: 'Kết nối xe để theo dõi thời gian sạc.',
      );
    }
    if (!d.charging) {
      final s = d.lastSession;
      return GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.power_off_rounded, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Xe không sạc',
                      style: AppTypography.labelLg(color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Thời gian sạc và thời gian còn lại sẽ hiển thị khi cắm sạc.',
                style: AppTypography.bodySm(color: AppColors.textSecondary)),
            if (s != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.55 : 0.8),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.panelBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_lastSessionText(s),
                          style: AppTypography.bodySm(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenCharging,
                icon: const Icon(Icons.ev_station_rounded, size: 18),
                label: const Text('Mở Trung tâm sạc'),
              ),
            ),
          ],
        ),
      );
    }

    // Đang sạc
    final soc = d.soc;
    final full = soc != null && soc >= 100;
    final eta = d.eta;
    return GlassCard(
      accent: AppColors.tertiary,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: TickBuilder(
        builder: (context, now) {
          final start = d.sessionStart;
          final elapsed = start == null ? null : now.difference(start);
          final startSoc = d.sessionStartSoc;
          final gain = (soc != null && startSoc != null) ? soc - startSoc : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.battery_charging_full_rounded,
                      size: 22, color: AppColors.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(full ? 'Pin đã đầy' : 'Đang sạc pin',
                        style: AppTypography.labelLg(color: AppColors.textPrimary)),
                  ),
                  Text(soc == null ? '--' : '$soc%',
                      style: AppTypography.evWide(fontSize: 20, letterSpacing: -0.3)),
                ],
              ),
              const SizedBox(height: 10),
              _ChargeBar(percent: soc),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TextTile(
                      icon: Icons.timer_outlined,
                      label: 'Đã sạc',
                      value: elapsed == null ? '--' : _clock(elapsed),
                      sub: start == null ? null : 'từ ${formatClock(start)}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TextTile(
                      icon: Icons.hourglass_bottom_rounded,
                      label: 'Còn lại để đầy',
                      value: full
                          ? '0 phút'
                          : (eta == null ? '--' : _humanDuration(eta.remaining)),
                      sub: full
                          ? null
                          : (eta == null
                              ? 'Đang thu thập dữ liệu'
                              : eta.source.label),
                      highlight: eta != null && !full,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TextTile(
                      icon: Icons.add_chart_rounded,
                      label: 'Pin tăng',
                      value: gain == null ? '--' : '+${gain.toStringAsFixed(0)}%',
                      sub: startSoc == null ? null : 'từ ${startSoc.toStringAsFixed(0)}%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TextTile(
                      icon: Icons.battery_charging_full_rounded,
                      label: 'Năng lượng đã nạp',
                      value: d.sessionWh == null ? '--' : _energy(d.sessionWh!),
                    ),
                  ),
                ],
              ),
              if (!full && eta == null) ...[
                const SizedBox(height: 10),
                Text(
                  'Bộ sạc chưa báo thời gian còn lại. Ứng dụng cần sạc thêm ít phút '
                  '(pin tăng tối thiểu ${ChargeTracker.rateMinGainPct.toStringAsFixed(0)}%) '
                  'để ước tính theo tốc độ thực.',
                  style: AppTypography.bodySm(color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenCharging,
                  icon: const Icon(Icons.ev_station_rounded, size: 18),
                  label: const Text('Xem biểu đồ & lịch sử sạc'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chargeIdle({required IconData icon, required String title, required String body}) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.labelLg(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: AppTypography.bodySm(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Thông tin xe ────────────────────────────────────────────────────
  Widget _vehicleCard() {
    final d = data;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.route_rounded,
                  label: 'Tổng quãng đường (ODO)',
                  value: d.odoKm,
                  unit: 'km',
                  decimals: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TextTile(
                  icon: Icons.two_wheeler_rounded,
                  label: 'Chế độ lái',
                  value: d.driveMode ?? '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.thermostat_rounded,
                  label: 'Nhiệt độ động cơ',
                  value: d.motorTempC,
                  unit: '°C',
                  decimals: 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.memory_rounded,
                  label: 'Nhiệt độ bộ điều khiển',
                  value: d.ecuTempC,
                  unit: '°C',
                  decimals: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Định dạng ───────────────────────────────────────────────────────
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 01:25:07
  static String _clock(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
  }

  /// "1 giờ 25 phút" / "42 phút" / "< 1 phút"
  static String _humanDuration(Duration d) {
    final m = (d.inSeconds / 60).round();
    if (m < 1) return '< 1 phút';
    if (m < 60) return '$m phút';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h giờ' : '$h giờ ${_two(r)} phút';
  }

  static String _energy(double wh) =>
      wh >= 1000 ? '${(wh / 1000).toStringAsFixed(2)} kWh' : '${wh.toStringAsFixed(0)} Wh';

  static String _lastSessionText(ChargeSession s) {
    final end = s.end ?? s.start;
    final dur = end.difference(s.start);
    final when = '${_two(s.start.day)}/${_two(s.start.month)} ${_two(s.start.hour)}:${_two(s.start.minute)}';
    final gain = s.socGain;
    final parts = <String>[
      'Lần sạc gần nhất: $when',
      _humanDuration(dur),
      if (gain != null) '+${gain.toStringAsFixed(0)}%',
      if (s.energyWh > 0) _energy(s.energyWh),
    ];
    return parts.join(' · ');
  }
}

/// Ô số liệu có đơn vị. value null → "--".
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final Color? accent;

  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.decimals = 0,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.55 : 0.8),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: v == null ? AppColors.textMuted : (accent ?? AppColors.textSecondary)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMetric(
              value: v,
              decimals: decimals,
              unit: unit,
              valueSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô số liệu dạng chữ (thời gian, chế độ…).
class _TextTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final bool highlight;

  const _TextTile({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final none = value == '--';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: AppColors.isDark ? 0.55 : 0.8),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: highlight ? AppColors.tertiary.withValues(alpha: 0.6) : AppColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: none ? AppColors.textMuted : AppColors.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTypography.evWide(
                    fontSize: 20,
                    letterSpacing: -0.3,
                    color: none ? AppColors.textMuted : null)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSm(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _ChargeBar extends StatelessWidget {
  final int? percent;
  const _ChargeBar({required this.percent});

  @override
  Widget build(BuildContext context) {
    final frac = ((percent ?? 0) / 100.0).clamp(0.0, 1.0);
    return Semantics(
      label: percent == null ? 'Chưa có mức pin' : 'Mức pin $percent%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          height: 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.surfaceContainerHigh),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: frac,
                child: ColoredBox(color: AppColors.tertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
