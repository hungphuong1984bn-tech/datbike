// Thành phần giao diện dùng chung của Trung tâm tìm kiếm trạm sạc: nhãn trạng
// thái, nhãn loại xe, biểu tượng trên bản đồ. Chỉ dùng token của design system
// (AppColors / AppRadius / AppMotion) để đồng bộ với toàn app.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/charging/station_marker_status.dart';
import '../../core/services/charging_station_service.dart';
import '../../ui/app_theme.dart';

class StationUi {
  StationUi._();

  static String statusLabel(StationStatus s) => switch (s) {
        StationStatus.active => 'Đang hoạt động',
        StationStatus.paused => 'Tạm ngừng',
        StationStatus.closed => 'Đã đóng cửa',
        StationStatus.unverified => 'Chưa xác minh',
      };

  static Color statusColor(StationStatus s) => switch (s) {
        StationStatus.active => AppColors.tertiary,
        StationStatus.paused => AppColors.amber,
        StationStatus.closed => AppColors.red,
        StationStatus.unverified => AppColors.textSecondary,
      };

  static String categoryLabel(StationCategory c) => switch (c) {
        StationCategory.datBike => 'Dat Bike chính thức',
        StationCategory.partner => 'Điểm sạc đối tác',
        StationCategory.community => 'Điểm sạc cộng đồng',
      };

  static Color categoryColor(StationCategory c) => switch (c) {
        StationCategory.datBike => AppColors.primary,
        StationCategory.partner => AppColors.cyan,
        StationCategory.community => AppColors.textSecondary,
      };

  /// Nhãn xác nhận có sạc — chỉ cho điểm Dat Bike (cửa hàng chưa xác nhận không được coi là có sạc).
  static String? chargingLabel(ChargingStation s) => s.category != StationCategory.datBike
      ? null
      : (s.chargingConfirmed ? 'Có trạm sạc (đã xác nhận)' : 'Chưa xác nhận có sạc');

  static String vehicleLabel(VehicleSupport v) => switch (v) {
        VehicleSupport.motorbike => 'Xe máy điện',
        VehicleSupport.car => 'Ô tô điện',
        VehicleSupport.both => 'Xe máy & ô tô điện',
        VehicleSupport.unknown => 'Chưa rõ loại xe',
      };

  static IconData vehicleIcon(VehicleSupport v) => switch (v) {
        VehicleSupport.motorbike => Icons.electric_moped_rounded,
        VehicleSupport.car => Icons.electric_car_rounded,
        VehicleSupport.both => Icons.ev_station_rounded,
        VehicleSupport.unknown => Icons.help_outline_rounded,
      };

  static Color vehicleColor(VehicleSupport v) => switch (v) {
        VehicleSupport.motorbike || VehicleSupport.both => AppColors.tertiary,
        VehicleSupport.car => AppColors.cyan,
        VehicleSupport.unknown => AppColors.amber,
      };

  /// Màu Marker theo trạng thái: xanh lá = hoạt động, xanh dương = đang cập nhật,
  /// cam = chưa xác minh, xám = tạm ngừng, đỏ = có cảnh báo.
  static Color markerColor(MarkerStatus s) => switch (s) {
        MarkerStatus.active => const Color(0xFF16A34A),
        MarkerStatus.updating => const Color(0xFF2563EB),
        MarkerStatus.unverified => const Color(0xFFF59E0B),
        MarkerStatus.paused => const Color(0xFF8B95A5),
        MarkerStatus.warning => const Color(0xFFDC2626),
      };

  static IconData markerIcon(MarkerStatus s) => switch (s) {
        MarkerStatus.active => Icons.bolt_rounded,
        MarkerStatus.updating => Icons.sync_rounded,
        MarkerStatus.unverified => Icons.question_mark_rounded,
        MarkerStatus.paused => Icons.pause_rounded,
        MarkerStatus.warning => Icons.priority_high_rounded,
      };

  static String km(double v) => v < 1 ? '${(v * 1000).round()} m' : '${v.toStringAsFixed(1)} km';

  static String dateTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}

/// Viên nhãn nhỏ: biểu tượng + chữ, có nền mờ theo màu ngữ nghĩa.
class StationChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const StationChip({super.key, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.readable(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Điểm đánh dấu trạm trên bản đồ — biểu tượng riêng theo loại xe, phóng to
/// nhẹ khi được chọn, viền vàng nếu là trạm yêu thích.
class StationMarker extends StatelessWidget {
  final ChargingStation station;
  final bool selected;
  final bool favorite;
  const StationMarker({super.key, required this.station, required this.selected, required this.favorite});

  @override
  Widget build(BuildContext context) {
    final c = StationUi.vehicleColor(station.vehicle);
    final dim = station.carOnly || station.status == StationStatus.closed;
    return AnimatedScale(
      scale: selected ? 1.25 : 1.0,
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dim ? AppColors.panelSecondary : c,
          border: Border.all(
            color: favorite
                ? AppColors.amber
                : station.status == StationStatus.paused
                    ? AppColors.amber
                    : station.status == StationStatus.unverified
                        ? Colors.white54
                        : Colors.white,
            width: favorite ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.35 : 0.2),
              blurRadius: selected ? 10 : 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          StationUi.vehicleIcon(station.vehicle),
          size: 20,
          color: dim ? AppColors.textSecondary : Colors.white,
        ),
      ),
    );
  }
}

/// Marker trạm theo trạng thái. Chọn → phóng to + vòng sáng; yêu thích → sao nhỏ ở góc.
/// Màu KHÔNG là tín hiệu duy nhất: mỗi trạng thái có biểu tượng riêng.
class StationPin extends StatelessWidget {
  final MarkerStatus status;
  final bool selected;
  final bool favorite;
  final bool dimmed;
  const StationPin({
    super.key,
    required this.status,
    required this.selected,
    required this.favorite,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = StationUi.markerColor(status);
    return AnimatedScale(
      scale: selected ? 1.3 : 1.0,
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dimmed ? c.withValues(alpha: 0.55) : c,
              border: Border.all(color: Colors.white, width: selected ? 3 : 2),
              boxShadow: [
                if (selected) BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 3),
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5, offset: const Offset(0, 2)),
              ],
            ),
            child: Center(child: Icon(StationUi.markerIcon(status), size: 20, color: Colors.white)),
          ),
          if (favorite)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bong bóng cụm: hiện số trạm; viền theo mức nghiêm trọng nhất trong cụm.
class ClusterBubble extends StatelessWidget {
  final int count;
  final Color color;
  const ClusterBubble({super.key, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.panel,
        border: Border.all(color: color, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary),
      ),
    );
  }
}
