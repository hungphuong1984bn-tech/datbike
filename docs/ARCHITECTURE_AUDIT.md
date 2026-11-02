# Kiểm tra kiến trúc (2.11.1)

## Đã kiểm tra — ĐẠT, không cần sửa
- BLE: chỉ có MỘT `bleProvider` (BleController) quản lý kết nối; chỗ khác chỉ gọi `connect()` qua provider, `scan_screen` chỉ quét.
- Vòng đời widget: 14 màn hình/widget có Timer/StreamSubscription đều hủy trong `dispose()`.
- BleController: `ref.onDispose(_teardown)` hủy timer + subscription.
- Lỗi: có `FlutterError.onError` + `PlatformDispatcher.onError` trong `main.dart`.
- Log: `BleLogger` đã che dữ liệu nhạy cảm qua `Redactor`.

## Đã sửa
1. Mật khẩu xe chuyển từ SharedPreferences sang `flutter_secure_storage` (`core/session/secret_store.dart`). Người dùng cũ tự được di chuyển; nếu kho bảo mật lỗi thì giữ bản cũ, không mất ghép đôi.
2. RSSI chỉ cập nhật state khi giá trị đổi (giảm rebuild toàn app).
3. Màn Mở khóa thông minh dùng `select` thay vì watch toàn BleState.
4. RSSI đo bằng timer riêng, có hủy đầy đủ (không rò timer).

## Còn tồn đọng (cần làm riêng, có trình biên dịch)
- 15 màn hình vẫn `ref.watch(bleProvider)` toàn bộ → nên chuyển dần sang `select`.
- `ble_controller.dart` ~4500 dòng: nên tách thành reconnect / auth / commands / proximity-runner.
- Thư mục `core/` và `main.dart` ở GỐC repo là bản cũ trùng với `lib/` (không được build) → nên xóa để khỏi nhầm.
