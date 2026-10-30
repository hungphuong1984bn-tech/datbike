// Cài đặt ứng dụng — giao diện, ngôn ngữ, hiển thị, đơn vị đo, thông báo, kết nối,
// thông tin xe, phiên bản và giải thích thuật ngữ. Chỉ ĐỌC trạng thái xe; các thao tác
// ghi dùng đúng hàm đã có (ngắt kết nối, cấu hình đồng hồ). Không đổi giao thức BLE.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/ble/ble_logger.dart' show appBuild;
import '../../core/brand/app_info.dart';
import '../../core/config/cluster_config.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _notifStatus; // null = chưa biết / không hỗ trợ
  bool _notifChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNotif();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Người dùng đổi quyền trong cài đặt hệ thống rồi quay lại → đọc lại.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNotif();
  }

  Future<void> _checkNotif() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _notifChecked = true);
      return;
    }
    try {
      final s = await Permission.notification.status;
      if (mounted) setState(() {
        _notifStatus = s;
        _notifChecked = true;
      });
    } catch (_) {
      if (mounted) setState(() => _notifChecked = true);
    }
  }

  Future<void> _askNotif() async {
    final s = _notifStatus;
    if (s != null && (s.isPermanentlyDenied || s.isRestricted)) {
      await openAppSettings();
    } else {
      await Permission.notification.request();
      await _checkNotif();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final cfg = ref.watch(clusterConfigProvider);
    final t = ble.lastTelemetry;
    final connected = ble.phase == BlePhase.connected;

    String orDash(String? v) => (v == null || v.trim().isEmpty) ? '--' : v.trim();

    return DsScaffold(
      title: 'Cài đặt ứng dụng',
      subtitle: 'Giao diện, đơn vị, thông báo, kết nối',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.huge),
        children: [
          // ── Giao diện & ngôn ngữ ────────────────────────────────────────
          const _Group('Giao diện'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ThemeModeSelector(),
                const SizedBox(height: AppSpacing.sm),
                Text('Chế độ "Hệ thống" tự đổi Sáng/Tối theo điện thoại.',
                    style: AppTypography.bodySm()),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoCard(rows: const [
            _Row(Icons.translate_rounded, 'Ngôn ngữ', 'Tiếng Việt'),
          ], footer: 'Ứng dụng hiện chỉ hỗ trợ tiếng Việt.'),

          // ── Hiển thị ────────────────────────────────────────────────────
          const _Group('Hiển thị'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.screen_rotation_rounded, color: AppColors.primary),
                  title: Text('Cho phép xoay ngang', style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                  subtitle: Text('Mặc định khóa dọc để tránh xoay nhầm khi lái.',
                      style: AppTypography.bodySm()),
                  value: cfg.allowRotate,
                  onChanged: (v) => ref
                      .read(clusterConfigProvider.notifier)
                      .update(cfg.copyWith(allowRotate: v)),
                ),
                Divider(height: 1, color: AppColors.panelBorder),
                SwitchListTile(
                  secondary: Icon(Icons.light_mode_rounded, color: AppColors.primary),
                  title: Text('Giữ màn hình sáng khi xem đồng hồ',
                      style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                  subtitle: Text('Áp dụng cho màn hình đồng hồ lái xe.', style: AppTypography.bodySm()),
                  value: cfg.keepAwake,
                  onChanged: (v) => ref
                      .read(clusterConfigProvider.notifier)
                      .update(cfg.copyWith(keepAwake: v)),
                ),
                Divider(height: 1, color: AppColors.panelBorder),
                _NavRow(
                  icon: Icons.dashboard_customize_rounded,
                  title: 'Tùy chỉnh đồng hồ lái xe',
                  subtitle: 'Kiểu đồng hồ, ô dữ liệu, màu sắc, cỡ chữ',
                  onTap: () => Navigator.of(context).pushNamed('/studio'),
                ),
              ],
            ),
          ),

          // ── Đơn vị đo ───────────────────────────────────────────────────
          const _Group('Đơn vị đo'),
          _InfoCard(
            rows: const [
              _Row(Icons.straighten_rounded, 'Quãng đường', 'km (ki-lô-mét)'),
              _Row(Icons.speed_rounded, 'Tốc độ', 'km/h'),
              _Row(Icons.thermostat_rounded, 'Nhiệt độ', '°C (độ C)'),
              _Row(Icons.bolt_rounded, 'Điện áp · Dòng · Công suất', 'V · A · W'),
              _Row(Icons.battery_charging_full_rounded, 'Năng lượng', 'kWh'),
            ],
            footer: 'Xe báo số liệu theo hệ mét nên ứng dụng chưa hỗ trợ đổi sang đơn vị khác.',
          ),

          // ── Thông báo ───────────────────────────────────────────────────
          const _Group('Thông báo'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.notifications_active_rounded,
                  title: 'Quyền thông báo',
                  subtitle: !Platform.isAndroid
                      ? 'Quản lý trong Cài đặt hệ thống của điện thoại'
                      : !_notifChecked
                          ? 'Đang kiểm tra…'
                          : _notifStatus == null
                              ? 'Không đọc được trạng thái quyền'
                              : (_notifStatus!.isGranted
                                  ? 'Đã cấp — thông báo kết nối nền hoạt động'
                                  : 'Chưa cấp — chạm để cấp quyền'),
                  trailingText: (_notifStatus?.isGranted ?? false) ? 'Bật' : null,
                  onTap: _askNotif,
                ),
                Divider(height: 1, color: AppColors.panelBorder),
                _NavRow(
                  icon: Icons.volume_up_rounded,
                  title: 'Nhắc quên khóa xe, tự động khóa',
                  subtitle: 'Cấu hình trong Mở khóa thông minh',
                  onTap: () => Navigator.of(context).pushNamed('/proximity'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Thông báo thường trực giúp giữ kết nối Bluetooth với xe khi ứng dụng chạy nền.',
              style: AppTypography.bodySm(),
            ),
          ),

          // ── Kết nối ─────────────────────────────────────────────────────
          const _Group('Kết nối'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_rounded, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(orDash(ble.bikeName),
                                style: AppTypography.labelLg(color: AppColors.textPrimary)),
                            Text('Xe đang ghép với ứng dụng', style: AppTypography.bodySm()),
                          ],
                        ),
                      ),
                      ConnectionBadge(phase: ble.phase),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.panelBorder),
                _NavRow(
                  icon: Icons.bluetooth_searching_rounded,
                  title: 'Ghép đôi xe mới',
                  subtitle: 'Quét và kết nối một xe khác',
                  onTap: () => Navigator.of(context).pushNamed('/scan'),
                ),
                if (connected || ble.phase == BlePhase.reconnecting) ...[
                  Divider(height: 1, color: AppColors.panelBorder),
                  _NavRow(
                    icon: Icons.link_off_rounded,
                    iconColor: AppColors.red,
                    title: 'Ngắt kết nối xe',
                    subtitle: 'Có thể kết nối lại bất cứ lúc nào',
                    onTap: _confirmDisconnect,
                  ),
                ],
              ],
            ),
          ),

          // ── Thông tin xe ────────────────────────────────────────────────
          const _Group('Thông tin xe'),
          _InfoCard(
            rows: [
              _Row(Icons.two_wheeler_rounded, 'Tên xe', orDash(ble.bikeName)),
              _Row(Icons.tag_rounded, 'Mẫu xe', orDash(ble.bikeModelCode ?? t?.model)),
              _Row(Icons.pin_rounded, 'Số khung', orDash(ble.frameSerial ?? t?.frame)),
              _Row(Icons.memory_rounded, 'Phiên bản phần mềm xe', orDash(t?.version)),
              _Row(Icons.developer_board_rounded, 'Mã bo mạch', orDash(ble.boardManifest)),
              _Row(Icons.route_rounded, 'Tổng quãng đường (ODO)',
                  t == null ? '--' : '${t.odo.toStringAsFixed(1)} km'),
            ],
            footer: connected
                ? null
                : 'Giá trị "--" nghĩa là xe chưa báo hoặc chưa kết nối.',
          ),

          // ── Phiên bản ứng dụng ──────────────────────────────────────────
          const _Group('Phiên bản ứng dụng'),
          _InfoCard(rows: const [
            _Row(Icons.info_outline_rounded, 'Ứng dụng', '$kAppName $kAppVersionName'),
            _Row(Icons.numbers_rounded, 'Build Number', '$kAppBuildNumber'),
            _Row(Icons.build_circle_outlined, 'Bản dựng', appBuild),
            _Row(Icons.person_rounded, 'Nhà phát triển', kDeveloperName),
          ]),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              icon: Icons.info_rounded,
              title: 'Giới thiệu $kAppName',
              subtitle: 'Thông tin tác giả, phiên bản và danh mục chức năng',
              onTap: () => Navigator.of(context).pushNamed('/about'),
            ),
          ),

          // ── Thuật ngữ ───────────────────────────────────────────────────
          const _Group('Giải thích thuật ngữ'),
          const _InfoCard(rows: [
            _Row(Icons.battery_std_rounded, 'SOC', 'Mức pin còn lại (%)'),
            _Row(Icons.health_and_safety_rounded, 'SOH', 'Độ chai/độ khỏe của pin (%) — ứng dụng chỉ ước tính'),
            _Row(Icons.bluetooth_rounded, 'BLE', 'Bluetooth năng lượng thấp, kênh kết nối điện thoại với xe'),
            _Row(Icons.memory_rounded, 'BMS', 'Hệ thống quản lý pin (đo điện áp từng cell, nhiệt độ, bảo vệ)'),
            _Row(Icons.grid_view_rounded, 'Cell', 'Một ô pin đơn lẻ trong bộ pin; điện áp từng cell cho biết pin có cân bằng không'),
            _Row(Icons.auto_graph_rounded, 'Delta', 'Chênh lệch điện áp giữa cell cao nhất và thấp nhất (mV)'),
            _Row(Icons.refresh_rounded, 'Regen', 'Phanh tái sinh — thu hồi một phần năng lượng khi giảm tốc'),
            _Row(Icons.system_update_rounded, 'OTA', 'Cập nhật phần mềm xe không dây'),
          ]),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final name = ref.read(bleProvider).bikeName ?? 'xe';
    final ok = await showConfirmDialog(
      context,
      title: 'Ngắt kết nối xe?',
      message: 'Ngắt Bluetooth khỏi xe $name? Bạn có thể kết nối lại bất cứ lúc nào.',
      confirmLabel: 'Ngắt kết nối',
      destructive: true,
      icon: Icons.link_off_rounded,
    );
    if (!ok) return;
    await ref.read(bleProvider.notifier).disconnect();
    if (mounted) showAppSnack(context, 'Đã ngắt kết nối Bluetooth', kind: SnackKind.success);
  }
}

// ═════════════════════════════════════════════════════════════════════════════

class _Group extends StatelessWidget {
  final String title;
  const _Group(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, AppSpacing.xl, 0, AppSpacing.sm),
        child: Text(title.toUpperCase(),
            style: AppTypography.labelSm(color: AppColors.textSecondary)
                .copyWith(letterSpacing: 0.8)),
      );
}

class _Row {
  final IconData icon;
  final String label;
  final String value;
  const _Row(this.icon, this.label, this.value);
}

class _InfoCard extends StatelessWidget {
  final List<_Row> rows;
  final String? footer;
  const _InfoCard({required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.panelBorder),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(rows[i].icon, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 5,
                        child: Text(rows[i].label,
                            style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 6,
                        child: Text(rows[i].value,
                            textAlign: TextAlign.end, style: AppTypography.bodyMd()),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(footer!, style: AppTypography.bodySm()),
          ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback onTap;
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTap + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyMd(color: AppColors.textPrimary)),
                    Text(subtitle, style: AppTypography.bodySm()),
                  ],
                ),
              ),
              if (trailingText != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(trailingText!,
                      style: AppTypography.labelMd(color: AppColors.greenText)),
                ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
