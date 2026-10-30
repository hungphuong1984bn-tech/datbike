// Trung tâm chẩn đoán — gom sức khỏe xe, danh sách lỗi, lịch sử lỗi và các nhật ký
// (hoạt động / Bluetooth / BMS) vào một nơi. Chỉ ĐỌC dữ liệu thật từ xe và BMS:
// không có lỗi mẫu, không suy đoán nguyên nhân ngoài bảng mô tả đã có trong ứng dụng.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/battery/balancing_monitor.dart';
import '../../core/battery/battery_hub.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/diagnostics/diag_model.dart';
import '../../core/diagnostics/diag_provider.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../logs/logs_screen.dart';

Severity _sev(DiagSeverity s) {
  switch (s) {
    case DiagSeverity.ok:
      return Severity.ok;
    case DiagSeverity.info:
      return Severity.info;
    case DiagSeverity.warning:
      return Severity.warning;
    case DiagSeverity.critical:
      return Severity.critical;
  }
}

enum _Tab {
  overview('Tổng quan'),
  issues('Lỗi hiện tại'),
  history('Lịch sử lỗi'),
  logs('Nhật ký');

  final String label;
  const _Tab(this.label);
}

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  _Tab _tab = _Tab.overview;
  DiagSource _logSource = DiagSource.activity;
  DiagSeverity? _historyFilter;

  @override
  Widget build(BuildContext context) {
    ref.watch(diagProvider); // dựng lại khi nhật ký thay đổi
    final log = ref.read(diagProvider.notifier).log;
    final phase = ref.watch(bleProvider.select((s) => s.phase));
    final hasLive = phase == BlePhase.connected &&
        ref.watch(bleProvider.select((s) => s.lastTelemetry != null));

    return DsScaffold(
      title: 'Chẩn đoán',
      subtitle: 'Sức khỏe xe, lỗi và nhật ký',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.pageH),
          child: Center(child: ConnectionBadge(phase: phase)),
        ),
      ],
      body: Column(
        children: [
          _TabBar(
            selected: _tab,
            issueCount: log.activeIssues.length,
            onSelect: (t) => setState(() => _tab = t),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  _Tab.overview => _buildOverview(log, phase, hasLive),
                  _Tab.issues => _buildIssues(log, phase, hasLive),
                  _Tab.history => _buildHistory(log),
                  _Tab.logs => _buildLogs(log),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tổng quan ────────────────────────────────────────────────────────────
  Widget _buildOverview(DiagLog log, BlePhase phase, bool hasLive) {
    final active = log.activeIssues;
    final health = VehicleHealth.evaluate(active, hasLiveData: hasLive);
    final color = switch (health.level) {
      VehicleHealthLevel.good => AppColors.tertiary,
      VehicleHealthLevel.watch => AppColors.amber,
      VehicleHealthLevel.critical => AppColors.red,
      VehicleHealthLevel.unknown => AppColors.textSecondary,
    };
    final icon = switch (health.level) {
      VehicleHealthLevel.good => Icons.verified_rounded,
      VehicleHealthLevel.watch => Icons.warning_amber_rounded,
      VehicleHealthLevel.critical => Icons.error_rounded,
      VehicleHealthLevel.unknown => Icons.sensors_off_rounded,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.huge),
      children: [
        GlassCard(
          hero: true,
          accent: health.level == VehicleHealthLevel.unknown ? null : color,
          padding: const EdgeInsets.all(AppSpacing.xl),
          semanticLabel: 'Tình trạng xe: ${health.level.label}',
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.readable(color), size: 30),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TÌNH TRẠNG XE', style: AppTypography.labelSm(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(health.level.label,
                        style: AppTypography.headlineMd(color: AppColors.readable(color))),
                    const SizedBox(height: 2),
                    Text(
                      hasLive || health.level != VehicleHealthLevel.unknown
                          ? health.level.hint
                          : phase == BlePhase.connected
                              ? 'Đang chờ dữ liệu từ xe.'
                              : health.level.hint,
                      style: AppTypography.bodySm(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _CountTile(
                label: 'Nghiêm trọng',
                value: hasLive || active.isNotEmpty ? '${health.critical}' : null,
                severity: Severity.critical,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CountTile(
                label: 'Cảnh báo',
                value: hasLive || active.isNotEmpty ? '${health.warning}' : null,
                severity: Severity.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CountTile(
                label: 'Thông tin',
                value: hasLive || active.isNotEmpty ? '${health.info}' : null,
                severity: Severity.info,
              ),
            ),
          ],
        ),
        if (active.isNotEmpty) ...[
          const _Header('Cần chú ý nhất', null),
          for (final e in active.take(3)) _IssueTile(event: e, onTap: () => _showDetail(e)),
          if (active.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TextButton(
                onPressed: () => setState(() => _tab = _Tab.issues),
                child: Text('Xem tất cả ${active.length} mục'),
              ),
            ),
        ],
        const _Header('Công cụ liên quan', 'Mở nhanh các màn chi tiết'),
        _LinkTile(
          icon: Icons.medical_services_rounded,
          title: 'Bác sĩ pin và BMS',
          subtitle: 'Điện áp từng cell, cân bằng, cảnh báo bảo vệ',
          onTap: () => Navigator.of(context).pushNamed('/battery'),
        ),
        _LinkTile(
          icon: Icons.speed_rounded,
          title: 'Thông số vận hành',
          subtitle: 'Biểu đồ tốc độ, điện áp, dòng điện, nhiệt độ',
          onTap: () => Navigator.of(context).pushNamed('/operations'),
        ),
        _LinkTile(
          icon: Icons.bluetooth_searching_rounded,
          title: 'Tệp nhật ký Bluetooth',
          subtitle: 'Xem, chia sẻ hoặc xuất tệp nhật ký kỹ thuật',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
        ),
      ],
    );
  }

  // ── Lỗi hiện tại ─────────────────────────────────────────────────────────
  Widget _buildIssues(DiagLog log, BlePhase phase, bool hasLive) {
    final active = log.activeIssues;
    if (active.isEmpty) {
      if (!hasLive) {
        return const StateView(
          kind: StateKind.offline,
          title: 'Chưa có dữ liệu từ xe',
          message: 'Kết nối xe để ứng dụng kiểm tra lỗi. Chưa kết nối nghĩa là chưa biết xe có lỗi hay không.',
        );
      }
      return const StateView(
        kind: StateKind.empty,
        icon: Icons.verified_rounded,
        title: 'Không có lỗi đang hoạt động',
        message: 'Xe và BMS không báo lỗi hay cảnh báo nào.',
      );
    }

    final groups = <DiagSeverity, List<DiagEvent>>{};
    for (final e in active) {
      groups.putIfAbsent(e.severity, () => []).add(e);
    }
    final order = [DiagSeverity.critical, DiagSeverity.warning, DiagSeverity.info];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.huge),
      children: [
        if (!hasLive)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: NoticeLine(
              icon: Icons.history_toggle_off_rounded,
              text: 'Đang mất kết nối — các mục dưới đây là lần ghi nhận gần nhất.',
            ),
          ),
        for (final sev in order)
          if (groups[sev] != null) ...[
            _Header('${sev.label} (${groups[sev]!.length})', null,
                color: _sev(sev).color),
            for (final e in groups[sev]!) _IssueTile(event: e, onTap: () => _showDetail(e)),
          ],
      ],
    );
  }

  // ── Lịch sử lỗi ──────────────────────────────────────────────────────────
  Widget _buildHistory(DiagLog log) {
    final all = log.issueHistory;
    final items = _historyFilter == null
        ? all
        : all.where((e) => e.severity == _historyFilter).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.huge),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(
                label: 'Tất cả',
                selected: _historyFilter == null,
                onTap: () => setState(() => _historyFilter = null),
              ),
              for (final s in [DiagSeverity.critical, DiagSeverity.warning, DiagSeverity.info])
                _Chip(
                  label: s.label,
                  selected: _historyFilter == s,
                  onTap: () => setState(() => _historyFilter = s),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const StateView(
            kind: StateKind.empty,
            compact: true,
            title: 'Chưa có lỗi nào được ghi lại',
            message: 'Lỗi và cảnh báo xuất hiện khi dùng xe sẽ được lưu ở đây.',
          )
        else
          for (final e in items) _IssueTile(event: e, onTap: () => _showDetail(e), showSpan: true),
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Xóa lịch sử chẩn đoán'),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa lịch sử chẩn đoán?',
      message: 'Toàn bộ lỗi đã ghi và nhật ký hoạt động trong ứng dụng sẽ bị xóa. '
          'Tệp nhật ký Bluetooth không bị ảnh hưởng.',
      confirmLabel: 'Xóa',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await ref.read(diagProvider.notifier).clearAll();
    if (mounted) showAppSnack(context, 'Đã xóa lịch sử chẩn đoán', kind: SnackKind.success);
  }

  // ── Nhật ký ──────────────────────────────────────────────────────────────
  Widget _buildLogs(DiagLog log) {
    final items = log.bySource(_logSource);
    final hub = _logSource == DiagSource.bms ? ref.watch(batteryHubProvider) : null;
    final balancing = hub?.balancingEvents.reversed.take(20).toList() ?? const <BalancingEvent>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.huge),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in [DiagSource.activity, DiagSource.ble, DiagSource.bms, DiagSource.vehicle])
                _Chip(
                  label: switch (s) {
                    DiagSource.activity => 'Hoạt động',
                    DiagSource.ble => 'Bluetooth (BLE)',
                    DiagSource.bms => 'BMS',
                    DiagSource.vehicle => 'Xe',
                  },
                  selected: _logSource == s,
                  onTap: () => setState(() => _logSource = s),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          switch (_logSource) {
            DiagSource.activity => 'Khóa/mở khóa, đổi chế độ, bắt đầu/kết thúc sạc.',
            DiagSource.ble => 'BLE là kết nối Bluetooth năng lượng thấp giữa điện thoại và xe.',
            DiagSource.bms => 'BMS là hệ thống quản lý pin. Chỉ ghi cảnh báo khi có dữ liệu BMS trực tiếp.',
            DiagSource.vehicle => 'Lỗi và cảnh báo do xe báo về.',
          },
          style: AppTypography.bodySm(),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_logSource == DiagSource.ble)
          _LinkTile(
            icon: Icons.folder_open_rounded,
            title: 'Tệp nhật ký kỹ thuật Bluetooth',
            subtitle: 'Xem, chia sẻ hoặc xuất tệp (không chứa khóa xác thực)',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
          ),
        if (items.isEmpty && balancing.isEmpty)
          const StateView(
            kind: StateKind.empty,
            compact: true,
            title: 'Chưa có sự kiện',
            message: 'Sự kiện sẽ xuất hiện khi ứng dụng làm việc với xe.',
          ),
        for (final e in items) _LogRow(event: e, onTap: e.isIssue ? () => _showDetail(e) : null),
        if (balancing.isNotEmpty) ...[
          const _Header('Lần cân bằng cell', 'Do BMS báo, 20 lần gần nhất'),
          for (final b in balancing) _BalancingRow(event: b),
        ],
      ],
    );
  }

  // ── Chi tiết lỗi ─────────────────────────────────────────────────────────
  void _showDetail(DiagEvent e) {
    final sev = _sev(e.severity);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.huge),
          children: [
            Row(
              children: [
                Icon(sev.icon, color: sev.color, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(sev.label,
                    style: AppTypography.labelLg(color: AppColors.readable(sev.color))),
                const SizedBox(width: AppSpacing.sm),
                Text('· ${e.source.label}', style: AppTypography.labelMd()),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(e.title, style: AppTypography.headlineSm(color: AppColors.textPrimary)),
            if (e.detail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(e.detail, style: AppTypography.bodyMd()),
            ],
            const SizedBox(height: AppSpacing.lg),
            _Fact('Bắt đầu', fmtDiagTime(e.at)),
            _Fact(
              'Trạng thái',
              e.isActive
                  ? 'Đang xảy ra (${fmtDiagDuration(DateTime.now().difference(e.at))})'
                  : e.clearedAt != null
                      ? 'Đã hết lúc ${fmtDiagTime(e.clearedAt!)} (kéo dài ${fmtDiagDuration(e.clearedAt!.difference(e.at))})'
                      : 'Không áp dụng',
            ),
            if (e.cause != null && e.cause!.isNotEmpty) ...[
              const _Header('Nguyên nhân có thể', null),
              Text(e.cause!, style: AppTypography.bodyMd(color: AppColors.textPrimary)),
            ],
            if (e.advice != null && e.advice!.isNotEmpty) ...[
              const _Header('Hướng xử lý', null),
              Text(e.advice!, style: AppTypography.bodyMd(color: AppColors.textPrimary)),
            ],
            if ((e.cause == null || e.cause!.isEmpty) && (e.advice == null || e.advice!.isEmpty))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Text('Ứng dụng không có mô tả nguyên nhân cho mục này.',
                    style: AppTypography.bodyMd()),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Nội dung mang tính tham khảo, không thay thế việc kiểm tra tại trạm dịch vụ. '
              'Khi có lỗi nghiêm trọng, hãy dừng xe ở nơi an toàn.',
              style: AppTypography.bodySm(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget con
// ═════════════════════════════════════════════════════════════════════════════

class _TabBar extends StatelessWidget {
  final _Tab selected;
  final int issueCount;
  final ValueChanged<_Tab> onSelect;
  const _TabBar({required this.selected, required this.issueCount, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        children: [
          for (final t in _Tab.values)
            _Chip(
              label: t == _Tab.issues && issueCount > 0 ? '${t.label} ($issueCount)' : t.label,
              selected: t == selected,
              onTap: () => onSelect(t),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            constraints: const BoxConstraints(minHeight: AppSizes.minTap - 4),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.panelBorderBright,
              ),
            ),
            child: Text(
              label,
              style: AppTypography.labelMd(
                color: selected ? AppColors.primary : AppColors.textDim,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? hint;
  final Color? color;
  const _Header(this.title, this.hint, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.labelLg(
                  color: color == null ? null : AppColors.readable(color!))),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!, style: AppTypography.bodySm()),
            ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final String? value; // null → "--" (chưa có dữ liệu)
  final Severity severity;
  const _CountTile({required this.label, required this.value, required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = severity.color;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(severity.icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(value ?? '--',
              style: AppTypography.headlineMd(color: AppColors.textPrimary)),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.labelSm()),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  final DiagEvent event;
  final VoidCallback onTap;
  final bool showSpan;
  const _IssueTile({required this.event, required this.onTap, this.showSpan = false});

  @override
  Widget build(BuildContext context) {
    final sev = _sev(event.severity);
    final active = event.isActive;
    final sub = StringBuffer(event.source.label)..write(' · ')..write(fmtDiagTime(event.at));
    if (showSpan) {
      sub.write(active
          ? ' · đang xảy ra'
          : event.clearedAt != null
              ? ' · đã hết sau ${fmtDiagDuration(event.clearedAt!.difference(event.at))}'
              : '');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        accent: active && event.severity == DiagSeverity.critical ? sev.color : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        semanticLabel: '${sev.label}: ${event.title}',
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: sev.color.withValues(alpha: active ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(sev.icon,
                  size: 22, color: active ? sev.color : AppColors.textMuted),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLg(color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(sub.toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodySm()),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final DiagEvent event;
  final VoidCallback? onTap;
  const _LogRow({required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sev = _sev(event.severity);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: sev.color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                  if (event.detail.isNotEmpty)
                    Text(event.detail, style: AppTypography.bodySm()),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(fmtDiagTime(event.at), style: AppTypography.labelSm()),
          ],
        ),
      ),
    );
  }
}

class _BalancingRow extends StatelessWidget {
  final BalancingEvent event;
  const _BalancingRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final end = event.end;
    final span = end == null
        ? 'đang diễn ra'
        : 'kéo dài ${fmtDiagDuration(end.difference(event.start))}';
    final delta = (event.deltaBeforeMv != null && event.deltaAfterMv != null)
        ? ' · chênh áp ${event.deltaBeforeMv!.toStringAsFixed(0)} → ${event.deltaAfterMv!.toStringAsFixed(0)} mV'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.balance_rounded, size: 18, color: AppColors.cyan),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text('Cân bằng cell $span$delta',
                style: AppTypography.bodyMd(color: AppColors.textPrimary)),
          ),
          Text(fmtDiagTime(event.start), style: AppTypography.labelSm()),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _LinkTile(
      {required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelLg(color: AppColors.textPrimary)),
                  Text(subtitle, style: AppTypography.bodySm()),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label, style: AppTypography.labelMd())),
          Expanded(child: Text(value, style: AppTypography.bodyMd(color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

/// Dòng ghi chú ngắn có biểu tượng.
class NoticeLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const NoticeLine({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.amberText),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.bodySm(color: AppColors.amberText))),
      ],
    );
  }
}
