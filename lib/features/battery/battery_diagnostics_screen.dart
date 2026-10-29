// Battery & OBD Diagnostics Screen — "Bác Sĩ Pin & Chẩn Đoán Lỗi OBD"
// Chuẩn thiết kế Kinetic Stitch EV:
// 1. Phân tích trực quan 20/24 Cell pin với biểu đồ Bar Chart & đo lệch áp Delta V (mV).
// 2. Bản đồ giám sát nhiệt độ 3 điểm (Motor, ECU, BMS) với ngưỡng cảnh báo.
// 3. Hệ thống quét chẩn đoán 8 hệ thống phần cứng OBD & hướng dẫn khắc phục.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/services/battery_diagnostics_service.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';

class BatteryDiagnosticsScreen extends ConsumerStatefulWidget {
  const BatteryDiagnosticsScreen({super.key});

  @override
  ConsumerState<BatteryDiagnosticsScreen> createState() =>
      _BatteryDiagnosticsScreenState();
}

class _BatteryDiagnosticsScreenState
    extends ConsumerState<BatteryDiagnosticsScreen> {
  int? _selectedCellIndex;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(bleProvider).phase == BlePhase.connected) {
        ref.read(bleProvider.notifier).fetchBatteryDetails();
      }
    });
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await ref.read(bleProvider.notifier).fetchBatteryDetails();
    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚡ Đã cập nhật dữ liệu Bác Sĩ Pin & OBD từ xe thành công!',
          ),
          backgroundColor: AppColors.tertiary,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final connected = ble.phase == BlePhase.connected;
    final telemetry = ble.lastTelemetry;
    final battery = ble.lastBattery;

    final resolvedModel = (ble.bikeName != null && ble.bikeName!.isNotEmpty)
        ? ble.bikeName!
        : ((ble.frameSerial?.toUpperCase().contains('DBQ') == true)
              ? 'Quantum S'
              : (telemetry?.model.isNotEmpty == true
                    ? telemetry!.model
                    : 'Quantum S'));

    final report = BatteryDiagnosticsService.analyze(
      telemetry: telemetry,
      battery: battery,
      modelName: resolvedModel,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: !Navigator.of(context).canPop()
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
        centerTitle: true,
        title: Text(
          'Battery & BMS',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            tooltip: 'Quét lại dữ liệu xe',
            onPressed: connected && !_isRefreshing ? _refreshData : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!connected) ...[
            const NoticeBanner(
              color: AppColors.amber,
              text: 'Xe chưa kết nối Bluetooth. Vui lòng kết nối xe để quét thông số BMS và OBD.',
            ),
            const SizedBox(height: 14),
          ] else if (report.isSimulated) ...[
            const NoticeBanner(
              color: AppColors.secondary,
              text: 'Đã kết nối Bluetooth. Đang chờ gói tin chi tiết cell từ BMS xe (chế độ Telemetry cơ bản).',
            ),
            const SizedBox(height: 14),
          ],

          // Chú giải nguồn dữ liệu: phân biệt số đo thật / ước tính / chưa có
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: const [
              FreshnessBadge(freshness: DataFreshness.live, labelOverride: 'Đo từ xe'),
              FreshnessBadge(freshness: DataFreshness.estimated),
              FreshnessBadge(freshness: DataFreshness.none, labelOverride: 'Chưa có (--)'),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Tổng quan Sức Khỏe Pin & Điểm An Toàn
          _buildHealthOverviewCard(report, telemetry?.percent ?? 0),
          const SizedBox(height: 16),

          // 2. Thẻ Hero: Độ Lệch Áp Delta V & Cân Bằng Cell
          const SectionTitle('ĐỘ CÂN BẰNG PACK PIN (CELL BALANCE)'),
          const SizedBox(height: 10),
          _buildCellBalanceCard(report),
          const SizedBox(height: 16),

          // 3. Biểu đồ 20/24 Cell Voltages Bar Chart
          const SectionTitle('BIỂU ĐỒ ĐIỆN ÁP CHI TIẾT TỪNG CELL'),
          const SizedBox(height: 10),
          _buildCellVoltagesChart(report),
          const SizedBox(height: 16),

          // 4. Bản Đồ Giám Sát Nhiệt Độ 3 Điểm (Thermal Radar)
          const SectionTitle('BẢN ĐỒ NHIỆT ĐỘ 3 ĐIỂM (THERMAL RADAR)'),
          const SizedBox(height: 10),
          _buildThermalRadarCard(report),
          const SizedBox(height: 16),

          // 5. Chẩn Đoán Lỗi Phần Cứng Hệ Thống OBD
          const SectionTitle('CHẨN ĐOÁN HỆ THỐNG PHẦN CỨNG OBD'),
          const SizedBox(height: 10),
          _buildObdDiagnosticsCard(report),
        ],
      ),
    );
  }

  // ========== WIDGET 1: TỔNG QUAN SỨC KHỎE PACK PIN ==========
  Widget _buildHealthOverviewCard(BatteryHealthReport report, int socPercent) {
    return Panel(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        children: [
          Row(
            children: [
              // Vòng tròn điểm số an toàn
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: CircularProgressIndicator(
                      value: report.hasLiveTelemetry
                          ? (report.safetyScore / 100.0)
                          : 0.0,
                      strokeWidth: 6,
                      backgroundColor: AppColors.panelBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        !report.hasLiveTelemetry
                            ? AppColors.textDim
                            : (report.safetyScore >= 90
                                  ? AppColors.tertiary
                                  : (report.safetyScore >= 70
                                        ? AppColors.amber
                                        : AppColors.error)),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        report.hasLiveTelemetry
                            ? '${report.safetyScore}'
                            : '--',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: report.hasLiveTelemetry
                              ? AppColors.textPrimary
                              : AppColors.textDim,
                        ),
                      ),
                      Text(
                        'ĐIỂM',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Sức khỏe Pin (SOH)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          report.hasLiveTelemetry
                              ? '${report.healthPercentage}%'
                              : '--',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: report.hasLiveTelemetry
                                ? AppColors.primary
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                    if (report.hasLiveTelemetry) ...[
                      const SizedBox(height: 6),
                      const FreshnessBadge(
                        freshness: DataFreshness.estimated,
                        labelOverride: 'Ước tính từ chu kỳ sạc & cân bằng cell',
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      !report.hasLiveTelemetry
                          ? 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry.'
                          : (report.safetyScore >= 90
                                ? 'Tất cả tế bào pin & hệ thống điện hoạt động xuất sắc.'
                                : 'Phát hiện cảnh báo hệ thống, vui lòng xem danh mục OBD bên dưới.'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.panelBorder, height: 1),
          const SizedBox(height: 14),

          // 4 thông số mini
          Row(
            children: [
              _buildMiniMetric(
                label: 'ĐIỆN ÁP TỔNG',
                value: report.hasLiveTelemetry && report.packVoltage > 0
                    ? '${report.packVoltage.toStringAsFixed(1)} V'
                    : '-- V',
              ),
              _buildMiniMetric(
                label: 'DÒNG TẢI',
                value: report.hasLiveTelemetry
                    ? '${report.currentAmp >= 0 ? "+" : ""}${report.currentAmp.toStringAsFixed(1)} A'
                    : '-- A',
                valueColor: report.hasLiveTelemetry
                    ? (report.currentAmp < -0.5
                          ? AppColors.tertiary
                          : (report.currentAmp > 0.5
                                ? AppColors.secondary
                                : AppColors.textDim))
                    : AppColors.textDim,
              ),
              _buildMiniMetric(
                label: 'CHU KỲ SẠC',
                value: report.hasLiveTelemetry
                    ? '${report.chargeCycles} cycles'
                    : '--',
              ),
              _buildMiniMetric(
                label: 'NỘI TRỞ',
                value:
                    report.hasLiveTelemetry && report.internalResistanceMo > 0
                    ? '${report.internalResistanceMo.toStringAsFixed(1)} mΩ'
                    : '-- mΩ',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05 * 10,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ========== WIDGET 2: THẺ DELTA V & CÂN BẰNG CELL ==========
  Widget _buildCellBalanceCard(BatteryHealthReport report) {
    final hasCells = report.cellCount > 0;
    final gradeColor = switch (report.balanceGrade) {
      CellBalanceGrade.unknown => AppColors.secondary,
      CellBalanceGrade.excellent => AppColors.tertiary,
      CellBalanceGrade.good => AppColors.secondary,
      CellBalanceGrade.fair => AppColors.amber,
      CellBalanceGrade.poor => const Color(0xFFF97316),
      CellBalanceGrade.critical => AppColors.error,
    };

    return Panel(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ĐỘ LỆCH ÁP CỰC ĐẠI (ΔV)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.06 * 11,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        hasCells
                            ? report.deltaVoltageMv.toStringAsFixed(1)
                            : '--',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: gradeColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'mV',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              StatusPill(
                label: report.balanceGrade.label.toUpperCase(),
                color: gradeColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.balanceGrade.description,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.panelBorder, height: 1),
          const SizedBox(height: 14),

          // 3 khối đối sánh: Cell cao nhất, Cell thấp nhất, Trung bình
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCells
                            ? 'Cell cao nhất (#${report.maxCellIndex})'
                            : 'Cell cao nhất',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCells
                            ? '${report.maxCellVoltage.toStringAsFixed(3)} V'
                            : '-- V',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (report.deltaVoltageMv > 80
                                ? AppColors.error
                                : AppColors.amber)
                            .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          (report.deltaVoltageMv > 80
                                  ? AppColors.error
                                  : AppColors.amber)
                              .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCells
                            ? 'Cell thấp nhất (#${report.minCellIndex})'
                            : 'Cell thấp nhất',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: report.deltaVoltageMv > 80
                              ? AppColors.error
                              : AppColors.amber,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCells
                            ? '${report.minCellVoltage.toStringAsFixed(3)} V'
                            : '-- V',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.panelSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.panelBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Điện áp TB cell',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCells
                            ? '${report.avgCellVoltage.toStringAsFixed(3)} V'
                            : '-- V',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== WIDGET 3: BIỂU ĐỒ CELL VOLTAGES BAR CHART ==========
  Widget _buildCellVoltagesChart(BatteryHealthReport report) {
    final cells = report.cellVoltages;
    final hasCells = cells.isNotEmpty;
    final minV = hasCells
        ? (report.minCellVoltage - 0.05).clamp(2.5, 4.2)
        : 2.5;
    final maxV = hasCells
        ? (report.maxCellVoltage + 0.05).clamp(minV + 0.05, 4.3)
        : 4.2;

    return Panel(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  report.packConfigName,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (hasCells &&
                  _selectedCellIndex != null &&
                  _selectedCellIndex! < cells.length)
                Flexible(
                  child: Text(
                    'Cell #${_selectedCellIndex! + 1}: ${cells[_selectedCellIndex!].toStringAsFixed(3)} V',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else if (hasCells)
                Text(
                  'Chạm vào cell để xem',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                )
              else
                Text(
                  'Đang chờ dữ liệu BMS...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (!hasCells)
            Container(
              height: 120,
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.panelSecondary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.panelBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.developer_board_off_rounded,
                    color: AppColors.textDim,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chưa nhận được gói tin chi tiết điện áp từng cell từ BMS qua Bluetooth.\nỨng dụng sẽ tự động vẽ biểu đồ ngay khi xe truyền telemetry BMS.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: AppColors.textDim,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else
            // Layout các cột điện áp dạng biểu đồ
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(cells.length, (idx) {
                  final v = cells[idx];
                  final normalized = ((v - minV) / (maxV - minV)).clamp(
                    0.08,
                    1.0,
                  );
                  final isLowest = (idx + 1) == report.minCellIndex;
                  final isHighest = (idx + 1) == report.maxCellIndex;
                  final isSelected = _selectedCellIndex == idx;

                  final Color barColor;
                  if (isLowest && report.deltaVoltageMv > 60) {
                    barColor = AppColors.error;
                  } else if (isHighest) {
                    barColor = AppColors.primary;
                  } else if (isSelected) {
                    barColor = AppColors.secondary;
                  } else {
                    barColor = AppColors.primary.withValues(alpha: 0.55);
                  }

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCellIndex = (_selectedCellIndex == idx)
                              ? null
                              : idx;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isSelected || isLowest || isHighest)
                              Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: barColor,
                                ),
                              ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 110 * normalized,
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // FittedBox: 23-24 cell → mỗi cột chỉ ~10px, nhãn
                            // 2 chữ số phải tự thu nhỏ để không đè lên nhau.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${idx + 1}',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 9,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          const SizedBox(height: 12),
          // Chú thích màu
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChartLegend(AppColors.primary, 'Cell cao nhất'),
              const SizedBox(width: 14),
              _buildChartLegend(
                report.deltaVoltageMv > 60 ? AppColors.error : AppColors.amber,
                'Cell thấp nhất',
              ),
              const SizedBox(width: 14),
              _buildChartLegend(
                AppColors.primary.withValues(alpha: 0.55),
                'Cell tiêu chuẩn',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.textDim,
          ),
        ),
      ],
    );
  }

  // ========== WIDGET 4: BẢN ĐỒ NHIỆT ĐỘ 3 ĐIỂM ==========
  Widget _buildThermalRadarCard(BatteryHealthReport report) {
    return Panel(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        children: [
          _buildThermalRow(
            report.motorThermal,
            Icons.electric_meter_rounded,
            report.hasLiveTelemetry,
          ),
          Divider(color: AppColors.panelBorder, height: 20),
          _buildThermalRow(
            report.ecuThermal,
            Icons.memory_rounded,
            report.hasLiveTelemetry,
          ),
          Divider(color: AppColors.panelBorder, height: 20),
          _buildThermalRow(
            report.bmsThermal,
            Icons.battery_charging_full_rounded,
            report.hasLiveTelemetry,
          ),
        ],
      ),
    );
  }

  Widget _buildThermalRow(
    ThermalZone zone,
    IconData icon,
    bool hasLiveTelemetry,
  ) {
    final isOnline = hasLiveTelemetry && zone.temperature > 0;
    final statusColor = isOnline
        ? Color(zone.status.colorValue)
        : AppColors.textDim;
    final ratio = isOnline
        ? (zone.temperature / zone.criticalTemp).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: statusColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    zone.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    isOnline
                        ? '${zone.temperature.toStringAsFixed(1)} °C'
                        : '-- °C',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: AppColors.panelBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    isOnline
                        ? 'Trạng thái: ${zone.status.label}'
                        : 'Trạng thái: Chờ dữ liệu xe',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Cảnh báo: ${zone.warningTemp.round()}°C',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========== WIDGET 5: CHẨN ĐOÁN HỆ THỐNG OBD ==========
  Widget _buildObdDiagnosticsCard(BatteryHealthReport report) {
    final activeErrors = report.obdItems.where((e) => !e.isHealthy).toList();

    return Panel(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (!report.hasLiveTelemetry
                              ? AppColors.textDim
                              : (activeErrors.isEmpty
                                    ? AppColors.tertiary
                                    : AppColors.error))
                          .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  !report.hasLiveTelemetry
                      ? Icons.sensors_off_rounded
                      : (activeErrors.isEmpty
                            ? Icons.check_circle_rounded
                            : Icons.warning_rounded),
                  color: !report.hasLiveTelemetry
                      ? AppColors.textDim
                      : (activeErrors.isEmpty
                            ? AppColors.tertiary
                            : AppColors.error),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !report.hasLiveTelemetry
                          ? 'Chưa kết nối xe — Đang chờ dữ liệu Telemetry'
                          : (activeErrors.isEmpty
                                ? 'Tất cả 8 hệ thống phần cứng hoàn hảo'
                                : 'Phát hiện ${activeErrors.length} sự cố phần cứng!'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: !report.hasLiveTelemetry
                            ? AppColors.textDim
                            : (activeErrors.isEmpty
                                  ? AppColors.tertiary
                                  : AppColors.error),
                      ),
                    ),
                    Text(
                      !report.hasLiveTelemetry
                          ? 'Kết nối Bluetooth để tự động quét 8 hệ thống OBD'
                          : 'Quét thời gian thực qua giao thức Telemetry',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Hiển thị mã lỗi thô VESC từ ECU
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.panelSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.panelBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.memory_rounded, size: 16, color: AppColors.textDim),
                const SizedBox(width: 8),
                Text(
                  'VESC mc_fault_code:',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (!report.hasLiveTelemetry
                                ? AppColors.textDim
                                : (report.rawErrorCode == 0
                                      ? AppColors.tertiary
                                      : AppColors.error))
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    report.hasLiveTelemetry
                        ? '0x${report.rawErrorCode.toRadixString(16).padLeft(2, '0').toUpperCase()} (${report.rawErrorCode})'
                        : '--',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: !report.hasLiveTelemetry
                          ? AppColors.textDim
                          : (report.rawErrorCode == 0
                                ? AppColors.tertiary
                                : AppColors.error),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  !report.hasLiveTelemetry
                      ? 'CHỜ KẾT NỐI'
                      : (report.rawErrorCode == 0
                            ? 'FAULT_NONE'
                            : 'PHÁT HIỆN SỰ CỐ'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: !report.hasLiveTelemetry
                        ? AppColors.textDim
                        : (report.rawErrorCode == 0
                              ? AppColors.tertiary
                              : AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: AppColors.panelBorder, height: 1),
          const SizedBox(height: 6),

          // Danh sách 8 mục chẩn đoán
          ...report.obdItems.map(
            (item) => _buildObdItemTile(item, report.hasLiveTelemetry),
          ),
        ],
      ),
    );
  }

  Widget _buildObdItemTile(ObdDiagnosticItem item, bool hasLiveTelemetry) {
    final statusColor = !hasLiveTelemetry
        ? AppColors.textDim
        : (item.isHealthy ? AppColors.tertiary : AppColors.error);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Icon(
          !hasLiveTelemetry
              ? Icons.radio_button_unchecked_rounded
              : (item.isHealthy
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_rounded),
          color: statusColor,
          size: 20,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: (hasLiveTelemetry && !item.isHealthy)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: (hasLiveTelemetry && !item.isHealthy)
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                !hasLiveTelemetry ? 'CHỜ KẾT NỐI' : item.code,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.panelSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chi tiết kỹ thuật:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Khuyến nghị xử lý:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: !hasLiveTelemetry
                        ? AppColors.textDim
                        : (item.isHealthy
                              ? AppColors.primary
                              : AppColors.error),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.recommendation,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
