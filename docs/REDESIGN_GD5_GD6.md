# Redesign — Giai đoạn 5 (Trung tâm chẩn đoán) và 6 (Cài đặt, màn phụ)

**Xác minh:** chỉ kiểm tra CÚ PHÁP toàn bộ file Dart bằng tree-sitter (đều qua). KHÔNG có Flutter/Dart SDK trong môi trường làm việc
nên CHƯA chạy `flutter analyze`, `flutter test`, `flutter build`, CHƯA thử trên thiết bị. Bắt buộc chạy trước khi dùng:

    flutter pub get && flutter analyze && flutter test

## Giai đoạn 5 — Trung tâm chẩn đoán (tab "Chẩn đoán" thay tab "Nhật ký", route `/diagnostics`)
File mới
- `lib/core/diagnostics/diag_model.dart` — thuần Dart: `DiagEvent`, `DiagLog` (khóa lỗi, mở/đóng lỗi, giới hạn 300 mục, JSON), `VehicleHealth`.
- `lib/core/diagnostics/diag_provider.dart` — nối `bleProvider` + `batteryHubProvider` (CHỈ ĐỌC) → nhật ký; lưu SharedPreferences (`diag_log_v1`).
- `lib/features/diagnostics/diagnostics_screen.dart` — 4 tab: Tổng quan · Lỗi hiện tại · Lịch sử lỗi · Nhật ký (Hoạt động / BLE / BMS / Xe) + trang chi tiết lỗi (nguyên nhân, hướng xử lý).
- `test/diag_model_test.dart` — 10 kiểm thử logic (chưa chạy được ở đây).
File sửa: `home_shell.dart` (tab), `main.dart` (route + giữ provider chạy nền), `logs_screen.dart` (nhãn).

Nguồn dữ liệu — không bịa
| Mục | Nguồn | Ghi chú |
|---|---|---|
| Lỗi xe | `BatteryDiagnosticsService.obdItems` (bảng mô tả có sẵn trong app) | chỉ mục không khỏe; mã lỗi lạ → ghi đúng mã, KHÔNG suy đoán |
| Cảnh báo BMS | `ProtectionReport.alerts` | chỉ khi dữ liệu BMS đang trực tiếp |
| Mất kết nối / không giải mã | `BlePhase`, `dashboardEncrypted` | |
| Hoạt động | đổi trạng thái xe, khóa/mở khóa, bắt đầu/kết thúc sạc | chỉ ghi khi giá trị ĐỔI |
Chưa kết nối → "Chưa có dữ liệu" (không bao giờ hiện "Tốt" khi chưa biết). Mất kết nối → các lỗi xe/BMS được đóng; mở lại app → lỗi còn mở của phiên trước được đóng.
Nhật ký không chứa khóa phiên/token (chỉ tiêu đề + mô tả cố định + số đo).

## Giai đoạn 6 — Cài đặt
- `profile_screen.dart` (tab Cài đặt) viết lại: hồ sơ + 4 nhóm (Xe và kết nối · Năng lượng và vận hành · Chẩn đoán và phần mềm · Ứng dụng), mỗi mục có mô tả; "Hello/Dat Bike User" → tiếng Việt.
- `settings/app_settings_screen.dart` (mới, route `/app-settings`): giao diện sáng/tối, ngôn ngữ, xoay ngang, giữ màn hình sáng, đơn vị đo, quyền thông báo, kết nối (ghép/ngắt), thông tin xe, phiên bản, giải thích thuật ngữ (SOC, SOH, BLE, BMS, Cell, Delta, Regen, OTA).
- Việt hóa: "WARNING/CRITICAL", "FILES", "BETA/OFFICIAL", "SPEED:" ở các màn cũ.

## Chưa làm / cần quyết định
- **Đơn vị đo**: chỉ HIỂN THỊ hệ mét (km, km/h, °C…). Chưa có lựa chọn dặm/°F vì phải đổi mọi màn và đồng hồ; làm nửa vời sẽ hiển thị lẫn lộn.
- **Ngôn ngữ**: chỉ tiếng Việt (đúng yêu cầu 100% tiếng Việt).
- **Giai đoạn 7 (màu cứng)**: CHƯA làm. `bms_theme.dart` (giao diện tối riêng, nhiều chỗ dùng `const`), `dashboard_view.dart` (45 màu cứng), `trip_route_screen.dart` (19) vẫn lệch Design System; đổi sang `AppColors` cần compiler + xem trên máy để không vỡ `const`/độ tương phản.
- Cluster/HUD giữ palette riêng (chủ ý).
- Bảng mã lỗi xe chính thức: app chỉ có bảng nội bộ cho mã 1–6, 11–13, 18, 20–22; mã khác chỉ hiện số.
- Chưa kiểm tra: màn 360dp, chữ hệ thống phóng to, chế độ sáng, hiệu năng danh sách dài.
