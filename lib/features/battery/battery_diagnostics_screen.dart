// Battery Management System (BMS) — màn hình quản lý pin cao cấp.
//
// Tab: Sức khỏe · Cell · Bảo vệ · Cân bằng · Chẩn đoán (OBD/nhiệt).
// Chỉ ĐỌC dữ liệu từ BleController (không ghi lệnh xuống BMS/xe). Mọi số liệu cell
// lấy từ gói BatteryLogMsg thật; không có dữ liệu giả lập.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/battery/battery_hub.dart';
import '../../core/battery/cell_model.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/services/battery_diagnostics_service.dart';
import 'bms_theme.dart';
import 'views/balancing_view.dart';
import 'views/health_view.dart';
import 'views/obd_view.dart';
import 'views/protection_view.dart';
import 'widgets/cell_pack_view.dart';

class BatteryDiagnosticsScreen extends ConsumerStatefulWidget {
  const BatteryDiagnosticsScreen({super.key});

  @override
  ConsumerState<BatteryDiagnosticsScreen> createState() =>
      _BatteryDiagnosticsScreenState();
}

class _BatteryDiagnosticsScreenState
    extends ConsumerState<BatteryDiagnosticsScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Đồng bộ hub với gói BMS đã có và yêu cầu đọc mới (hàm đọc sẵn có).
      final hub = ref.read(batteryHubProvider.notifier);
      hub.sync();
      if (ref.read(bleProvider).phase == BlePhase.connected) {
        hub.requestRefresh();
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await ref.read(batteryHubProvider.notifier).requestRefresh();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Giữ hub luôn đồng bộ khi có gói BMS mới.
    ref.listen<DateTime?>(
      bleProvider.select((s) => s.lastBatteryAt),
      (_, _) => ref.read(batteryHubProvider.notifier).sync(),
    );

    final connected =
        ref.watch(bleProvider.select((s) => s.phase == BlePhase.connected));
    final canPop = Navigator.of(context).canPop();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Bms.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Bms.text,
          centerTitle: true,
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text('Pin và BMS', style: Bms.title(18)),
          actions: [
            IconButton(
              tooltip: 'Quét lại dữ liệu xe',
              onPressed: connected && !_isRefreshing ? _refresh : null,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Bms.accent),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Bms.accent,
            labelColor: Bms.accent,
            unselectedLabelColor: Bms.textDim,
            dividerColor: Bms.border,
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
            unselectedLabelStyle:
                GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Sức khỏe'),
              Tab(text: 'Cell'),
              Tab(text: 'Bảo vệ'),
              Tab(text: 'Cân bằng'),
              Tab(text: 'Chẩn đoán'),
            ],
          ),
        ),
        body: BmsBackground(
          child: SafeArea(
            top: false,
            child: TabBarView(
              children: [
                _tab(const _HealthTab()),
                _tab(const _CellsTab()),
                _tab(const ProtectionView()),
                _tab(const BalancingView()),
                _tab(const _ObdTab()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(Widget child) => RefreshIndicator(
        color: Bms.accent,
        backgroundColor: Bms.bgMid,
        onRefresh: () => ref.read(batteryHubProvider.notifier).requestRefresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [child],
        ),
      );
}

class _HealthTab extends ConsumerWidget {
  const _HealthTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(bleProvider.select((s) => s.lastTelemetry?.percent ?? 0));
    final teleLive = ref.read(bleProvider.notifier).telemetryFresh;
    final report = _report(ref);
    return HealthView(report: report, telemetryPercent: percent, telemetryLive: teleLive);
  }
}

class _CellsTab extends ConsumerWidget {
  const _CellsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshness = ref.watch(batteryHubProvider.select((s) => s.freshness));
    final at = ref.watch(batteryHubProvider.select((s) => s.latest?.receivedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataStateBanner(freshness: freshness, receivedAt: at),
        Row(
          children: [
            FreshnessPill(freshness),
            const SizedBox(width: 8),
            AgeText(at: at, prefix: 'Cập nhật: '),
          ],
        ),
        const SizedBox(height: 12),
        const CellPackView(),
      ],
    );
  }
}

class _ObdTab extends ConsumerWidget {
  const _ObdTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ObdThermalView(report: _report(ref));
  }
}

/// Báo cáo chẩn đoán cũ (OBD/nhiệt/SOH ước tính). Chỉ truyền gói BMS vào khi nó còn
/// trực tiếp — không dùng bản ghi cũ như dữ liệu hiện tại.
BatteryHealthReport _report(WidgetRef ref) {
  final ble = ref.watch(bleProvider.select((s) => (s.lastTelemetry, s.lastBattery, s.bikeName, s.frameSerial)));
  final fresh = ref.watch(batteryHubProvider.select((s) => s.freshness == BmsFreshness.live));
  final telemetry = ble.$1;
  final battery = fresh ? ble.$2 : null;
  final bikeName = ble.$3;
  final serial = ble.$4;
  final model = (bikeName != null && bikeName.isNotEmpty)
      ? bikeName
      : ((serial?.toUpperCase().contains('DBQ') == true)
          ? 'Quantum S'
          : (telemetry?.model.isNotEmpty == true ? telemetry!.model : 'Quantum S'));
  return BatteryDiagnosticsService.analyze(
    telemetry: telemetry,
    battery: battery,
    modelName: model,
  );
}
