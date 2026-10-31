# THBIKE – Giai đoạn 2 (Battery Intelligence): tiến độ

Phiên bản trong pubspec vẫn là 2.11.0+56 (chưa tăng version vì giai đoạn chưa nghiệm thu).

## Đã làm
- `health_view.dart`: bỏ phần trăm SOH tự suy ra; hiển thị "Chưa đủ dữ liệu đánh giá sức khỏe pin" (BMS không gửi SOH, chưa có thuật toán xác minh).
- `battery_diagnostics_service.dart`: chỉ thêm chú thích cho `healthPercentage` (không phải SOH).
- Mới `lib/core/battery/battery_history_store.dart`: lịch sử pin bền vững (JSONL, thưa 5 phút/mẫu, giữ 90 ngày), tổng hợp ngày/tuần/tháng. Chỉ ghi từ gói BMS thật còn mới; trường thiếu = null; NTC ngoài dải -40..125 °C bị bỏ.
- `battery_hub.dart`: ghi lịch sử bền vững trong `ingest` khi dữ liệu "live". "Đặt lại phiên" KHÔNG xóa lịch sử bền vững.
- Mới `lib/features/battery/views/history_view.dart` + tab "Lịch sử" trong `battery_diagnostics_screen.dart`: biểu đồ điện áp pack, SOC, nhiệt độ cao nhất, Delta theo ngày/tuần/tháng; khoảng không có mẫu bị bỏ, không nội suy.
- `obd_view.dart`: gắn nhãn mốc nhiệt độ là mặc định của ứng dụng, không phải thông số nhà sản xuất.
- Mới `test/battery_history_store_test.dart`.

## Đã có sẵn từ trước, đã rà và giữ nguyên
- Cân bằng cell: `balancing_monitor.dart` coi `balancing != 0` chỉ là "BMS báo đang cân bằng" ở mức pack, kiểu cân bằng là "Chưa xác minh", không có lệnh điều khiển (đặc tính BMS chỉ Read).
- Ngưỡng điện áp cell: mặc định null (tắt) cho tới khi người dùng nhập theo thông số BMS; ngưỡng khác có chú thích là mặc định ứng dụng (`protection_view.dart`).

## Chưa làm trong Giai đoạn 2
- Hiển thị dung lượng pin: `socAh`/`socAbsAh` có trong giao thức nhưng KHÔNG có tài liệu về ý nghĩa (không thấy trong docs/), nên chưa hiển thị như dung lượng.
- Tích hợp `DataField` vào các màn hình pin.
- Xuất/xóa lịch sử pin từ giao diện (xuất CSV/JSON thuộc Giai đoạn 3F).
- Ngưỡng cảnh báo dựa trên tài liệu BMS/nhà sản xuất: chưa có tài liệu nào được cung cấp.
- So sánh các giai đoạn sử dụng và phát hiện xu hướng bất thường trên lịch sử dài hạn.

## Kiểm chứng
- `flutter analyze`, `flutter test`, build APK: CHƯA chạy (môi trường không có Flutter SDK).
- Đã chạy `tool/check_imports.py` (OK) và kiểm tra cân bằng ngoặc các file đã sửa. Đây KHÔNG thay thế analyze/test.
- Chưa kiểm thử trên xe thật.
