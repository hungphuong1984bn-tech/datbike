// Tab "Chẩn đoán": bản đồ nhiệt độ 3 điểm (Motor / ECU / BMS) và 8 hệ thống OBD.
// Giữ nguyên logic và dữ liệu của BatteryDiagnosticsService; chỉ chuyển sang theme BMS.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/battery_diagnostics_service.dart';
import '../bms_theme.dart';

class ObdThermalView extends StatelessWidget {
  final BatteryHealthReport report;
  const ObdThermalView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Bản đồ nhiệt độ 3 điểm'),
        _buildThermalRadarCard(report),
        const SizedBox(height: 16),
        const SectionHeader('Chẩn đoán hệ thống phần cứng OBD'),
        _buildObdDiagnosticsCard(report),
      ],
    );
  }

  Widget _buildThermalRadarCard(BatteryHealthReport report) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        children: [
          _buildThermalRow(
            report.motorThermal,
            Icons.electric_meter_rounded,
            report.hasLiveTelemetry,
          ),
          Divider(color: Bms.border, height: 20),
          _buildThermalRow(
            report.ecuThermal,
            Icons.memory_rounded,
            report.hasLiveTelemetry,
          ),
          Divider(color: Bms.border, height: 20),
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
        : Bms.textDim;
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
                      color: Bms.text,
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
                  backgroundColor: Bms.border,
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
                      color: Bms.textDim,
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

    return GlassCard(
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
                              ? Bms.textDim
                              : (activeErrors.isEmpty
                                    ? Bms.ok
                                    : Bms.critical))
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
                      ? Bms.textDim
                      : (activeErrors.isEmpty
                            ? Bms.ok
                            : Bms.critical),
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
                            ? Bms.textDim
                            : (activeErrors.isEmpty
                                  ? Bms.ok
                                  : Bms.critical),
                      ),
                    ),
                    Text(
                      !report.hasLiveTelemetry
                          ? 'Kết nối Bluetooth để tự động quét 8 hệ thống OBD'
                          : 'Quét thời gian thực qua giao thức Telemetry',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Bms.textDim,
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
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Bms.border),
            ),
            child: Row(
              children: [
                Icon(Icons.memory_rounded, size: 16, color: Bms.textDim),
                const SizedBox(width: 8),
                Text(
                  'VESC mc_fault_code:',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Bms.textDim,
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
                                ? Bms.textDim
                                : (report.rawErrorCode == 0
                                      ? Bms.ok
                                      : Bms.critical))
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
                          ? Bms.textDim
                          : (report.rawErrorCode == 0
                                ? Bms.ok
                                : Bms.critical),
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
                        ? Bms.textDim
                        : (report.rawErrorCode == 0
                              ? Bms.ok
                              : Bms.critical),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Bms.border, height: 1),
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
        ? Bms.textDim
        : (item.isHealthy ? Bms.ok : Bms.critical);

    return ExpansionTile(
        iconColor: Bms.textDim,
        collapsedIconColor: Bms.textDim,
        shape: const Border(),
        collapsedShape: const Border(),
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
                      ? Bms.critical
                      : Bms.text,
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
              color: Colors.white.withValues(alpha: 0.05),
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
                    color: Bms.textDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: Bms.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Khuyến nghị xử lý:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: !hasLiveTelemetry
                        ? Bms.textDim
                        : (item.isHealthy
                              ? Bms.accent
                              : Bms.critical),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.recommendation,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Bms.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }
}
