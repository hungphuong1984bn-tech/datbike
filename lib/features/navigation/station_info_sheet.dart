// Thẻ thông tin trạm (bottom sheet) hiện khi chạm Marker.
//
// Trung thực: thông số nào nguồn không có thì ghi "Chưa có dữ liệu", không điền
// số liệu giả. "Nguồn dữ liệu" và "Cập nhật gần nhất" lấy thẳng từ bản ghi trạm.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/charging/external_nav.dart';
import '../../core/charging/station_marker_status.dart';
import '../../core/services/charging_station_service.dart';
import '../../ui/app_theme.dart';
import 'station_widgets.dart';

class StationInfoSheet extends StatelessWidget {
  final ChargingStation station;
  final MarkerStatus status;

  /// Khoảng cách chim bay từ vị trí hiện tại (km); null khi chưa có GPS.
  final double? distanceKm;

  /// Ảnh trạm trên máy (nếu có).
  final String? photoPath;
  final bool favorite;
  final VoidCallback onDetail;
  final void Function(NavMode mode) onNavigate;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;

  const StationInfoSheet({
    super.key,
    required this.station,
    required this.status,
    required this.distanceKm,
    required this.photoPath,
    required this.favorite,
    required this.onDetail,
    required this.onNavigate,
    required this.onClose,
    required this.onToggleFavorite,
  });

  static const _noData = 'Chưa có dữ liệu';

  @override
  Widget build(BuildContext context) {
    final s = station;
    final mc = StationUi.markerColor(status);
    final label = GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondary);
    final value = GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary);

    Widget row(IconData i, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              SizedBox(width: 92, child: Text(k, style: label)),
              Expanded(child: Text(v, style: value)),
            ],
          ),
        );

    final ports = s.ports == null ? _noData : '${s.ports} cổng';
    final power = s.powerKw == null
        ? _noData
        : '${s.powerKw!.toStringAsFixed(s.powerKw! % 1 == 0 ? 0 : 1)} kW';
    final photo = photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: mc.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
            child: Row(
              children: [
                CircleAvatar(radius: 15, backgroundColor: mc, child: Icon(StationUi.markerIcon(status), size: 17, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: favorite ? 'Bỏ yêu thích' : 'Lưu yêu thích',
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: favorite ? AppColors.amber : AppColors.textSecondary),
                  onPressed: onToggleFavorite,
                ),
                IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close_rounded), onPressed: onClose),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StationChip(icon: Icons.circle, label: status.label, color: mc),
                    StationChip(
                      icon: Icons.verified_outlined,
                      label: StationUi.categoryLabel(s.category),
                      color: StationUi.categoryColor(s.category),
                    ),
                    StationChip(icon: StationUi.vehicleIcon(s.vehicle), label: StationUi.vehicleLabel(s.vehicle), color: StationUi.vehicleColor(s.vehicle)),
                  ]),
                  if (hasPhoto)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.file(File(photo), height: 120, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                  const SizedBox(height: 6),
                  row(Icons.place_outlined, 'Địa chỉ', (s.address == null || s.address!.trim().isEmpty) ? _noData : s.address!),
                  row(Icons.my_location_rounded, 'Tọa độ GPS', '${s.lat.toStringAsFixed(6)}, ${s.lng.toStringAsFixed(6)}'),
                  row(Icons.straighten_rounded, 'Khoảng cách',
                      distanceKm == null ? 'Chưa có vị trí hiện tại' : '${StationUi.km(distanceKm!)} (đường chim bay)'),
                  row(Icons.ev_station_rounded, 'Số cổng sạc', ports),
                  row(Icons.bolt_rounded, 'Công suất', power),
                  row(Icons.update_rounded, 'Cập nhật gần nhất', s.updatedAt == null ? _noData : StationUi.dateTime(s.updatedAt!)),
                  row(Icons.source_outlined, 'Nguồn dữ liệu', s.source),
                  if (status != MarkerStatus.active)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        switch (status) {
                          MarkerStatus.warning => 'Có báo cáo gần đây về trạm này (chưa xác minh). Nên kiểm tra trước khi đi.',
                          MarkerStatus.paused => 'Trạm được ghi nhận là tạm ngừng/đã đóng.',
                          MarkerStatus.updating => 'Thông tin trạm đang được cập nhật.',
                          _ => 'Chưa có xác nhận nào cho thấy trạm đang hoạt động.',
                        },
                        style: TextStyle(fontSize: 11.5, color: AppColors.amberText, height: 1.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDetail,
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: const Text('CHI TIẾT TRẠM'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onNavigate(NavMode.choose),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('DẪN ĐƯỜNG'),
                  ),
                ),
                PopupMenuButton<NavMode>(
                  tooltip: 'Chọn phương tiện',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: onNavigate,
                  itemBuilder: (_) => [
                    for (final m in NavMode.values)
                      PopupMenuItem(value: m, child: Text(m == NavMode.choose ? m.label : 'Dẫn đường: ${m.label}')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
