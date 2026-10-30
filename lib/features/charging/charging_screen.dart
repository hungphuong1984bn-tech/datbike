// Trung tâm sạc — thiết kế lại theo Design System v3.
//
// Mọi số liệu lấy từ telemetry THẬT của xe (bleProvider, chỉ đọc) và từ phiên sạc
// do ChargeTracker ghi nhận. Không có số liệu giả định: thiếu dữ liệu → "--".
// Lệnh chọn chế độ sạc giữ nguyên (setChargingProfile + setFwChargingProfile).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/charging/charge_provider.dart';
import '../../core/charging/charge_session.dart';
import '../../core/proto/bike_log.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';
import '../battery/battery_diagnostics_screen.dart';

class ChargingScreen extends ConsumerStatefulWidget {
  const ChargingScreen({super.key});

  @override
  ConsumerState<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends ConsumerState<ChargingScreen> {
  int _chartTab = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Làm mới đồng hồ "thời gian đã sạc" mỗi giây, chỉ khi có phiên đang chạy.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(chargeProvider).ongoing != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static const _tabs = <_ChartTab>[
    _ChartTab('Công suất', 'W', 0),
    _ChartTab('Điện áp', 'V', 1),
    _ChartTab('Dòng điện', 'A', 1),
    _ChartTab('SOC', '%', 0),
  ];

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final charge = ref.watch(chargeProvider);
    final tracker = ref.read(chargeProvider.notifier).tracker;

    final connected = ble.phase == BlePhase.connected;
    final tele = connected ? ble.lastTelemetry : null;
    final charging =
        tele != null && (tele.charging != null || tele.phase > 0.5);
    final session = charging ? charge.ongoing : null;

    final soc = tele?.percent.toDouble();
    final full = soc != null && soc >= 100;
    final eta = charging
        ? tracker.eta(
            chargerEtaSec: tele?.charging?.etaSec ?? 0, currentSoc: soc)
        : null;
    final fault = tele?.charging?.fault ?? 0;

    final Color tone = !connected
        ? AppColors.textMuted
        : charging
            ? AppColors.tertiary
            : AppColors.primary;

    return DsScaffold(
      title: 'Trung tâm sạc',
      subtitle: 'Theo dõi phiên sạc theo thời gian thực',
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
            _pad(StateView(
              kind: StateKind.offline,
              compact: true,
              title: 'Chưa kết nối xe',
              message:
                  'Số liệu sạc trực tiếp chỉ hiển thị khi kết nối BLE. Lịch sử phiên sạc bên dưới vẫn xem được.',
            ))
          else if (tele == null)
            _pad(StateView(
              kind: StateKind.loading,
              compact: true,
              title: 'Đang chờ dữ liệu từ xe',
              message: 'Chưa nhận được gói telemetry đầu tiên.',
            )),
          if (fault != 0) ...[
            const SizedBox(height: AppSpacing.md),
            _pad(GlassCard(
              accent: AppColors.red,
              child: Row(
                children: [
                  Icon(Icons.error_rounded, color: AppColors.red),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Bộ sạc báo mã lỗi $fault. Kiểm tra bộ sạc, cổng sạc và xem Trung tâm chẩn đoán.',
                      style: AppTypography.bodyMd(),
                    ),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: AppSpacing.md),
          _pad(_Hero(
            soc: soc,
            charging: charging,
            full: full,
            connected: connected,
            tone: tone,
            eta: eta,
            kmLeft: (tele != null && tele.kmLeft > 0) ? tele.kmLeft : null,
          )),
          const SizedBox(height: AppSpacing.md),
          _pad(_MetricGrid(
            tele: tele,
            charging: charging,
            session: session,
          )),
          const DsSectionHeader(
            'Biểu đồ sạc',
            hint: 'Lấy mẫu mỗi 2 giây, giữ khoảng 15 phút gần nhất',
          ),
          _pad(_chartCard(tracker, charging)),
          const DsSectionHeader(
            'Chế độ sạc',
            hint: 'Hồ sơ sạc ghi vào firmware của xe',
          ),
          _pad(_profileCard(ble, connected)),
          DsSectionHeader(
            'Lịch sử phiên sạc',
            hint: 'Lưu trên máy, tối đa ${ChargeTracker.maxSessions} phiên',
            trailing: charge.history.isEmpty
                ? null
                : TextButton(
                    onPressed: _confirmClear,
                    child: const Text('Xóa lịch sử'),
                  ),
          ),
          _pad(_historyCard(charge.history)),
          const SizedBox(height: AppSpacing.xl),
          _pad(SizedBox(
            height: 52,
            child: FilledButton.icon(
              icon: const Icon(Icons.battery_charging_full_rounded),
              label: const Text('Bác sĩ pin và chẩn đoán cell'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BatteryDiagnosticsScreen(),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        child: child,
      );

  Widget _chartCard(ChargeTracker tracker, bool charging) {
    final series = <List<double>>[
      tracker.power.values(),
      tracker.voltage.values(),
      tracker.current.values(),
      tracker.soc.values(),
    ];
    final colors = <Color>[
      AppColors.tertiary,
      AppColors.primary,
      AppColors.amber,
      AppColors.cyan,
    ];
    final tab = _tabs[_chartTab];
    final values = series[_chartTab];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                ChoiceChip(
                  label: Text('${_tabs[i].label} (${_tabs[i].unit})'),
                  selected: i == _chartTab,
                  onSelected: (_) => setState(() => _chartTab = i),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DsLineChart(
            values: values,
            color: colors[_chartTab],
            unit: tab.unit,
            decimals: tab.decimals,
            animationKey: _chartTab,
            minY: _chartTab == 3 ? 0 : null,
            maxY: _chartTab == 3 ? 100 : null,
            emptyText: 'Biểu đồ bắt đầu khi xe được cắm sạc.',
            caption: charging ? 'Phiên sạc đang chạy' : 'Phiên sạc gần nhất',
          ),
        ],
      ),
    );
  }

  Widget _profileCard(BleState ble, bool connected) {
    const names = ['Tiêu chuẩn', 'Sạc nhanh', 'Tăng tốc'];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < names.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ProfilePill(
                    label: names[i],
                    selected: ble.chargingProfile == i,
                    enabled: connected,
                    onTap: () => _setProfile(i),
                  ),
                ),
              ],
            ],
          ),
          if (!connected)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text('Kết nối xe để đổi chế độ sạc.',
                  style: AppTypography.bodySm(color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  Future<void> _setProfile(int p) async {
    final notifier = ref.read(bleProvider.notifier);
    notifier.setChargingProfile(p);
    final res = await notifier.setFwChargingProfile(p);
    if (!mounted) return;
    showAppSnack(context, res);
  }

  Widget _historyCard(List<ChargeSession> list) {
    if (list.isEmpty) {
      return const StateView(
        kind: StateKind.empty,
        compact: true,
        title: 'Chưa có phiên sạc nào',
        message:
            'Phiên sạc được ghi lại khi xe cắm sạc và ứng dụng đang kết nối (tối thiểu 1 phút).',
      );
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.panelBorder),
            _SessionRow(session: list[i]),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa lịch sử sạc?',
      message: 'Toàn bộ phiên sạc đã lưu trên máy sẽ bị xóa. Không thể hoàn tác.',
      confirmLabel: 'Xóa',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok) await ref.read(chargeProvider.notifier).clearHistory();
  }
}

class _ChartTab {
  final String label;
  final String unit;
  final int decimals;
  const _ChartTab(this.label, this.unit, this.decimals);
}

// ─────────────────────────────────────────────────────────────────────────────

String formatChargeDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s giây';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m phút';
  return '$h giờ ${m.toString().padLeft(2, '0')} phút';
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _dm(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

class _Hero extends StatelessWidget {
  final double? soc;
  final bool charging;
  final bool full;
  final bool connected;
  final Color tone;
  final EtaEstimate? eta;
  final double? kmLeft;

  const _Hero({
    required this.soc,
    required this.charging,
    required this.full,
    required this.connected,
    required this.tone,
    required this.eta,
    required this.kmLeft,
  });

  @override
  Widget build(BuildContext context) {
    final String status = !connected
        ? 'Chưa kết nối xe'
        : charging
            ? (full ? 'Đã đầy pin' : 'Đang sạc')
            : 'Chưa cắm sạc';

    String remaining;
    String finishAt;
    if (!charging) {
      remaining = '--';
      finishAt = '--';
    } else if (full) {
      remaining = '0 phút';
      finishAt = 'Đã đầy';
    } else if (eta == null) {
      remaining = 'Chưa đủ dữ liệu';
      finishAt = '--';
    } else {
      remaining = formatChargeDuration(eta!.remaining);
      final at = DateTime.now().add(eta!.remaining);
      final sameDay = at.day == DateTime.now().day;
      finishAt = sameDay ? _hm(at) : '${_hm(at)} (${_dm(at)})';
    }

    return GlassCard(
      hero: true,
      accent: charging ? AppColors.tertiary : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      semanticLabel: 'Trạng thái sạc: $status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusPill(
                label: status,
                color: tone,
                pulse: charging && !full,
                icon: charging ? Icons.bolt_rounded : null,
              ),
              const Spacer(),
              AnimatedMetric(
                value: connected ? soc : null,
                unit: '%',
                valueSize: 44,
                color: tone == AppColors.textMuted ? null : tone,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          EnergyBattery(
            percent: connected ? soc : null,
            charging: charging && !full,
            color: (soc ?? 101) <= 15
                ? AppColors.red
                : (soc ?? 101) <= 30
                    ? AppColors.amber
                    : AppColors.tertiary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: _kv('Thời gian còn lại', remaining)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _kv('Dự kiến đầy lúc', finishAt)),
            ],
          ),
          if (charging && eta != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                eta!.source == EtaSource.charger
                    ? 'Nguồn: bộ sạc của xe báo trực tiếp.'
                    : 'Nguồn: ${eta!.source.label}; có thể lâu hơn ở giai đoạn cuối khi dòng sạc giảm.',
                style: AppTypography.bodySm(color: AppColors.textSecondary),
              ),
            ),
          if (charging && eta == null && !full)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Bộ sạc chưa báo thời gian còn lại. Ứng dụng cần sạc thêm ít phút và tăng tối thiểu ${ChargeTracker.rateMinGainPct.toStringAsFixed(0)}% để ước tính theo tốc độ thực.',
                style: AppTypography.bodySm(color: AppColors.textSecondary),
              ),
            ),
          if (connected && kmLeft != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Quãng đường còn lại do xe báo: ${kmLeft!.round()} km',
                style: AppTypography.bodySm(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: AppTypography.labelMd(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(v, style: AppTypography.headlineSm()),
        ],
      );
}

class _MetricGrid extends StatelessWidget {
  final BikeLogMsg? tele;
  final bool charging;
  final ChargeSession? session;

  const _MetricGrid({
    required this.tele,
    required this.charging,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final t = tele;
    final double? powerW = (t != null && charging) ? ChargeCenter.powerOf(t) : null;
    final double? volt = (t != null && t.voltage > 0) ? t.voltage : null;
    final double? amp = (t != null && charging) ? (t.phase > 0 ? t.phase : 0.0) : null;
    final double? temp = (t != null && t.bmsTemp > 0) ? t.bmsTemp : null;

    final wh = session?.energyWh;
    final bool kwh = wh != null && wh >= 1000;

    final tiles = <Widget>[
      _Tile(
        icon: Icons.bolt_rounded,
        label: 'Công suất tức thời',
        child: AnimatedMetric(value: powerW, unit: 'W', valueSize: 24),
      ),
      _Tile(
        icon: Icons.electric_meter_rounded,
        label: 'Điện áp sạc',
        child: AnimatedMetric(value: volt, decimals: 1, unit: 'V', valueSize: 24),
      ),
      _Tile(
        icon: Icons.waves_rounded,
        label: 'Dòng điện sạc',
        child: AnimatedMetric(value: amp, decimals: 1, unit: 'A', valueSize: 24),
      ),
      _Tile(
        icon: Icons.thermostat_rounded,
        label: 'Nhiệt độ pin (BMS)',
        child: AnimatedMetric(value: temp, decimals: 1, unit: '°C', valueSize: 24),
      ),
      _Tile(
        icon: Icons.battery_charging_full_rounded,
        label: 'Năng lượng đã nạp',
        child: AnimatedMetric(
          value: wh == null ? null : (kwh ? wh / 1000 : wh),
          decimals: kwh ? 2 : 0,
          unit: kwh ? 'kWh' : 'Wh',
          valueSize: 24,
        ),
      ),
      _Tile(
        icon: Icons.timer_outlined,
        label: 'Thời gian đã sạc',
        child: Text(
          session == null ? '--' : formatChargeDuration(session!.durationUntil(DateTime.now())),
          style: AppTypography.headlineSm(
            color: session == null ? AppColors.textMuted : null,
          ),
        ),
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: tiles[i + 1]),
            ],
          ),
        ],
        if (session != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                session!.gapSeconds > 0
                    ? 'Năng lượng và thời gian tính từ lúc ứng dụng bắt đầu ghi nhận; đã bỏ qua ${session!.gapSeconds} giây mất dữ liệu.'
                    : 'Năng lượng và thời gian tính từ lúc ứng dụng bắt đầu ghi nhận phiên sạc.',
                style: AppTypography.bodySm(color: AppColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _Tile({required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTypography.labelMd(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ProfilePill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Chế độ sạc $label',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.panelSecondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.panelBorderBright,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelLg(
                color: !enabled
                    ? AppColors.textMuted
                    : selected
                        ? AppColors.primary
                        : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final ChargeSession session;
  const _SessionRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final dur = s.durationUntil(s.end ?? DateTime.now());
    final from = s.startSoc?.round();
    final to = s.endSoc?.round();
    final soc = (from != null && to != null) ? '$from% → $to%' : 'SOC không rõ';
    final e = s.energyWh >= 1000
        ? '${(s.energyWh / 1000).toStringAsFixed(2)} kWh'
        : '${s.energyWh.round()} Wh';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bolt_rounded, size: 20, color: AppColors.tertiary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_dm(s.start)} · ${_hm(s.start)}',
                    style: AppTypography.labelLg()),
                const SizedBox(height: 2),
                Text('$soc · ${formatChargeDuration(dur)}',
                    style: AppTypography.bodySm(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(e, style: AppTypography.labelLg()),
              const SizedBox(height: 2),
              Text('đỉnh ${s.peakPowerW.round()} W',
                  style: AppTypography.bodySm(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
