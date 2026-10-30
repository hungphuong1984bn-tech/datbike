# Redesign toàn diện — Giai đoạn 1: Phân tích hiện trạng

**Phiên bản nền:** TH DATBIKE 2.9.0+54 (Flutter, Riverpod, flutter_blue_plus).
**Trạng thái xác minh:** chỉ đọc và phân tích mã nguồn. CHƯA biên dịch, CHƯA chạy `flutter analyze` / `flutter test`
(môi trường làm việc không tải được Flutter SDK). Mọi thay đổi sau này phải được chạy kiểm tra trên máy dev/CI.

## 1. Quy mô
- 76 file Dart, ~39.700 dòng trong `lib/`; `ble_controller.dart` 4.445 dòng (KHÔNG chạm vào giao thức).
- Màn hình lớn nhất: `my_bike_screen.dart` (2.687), `vehicle_settings_screen.dart` (2.021),
  `trip_route_screen.dart` (1.676), `charge_finder_screen.dart` (1.396), `dashboard_screen.dart` (1.219).

## 2. Điều hướng hiện tại (`home_shell.dart`, `main.dart`)
- Thanh dưới 5 mục: Tổng quan · Trạm sạc · Bác sĩ Pin · Nhật ký · Cài đặt (Material 3 `NavigationBar`).
- 15 route đặt tên trong `main.dart`; chỉ tab Tổng quan được giữ sống, các tab khác huỷ khi rời (tốt cho pin/GPS).
- Chưa có hiệu ứng chuyển tab; chưa có cấu trúc nhóm chức năng rõ cho các màn phụ (Sạc, Năng lượng, Regen, Lab, OTA…).

## 3. Design System hiện có (đã khá tốt — nên NÂNG CẤP, không viết lại)
- `lib/ui/app_theme.dart`: tokens `AppSpacing/AppRadius/AppSizes/AppMotion`, `AppPalette` sáng/tối, `AppColors` (API cũ giữ tên),
  `AppTypography` (Space Grotesk + Plus Jakarta Sans), `AppTheme` đầy đủ component theme.
- `lib/ui/components.dart`: `FreshnessBadge`, `StateView` (loading/empty/error/offline/warning), `showConfirmDialog`, `showAppSnack`, `ThemeModeSelector`.
- `lib/ui/widgets.dart`: `Panel`, `StatusPill`, `MetricTile`, `VehicleCommandButton`, `RoundControl`, `BatteryRangeCapsule`, `NoticeBanner`, `SectionTitle`.
- Đổi sáng/tối bằng cách ép dựng lại cây widget (`main.dart::_applyTheme`) vì nhiều widget đọc `AppColors.*` trực tiếp.
- **Còn thiếu so với yêu cầu:** token gradient/glow/glass, thẻ nhiều lớp (`GlassCard`), số liệu có hiệu ứng cập nhật,
  biểu đồ dùng chung, hiệu ứng chuyển trang/tab, nhãn trạng thái BLE chuẩn.

## 4. Các màn hình lạc phong cách (màu cứng, palette riêng)
| File | `Color(0x…)` cứng | Ghi chú |
|---|---:|---|
| `dashboard_studio/dashboard_view.dart` | 45 | không dùng `AppColors` (0 lần) |
| `battery/bms_theme.dart` | 15 | theme riêng cho Bác sĩ Pin / Cell |
| `cluster/cluster_screen.dart` | 14 | palette riêng của đồng hồ (có chủ đích, giữ) |
| `home/trip_route_screen.dart` | 19 | lẫn `AppColors` |
| `home/my_bike_screen.dart` | 12 | trang chủ — 84 chỗ gọi `GoogleFonts` trực tiếp |
| `settings/vehicle_settings_screen.dart` | 9 | 64 chỗ gọi `GoogleFonts` trực tiếp |
Ghi chú: các màn Cockpit HUD/Cluster có palette riêng theo thiết kế (hiển thị ngoài trời) — chỉ đồng bộ phần khung, không đổi màu đồng hồ.

