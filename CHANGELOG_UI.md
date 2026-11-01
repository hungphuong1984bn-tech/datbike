# Redesign UI — "Digital Cockpit" (Premium EV)

Chỉ thay đổi trình bày. Không đổi: BLE/UUID/GATT, Provider, Repository, Service, API, dữ liệu, quyền hệ thống, chuỗi hiển thị (test vẫn khớp).
Bản gốc: thư mục `lib` được sao lưu trước khi sửa.

## File đã sửa (13) + 1 file mới
- ui/app_theme.dart   — palette Graphite/Navy/Electric Blue/Cyan (Dark + Light), radius lớn hơn, bóng nhẹ, theme nút/slider/tab/segmented, token `electric`, `electricGlow`, `electricGradient`
- ui/widgets.dart     — Panel, StatusPill, MetricTile, VehicleCommandButton (gradient Electric→Cyan), RoundControl, BatteryRangeCapsule, NoticeBanner, SectionTitle
- ui/ds/ds_tokens.dart, ui/ds/glass_card.dart — gradient hero/page, viền thẻ
- ui/gauge.dart      — vòng cung tốc độ Electric→Cyan có quầng sáng, số km/h lớn hơn
- ui/map_style.dart (MỚI) + features/navigation/charge_finder_screen.dart — bản đồ Google ở Dark Mode (chỉ thêm tham số `style`)
- features/home/home_shell.dart, my_bike_screen.dart, home_hero.dart — thanh điều hướng, nút thao tác nhanh dạng squircle, tốc độ nổi bật hơn
- features/battery/bms_theme.dart, cluster/cluster_screen.dart (theme mặc định), splash/splash_overlay.dart — đồng bộ màu

## Cố ý KHÔNG đổi
- Các theme người dùng tự chọn trong Dashboard Studio / Cluster (tính năng tùy biến).
- Bản đồ vẫn dùng đúng nguồn tile / trạm sạc cũ.

## Cần chạy trên máy có Flutter
flutter pub get && flutter analyze && flutter test
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
