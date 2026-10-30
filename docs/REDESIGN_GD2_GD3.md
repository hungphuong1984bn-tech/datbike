# Redesign — Giai đoạn 2 (Design System v3) & 3 (Trang chủ + Điều hướng)

**Xác minh:** chỉ kiểm tra cú pháp bằng trình phân tích Dart (tree-sitter). CHƯA chạy `flutter analyze`,
`flutter test`, `flutter build`, CHƯA thử trên thiết bị. Chạy trước khi dùng:

    flutter pub get && flutter analyze && flutter test

## Giai đoạn 2 — file mới (chỉ thêm, không đổi file cũ)
`lib/ui/ds/` — import qua `ui/ds/ds.dart`
- `ds_tokens.dart`: `Severity` (Bình thường/Thông tin/Cảnh báo/Nghiêm trọng), `AppGradients` (page, hero, energy), `AppGlow.soft`.
- `glass_card.dart`: `GlassCard` — thẻ nhiều lớp; `hero`, `accent` (viền+glow), `blur` (mặc định tắt để nhẹ máy).
- `animated_metric.dart`: `AnimatedMetric` — số liệu đếm mượt; `value == null` → "--" (không bịa số).
- `connection_badge.dart`: `ConnectionBadge(phase)` — trạng thái BLE chuẩn, tiếng Việt (chỉ đọc enum `BlePhase`).
- `ds_scaffold.dart`: `DsScaffold` (khung trang con thống nhất), `DsSectionHeader`.

## Giai đoạn 3 — thay đổi
- `lib/features/home/home_hero.dart` (mới): `HomeHeroCard` — tên xe/đổi xe, trạng thái kết nối, SOC lớn, quãng đường còn lại
  (gắn "Ước tính" khi xe không báo), thanh năng lượng (chạy khi sạc), ảnh xe, huy hiệu Sẵn sàng/Đã khóa/Chế độ lái/Hú còi,
  vùng cảnh báo (chân chống, mã lỗi xe), 4 ô thông số: Tốc độ · Công suất · Nhiệt độ pin · Điện áp, nhãn độ mới dữ liệu.
- `lib/features/home/my_bike_screen.dart`: thay phần đầu trang (header, cụm km, thẻ trạng thái, ảnh xe) bằng `HomeHeroCard`;
  GIỮ NGUYÊN lối tắt, 5 nút điều khiển nhanh, thẻ chuyến đi và mọi hàm điều khiển (`_quickLockToggle`, `_quickPowerToggle`, …).
  Mất kết nối vẫn hiện giá trị cuối kèm "Dữ liệu cũ".
- `lib/features/home/home_shell.dart`: thanh điều hướng dưới tự dựng (viên thuốc chỉ thị trượt, icon phóng nhẹ, haptic),
  hiệu ứng chuyển tab mờ dần + trượt 1,5%. Vẫn 5 tab, vẫn chỉ giữ sống tab Tổng quan, Back về Tổng quan như cũ.

## Dữ liệu — nguồn từng ô trên trang chủ (đều từ `ble.lastTelemetry`)
| Ô | Trường | Khi thiếu |
|---|---|---|
| SOC | `percent` | "--" |
| Quãng đường | `kmLeft` (nếu >0), else `% × 270 km` nhãn "Ước tính" | "--" |
| Tốc độ | `speed` | "--" |
| Công suất | `voltage × |phase|` (W) | "--" nếu điện áp = 0 |
| Nhiệt độ pin | `bmsTemp` | "--" nếu = 0 |
| Điện áp | `voltage` | "--" nếu = 0 |
| Cảnh báo | `isSideStandDown`, `error != 0` | ẩn |
Chưa hiển thị SOH trên trang chủ: app không đo được SOH trực tiếp (chỉ ước tính ở màn Bác sĩ Pin) nên không đưa lên khu vực ưu tiên.

## Giả định cần bạn xác nhận
- `bmsTemp == 0` và `voltage == 0` được coi là "chưa có giá trị". Nếu xe có thể báo đúng 0 °C thật, cần đổi sang cờ hợp lệ.
- Công suất = điện áp pin × |dòng pha động cơ| (cùng cách `charging_screen` đang tính) — là công suất điện ước lượng, không phải số đo trực tiếp của BMS.

## Còn lại
GĐ4 sạc → pin → cell; GĐ5 vận hành + chẩn đoán; GĐ6 cài đặt + màn phụ; GĐ7 đồng bộ màu cứng (`dashboard_view`, `bms_theme`, `trip_route`); GĐ8 kiểm thử.
Chưa kiểm tra: màn nhỏ (360dp), chữ hệ thống phóng to, chế độ sáng — cần xem bằng mắt trên máy.
