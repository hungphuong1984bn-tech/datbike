// Danh mục chức năng THBIKE — đối chiếu với mã nguồn thực tế (đánh giá qua
// đọc mã + bộ kiểm thử; KHÔNG phải kết quả thử trên từng đời xe).
//
// Quy tắc: không liệt kê chức năng chưa có như đang hoạt động. Mọi số liệu xe/pin
// chỉ hiển thị khi xe/BMS thực sự báo; thiếu dữ liệu app hiển thị "--".

import 'package:flutter/material.dart';

enum FeatureStatus {
  done('Đã hoàn thiện'),
  limited('Hoạt động, còn hạn chế'),
  inDev('Đang phát triển'),
  unsupported('Chưa hỗ trợ');

  final String label;
  const FeatureStatus(this.label);
}

class FeatureItem {
  final String title;
  final String note;
  final FeatureStatus status;
  const FeatureItem(this.title, this.status, this.note);
}

class FeatureGroup {
  final String code;
  final String title;
  final IconData icon;
  final List<FeatureItem> items;
  const FeatureGroup(this.code, this.title, this.icon, this.items);
}

const List<FeatureGroup> kFeatureCatalog = [
  FeatureGroup('A', 'Quản lý xe điện', Icons.two_wheeler_rounded, [
    FeatureItem('Kết nối xe qua Bluetooth (BLE)', FeatureStatus.limited,
        'Quét, ghép đôi, tự kết nối lại. Giao thức xây dựng từ phân tích, không có tài liệu chính thức; xe chỉ nhận một kết nối cùng lúc.'),
    FeatureItem('Theo dõi trạng thái kết nối', FeatureStatus.done,
        'Hiển thị các pha kết nối và chẩn đoán lý do khi kết nối thất bại.'),
    FeatureItem('Thông tin xe (tên, mẫu, số khung, phần mềm, ODO)', FeatureStatus.limited,
        'Chỉ hiển thị khi xe báo; chưa có dữ liệu thì hiện "--".'),
    FeatureItem('Thông số vận hành & hành trình GPS', FeatureStatus.limited,
        'Tốc độ, quãng đường, chuyến đi theo dữ liệu xe và GPS điện thoại.'),
  ]),
  FeatureGroup('B', 'Quản lý pin', Icons.battery_charging_full_rounded, [
    FeatureItem('Dung lượng pin (SOC), điện áp, dòng điện, công suất', FeatureStatus.limited,
        'Lấy từ telemetry/BMS thật; trường nào xe không báo sẽ không hiển thị.'),
    FeatureItem('Nhiệt độ pin', FeatureStatus.limited, 'Chỉ khi BMS cung cấp cảm biến nhiệt.'),
    FeatureItem('Tình trạng pin & cảnh báo', FeatureStatus.limited,
        'Dựa trên ngưỡng bảo vệ trong ứng dụng; SOH chỉ là ước tính.'),
    FeatureItem('Điện áp từng cell', FeatureStatus.limited, 'Khi BMS gửi gói dữ liệu cell.'),
  ]),
  FeatureGroup('C', 'Giám sát cell pin', Icons.grid_view_rounded, [
    FeatureItem('Điện áp từng cell & biểu đồ chênh lệch (Delta)', FeatureStatus.limited,
        'Khi BMS gửi dữ liệu cell.'),
    FeatureItem('Cảnh báo cell bất thường', FeatureStatus.limited,
        'Theo ngưỡng của ứng dụng, chỉ là gợi ý để kiểm tra.'),
    FeatureItem('Theo dõi trạng thái cân bằng cell', FeatureStatus.limited,
        'Chỉ GIÁM SÁT cờ cân bằng do BMS báo; không suy đoán cell nào đang cân bằng.'),
    FeatureItem('Điều khiển cân bằng cell', FeatureStatus.unsupported,
        'Ứng dụng không ghi lệnh cân bằng xuống BMS.'),
  ]),
  FeatureGroup('D', 'Quản lý sạc', Icons.ev_station_rounded, [
    FeatureItem('Trạng thái sạc, SOC, điện áp, dòng điện, công suất', FeatureStatus.limited,
        'Theo telemetry thật của xe.'),
    FeatureItem('Thời gian sạc & biểu đồ quá trình sạc', FeatureStatus.done,
        'Ghi nhận từ phiên sạc đang diễn ra.'),
    FeatureItem('Ước tính thời gian sạc còn lại', FeatureStatus.limited,
        'Chỉ hiển thị khi đủ dữ liệu; đây là ước tính.'),
    FeatureItem('Lịch sử phiên sạc', FeatureStatus.done, 'Lưu trên máy này.'),
  ]),
  FeatureGroup('E', 'Chẩn đoán & cảnh báo', Icons.health_and_safety_rounded, [
    FeatureItem('Mã lỗi xe/pin và giải thích', FeatureStatus.limited,
        'Chỉ các mã xe báo và có trong bảng mô tả của ứng dụng.'),
    FeatureItem('Lịch sử cảnh báo & nhật ký', FeatureStatus.done,
        'Lưu cục bộ, có thể xuất để gửi kỹ thuật viên.'),
    FeatureItem('Kiểm tra kết nối và dữ liệu', FeatureStatus.done,
        'Báo cáo chẩn đoán kết nối Bluetooth.'),
  ]),
  FeatureGroup('F', 'Bản đồ trạm sạc', Icons.map_rounded, [
    FeatureItem('Tìm kiếm trạm & xem trên bản đồ', FeatureStatus.limited,
        'Dữ liệu cộng đồng OpenStreetMap, cần Internet, có thể thiếu hoặc sai.'),
    FeatureItem('Tìm theo khoảng cách, xem thông tin trạm', FeatureStatus.limited,
        'Thuộc tính nào nguồn không có sẽ ghi "Chưa có dữ liệu".'),
    FeatureItem('Chỉ đường', FeatureStatus.limited, 'Mở ứng dụng bản đồ bên ngoài để dẫn đường.'),
    FeatureItem('Xác minh tương thích trạm với xe', FeatureStatus.unsupported,
        'Ứng dụng không xác minh được trạm có phù hợp cổng/bộ sạc của xe.'),
  ]),
  FeatureGroup('G', 'Cài đặt', Icons.settings_rounded, [
    FeatureItem('Quản lý kết nối', FeatureStatus.done, 'Ghép đôi xe mới, ngắt kết nối.'),
    FeatureItem('Giao diện sáng/tối, tùy chỉnh đồng hồ', FeatureStatus.done, ''),
    FeatureItem('Thông báo', FeatureStatus.done, 'Quản lý quyền thông báo.'),
    FeatureItem('Thông tin ứng dụng & phiên bản', FeatureStatus.done, 'Trang Giới thiệu THBIKE.'),
  ]),
];
