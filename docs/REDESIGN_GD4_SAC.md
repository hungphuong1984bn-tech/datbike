# Redesign — Giai đoạn 4 (phần Sạc): Trung tâm sạc

**Xác minh thực tế:** logic thuần Dart (`charge_session.dart`) đã chạy 7/7 kiểm thử bằng Dart SDK 3.13.7.
Các file Flutter (màn hình, widget, provider) mới chỉ qua kiểm tra CÚ PHÁP; CHƯA `flutter analyze`, CHƯA `flutter test`,
CHƯA chạy trên thiết bị (môi trường làm việc không có Flutter SDK). Chạy trước khi dùng:

    flutter pub get && flutter analyze && flutter test

## File mới
- `lib/core/charging/charge_session.dart` — ChargeTracker: tích phân năng lượng, thời gian, ETA, lịch sử (thuần Dart).
- `lib/core/charging/charge_provider.dart` — nối `bleProvider` (CHỈ ĐỌC) → tracker; lưu lịch sử bằng SharedPreferences.
- `lib/ui/ds/ds_line_chart.dart`, `lib/ui/ds/energy_battery.dart` — biểu đồ và mô hình pin dùng chung (xuất qua `ds.dart`).
- `test/charge_session_test.dart` — 7 kiểm thử.

## File sửa
- `lib/features/charging/charging_screen.dart` — viết lại hoàn toàn, 100% tiếng Việt.
- `lib/main.dart` — giữ provider sạc chạy nền (2 dòng + import). Không đụng BLE/giao thức.

## Nguồn dữ liệu & quy tắc không bịa số
| Hiển thị | Nguồn | Khi thiếu |
|---|---|---|
| % pin | `percent` | "--" |
| Công suất | `charging.power` nếu >0, ngược lại điện áp × dòng sạc | "--" |
| Điện áp / Dòng / Nhiệt độ | `voltage` / `phase` (>0) / `bmsTemp` (>0) | "--" |
| Năng lượng đã nạp | tích phân công suất; đoạn mất dữ liệu >15 giây KHÔNG cộng bù | "--" |
| Thời gian còn lại | `charging.etaSec` nếu bộ sạc báo; không thì tốc độ tăng SOC đo được (≥2 phút và ≥2%) | "Chưa đủ dữ liệu" |
| Giờ dự kiến đầy | hiện tại + thời gian còn lại | "--" |
| Quãng đường | chỉ khi xe báo `kmLeft` > 0 | ẩn |
Đã BỎ phép nhân "% × 270 km" và mọi dung lượng pin giả định khỏi màn Sạc.

## Cần bạn xác nhận
- `phase > 0` là dòng sạc (theo quy ước đã có trong `battery_sessions.dart`/test cũ).
- Ý nghĩa `charging.stage` và `charging.fault` chưa được tài liệu hóa → app chỉ báo "mã lỗi N" khi `fault != 0`, không diễn giải.
- Phiên sạc chỉ tính từ lúc ứng dụng bắt đầu nhận dữ liệu (nếu mở app giữa chừng, phần trước đó không biết).

## Còn lại (chưa làm)
Cell pin (hiệu ứng phát sáng, đồng bộ `bms_theme`), Thông số vận hành, Trung tâm chẩn đoán, Cài đặt (đơn vị đo, quản lý thông báo/kết nối),
rà tiếng Việt các chuỗi đã liệt kê ở GĐ1, đồng bộ màu cứng, kiểm thử thiết bị.

---
# Bổ sung: Cell pin + Thông số vận hành

**Xác minh:** `ops_history.dart` chạy 4/4 kiểm thử bằng Dart SDK 3.13.7; màn hình/widget chỉ qua kiểm tra cú pháp (chưa `flutter analyze`).

## Cell pin
Trung tâm cell hiện có đã đủ các mục yêu cầu: mô hình cell có phát sáng và nhấp nháy khi đổi, điện áp từng cell, Delta, cell cao/thấp nhất,
cảnh báo, theo dõi cân bằng, chi tiết cell, lịch sử điện áp — và chỉ hiển thị dữ liệu BMS thật (không cell giả khi BMS chưa gửi).
Chỉ sửa nhãn chưa Việt hóa: "Battery & BMS" → "Pin và BMS", "PACK" → "BỘ PIN", "Balancing ON/OFF" → "Đang cân bằng/Không cân bằng",
"Delta Voltage" → "Chênh áp giữa cell (Delta)". Màn BMS vẫn dùng bảng màu tối riêng (`bms_theme.dart`) — chưa gộp vào Design System.

## Thông số vận hành (màn mới, route `/operations`, menu Hồ sơ → "Thông số vận hành")
- File mới: `lib/features/operations/operations_screen.dart`, `lib/core/telemetry/ops_history.dart`, `ops_provider.dart`, `lib/ui/ds/metric_card.dart`, `test/ops_history_test.dart`.
- Sửa: `main.dart` (route + giữ provider ghi nền), `profile_screen.dart` (mục menu), vài nhãn ở `features/battery/`.
- Nội dung: tốc độ; điện áp; dòng pha; công suất điện; mở ga; nhiệt độ pin/ECU/động cơ; trạng thái bộ điều khiển và mã lỗi; chân chống, đèn, xi-nhan;
  ADC 1/2 (giá trị thô); biểu đồ 7 đường (tối thiểu/trung bình/cao nhất); độ mới của gói telemetry.
- Công suất điện = điện áp × |dòng pha| (tính toán, ghi rõ trên nhãn). Nhiệt độ/điện áp = 0 coi là "xe chưa báo" → "--".
- Mất kết nối: biểu đồ dừng và ghi nhãn; sau khi kết nối lại bắt đầu chuỗi mới (không nối hai đoạn bằng một đường thẳng).

## Cần xác nhận
- Ý nghĩa ADC 1/2 chưa có tài liệu → chỉ hiện số thô.
- Mã lỗi chỉ hiện số (chưa có bảng mã lỗi trong mã nguồn); bảng nguyên nhân/hướng xử lý sẽ làm ở Trung tâm chẩn đoán nếu bạn cung cấp danh sách mã.
