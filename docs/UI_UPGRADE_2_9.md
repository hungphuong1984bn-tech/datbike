# Nâng cấp giao diện Premium UI/UX — ghi chú bàn giao

**Trạng thái xác minh:** chỉ kiểm tra cú pháp (`dart format`). CHƯA chạy `flutter analyze`,
`flutter test`, `flutter build`, và CHƯA thử trên thiết bị. Chạy trước khi phát hành:

    flutter pub get && flutter analyze && flutter test && flutter build apk

## Đã triển khai
- Dark/Light (Hệ thống/Sáng/Tối, lưu bền) — `lib/ui/app_theme.dart`, `lib/core/config/ui_prefs.dart`, `lib/main.dart`
- Design tokens (AppSpacing/AppRadius/AppSizes/AppMotion) + `AppColors.readable()` cho chữ đạt tương phản
- Component: `lib/ui/components.dart` (FreshnessBadge, TickBuilder, StateView, showConfirmDialog, showAppSnack, ThemeModeSelector)
- Điều hướng 5 mục: Tổng quan · Bản đồ · Bác sĩ Pin · Nhật ký · Cài đặt (`home_shell.dart`)
- Tổng quan: thẻ trạng thái (kết nối, pin, tốc độ gần nhất + dấu thời gian, cảnh báo), lối tắt Cockpit HUD / Sạc & Năng lượng / Hành trình; km ước tính gắn nhãn
- Nhật ký: tìm kiếm, lọc thời gian, loading/empty/error + thử lại, báo tiến trình đọc file
- Bác sĩ Pin: chú giải Đo từ xe / Ước tính / Chưa có; SOH gắn "Ước tính"; bỏ giá trị mặc định bịa (nhiệt 32/30/29 °C, 18.5 mΩ)
- Kết nối xe: xe giả lập trên Web gắn nhãn DEMO; banner lỗi có nút Thử lại
- Cài đặt: chọn giao diện, mục Sạc & Năng lượng, dialog ngắt kết nối dùng component chuẩn

## Thay đổi hành vi cần biết
- `BleController.lastTelemetryAt` — getter chỉ-đọc mới, không đổi giao thức BLE.
- Màn "Năng Lượng" không còn là tab; vào từ Tổng quan hoặc Cài đặt.
- Nhật ký BLE/Lab không còn là nút trên header Tổng quan (Nhật ký là tab; Lab nằm trong Cài đặt).

## Chưa làm / cần rà bằng mắt trên máy
- Cockpit HUD (`/dashboard`, `/cluster` có palette riêng), Bản đồ, Trip route ở chế độ tối
- Bóng đổ `Color(0x060F172A)` cũ, gradient `1E293B`, `Colors.white54` còn cứng
- Ánh xạ `Colors.white` → nền thẻ và `F1F5F9` → viền/nền dựa theo ngữ cảnh dòng code
- Ngang/dọc, màn nhỏ/lớn, offline, thiếu quyền chưa kiểm thử