## 5. Vi phạm yêu cầu "tiếng Việt 100%" (đã tìm thấy bằng grep)
- `profile_screen.dart:291`, `dashboard_studio_screen.dart:83` — "Dashboard Studio"
- `proximity_screen.dart:62,80` — "Smart Unlock", "Auto Lock"
- `vehicle_settings_screen.dart:1948` — "Reset"
- `overview_status.dart:289` — "Cockpit HUD"
- `protection_view.dart:140` — "BATTERY CELL PROTECTION"
- `firmware_lab_screen.dart:525,530,707,717` — "GHI PLAIN/PROTECTED", "PROT", "PLAIN"
- `ble_controller.dart:2004` — `title: 'Dat Bike'` (tên thương hiệu thông báo; chỉ xem xét, không động vào file BLE)
- Cần rà tiếp bằng mắt trên máy: các chuỗi ghép động, tooltip, nội dung thông báo hệ thống.

## 6. Dữ liệu ước tính / giả định cần xử lý (yêu cầu "không dữ liệu thiếu căn cứ")
- `charging_screen.dart:52` và `my_bike_screen.dart:1192,1435`: quãng đường còn lại = `% pin × 270 km danh định` khi xe không báo.
  Trang chủ đã gắn nhãn ước tính; **màn Sạc chưa gắn nhãn** → phải gắn nhãn "Ước tính" hoặc ẩn.
- `charging_router_service.dart:118`: giả định pin 7,0 kWh (1% = 70 Wh) để tính năng lượng/thời gian tuyến sạc → phải ghi rõ là ước tính danh định.
- `scan_screen.dart`: xe giả lập (DEMO) đã gắn nhãn rõ — giữ.
- Thời gian sạc còn lại dùng `telemetry.charging.etaSec` từ xe (thật); khi thiếu hiển thị "Đang sạc..." — giữ, bổ sung trạng thái "chưa đủ dữ liệu".

## 7. Ma trận yêu cầu → hiện trạng (tóm tắt)
| Hạng mục | Hiện trạng | Việc cần làm |
|---|---|---|
| Trang chủ | `my_bike_screen` + `overview_status` có thẻ trạng thái | tái bố cục theo ưu tiên thông số; thêm nhiệt độ pin/SOH nếu có dữ liệu thật |
| Pin | `battery_diagnostics_screen` + 4 view | đồng bộ theme, dùng component chung |
| Cell | `cell_pack_view`, `cell_detail_screen` | hiệu ứng phát sáng nhẹ, chỉ dữ liệu BMS thật |
| Sạc | `charging_screen` (579 dòng) | thiết kế lại; biểu đồ phiên sạc; lịch sử phiên (`battery_sessions.dart` đã có) |
| Vận hành | rải ở dashboard/cluster/my_bike | tạo màn Thông số vận hành có biểu đồ theo thời gian |
| Chẩn đoán | `obd_view`, `logs_screen`, `connect_diagnostics` | gom thành Trung tâm chẩn đoán phân loại mức độ |
| Cài đặt | `profile_screen` + `vehicle_settings_screen` | thêm đơn vị đo, quản lý thông báo/kết nối nếu chưa có |

## 8. Rủi ro & ràng buộc
- Không sửa `lib/core/ble/*`, `core/session/*`, `core/proto/*`, `core/regen/*` (giao thức/xác thực/lệnh).
- Mọi dòng đọc dữ liệu thật qua `bleProvider` giữ nguyên; chỉ thay lớp trình bày.
- Không có compiler trong môi trường này → ưu tiên thay đổi nhỏ, có thể kiểm chứng, không refactor hàng loạt.
- Test hiện có (`test/*.dart`) phải tiếp tục qua; chạy `flutter analyze && flutter test` sau mỗi giai đoạn.

## 9. Đề xuất thứ tự thực hiện tiếp
GĐ2 (Design System): thêm `lib/ui/ds/` (token gradient/glow, `GlassCard`, `AnimatedMetric`, `ConnectionBadge`, `ScreenScaffold`) — chỉ thêm file mới.
GĐ3: trang chủ + điều hướng. GĐ4: sạc → pin → cell. GĐ5–8 như kế hoạch.
