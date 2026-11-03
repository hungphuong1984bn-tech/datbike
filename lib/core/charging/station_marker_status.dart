// Trạng thái hiển thị của Marker trạm sạc — hàm thuần.
//
// Quy tắc trung thực: "đang hoạt động" (xanh lá) CHỈ khi dữ liệu trạm đã được
// một nguồn xác nhận (StationStatus.active). Trạm chưa có dữ liệu xác thực luôn
// là "chưa xác minh" (cam), không bao giờ tự suy ra là đang hoạt động.

import '../services/charging_station_service.dart';

enum MarkerStatus {
  active('Đang hoạt động'),
  updating('Đang cập nhật'),
  unverified('Chưa xác minh'),
  paused('Tạm ngừng'),
  warning('Có cảnh báo');

  final String label;
  const MarkerStatus(this.label);
}

/// Thứ tự ưu tiên: cảnh báo > đang cập nhật > tạm ngừng/đóng > chưa xác minh > hoạt động.
MarkerStatus markerStatusOf(
  ChargingStation s, {
  bool hasWarning = false,
  bool isUpdating = false,
}) {
  if (hasWarning) return MarkerStatus.warning;
  if (isUpdating) return MarkerStatus.updating;
  switch (s.status) {
    case StationStatus.paused:
    case StationStatus.closed:
      return MarkerStatus.paused;
    case StationStatus.unverified:
      return MarkerStatus.unverified;
    case StationStatus.active:
      return MarkerStatus.active;
  }
}
