# Nâng cấp Premium BMS (Battery Management System)

## Kiến trúc
- `lib/core/battery/` (thuần Dart, kiểm thử được): `cell_model`, `battery_config`, `battery_analytics`,
  `cell_protection_engine`, `balancing_monitor`, `battery_history`, `battery_sessions`, `battery_hub` (Riverpod).
- `lib/features/battery/`: `bms_theme`, `battery_diagnostics_screen` (5 tab), `cell_detail_screen`,
  `views/*` (health, protection, balancing, obd), `widgets/*` (cell_pack_view, bms_charts).
- Thay đổi duy nhất ở BLE: `BleState.lastBatteryAt` (thời điểm nhận gói BMS), gán trong `_handleBatteryPayload`.
  Không đổi UUID, giao thức, xác thực hay luồng đọc.

## Nguyên tắc dữ liệu
- Số cell = đúng số `cellVols` BMS gửi. Không có dữ liệu cell giả.
- Mỗi chỉ số gắn nhãn: BMS đo / Tính toán / Ước tính / Không có. SOH là ước tính (BMS không gửi).
- Dữ liệu cũ/mất kết nối: UI mờ đi, banner cảnh báo, engine không đánh giá lại số đo cũ như trực tiếp.
- Ngưỡng quá/thấp áp cell mặc định TẮT; người dùng nhập theo thông số nhà sản xuất.

## Giới hạn đã xác minh
- `BATTERY_LOG_CHAR` chỉ Read → app KHÔNG điều khiển cân bằng, không ghi lệnh xuống BMS (có test quét mã).
- Ý nghĩa bit của `balancing`/`protection`/`protections`/`error`, kiểu cân bằng (thụ động/chủ động),
  cell nào đang cân bằng, tiến trình cân bằng: chưa có tài liệu → không suy đoán.
- Dấu của `BatteryLogMsg.current` chưa xác minh; hướng sạc/xả lấy từ telemetry `phase` (đã xác minh).
- Lịch sử chỉ lưu RAM trong phiên (chưa ghi đĩa); chỉ ghi khi màn hình BMS hoặc hub đã được khởi tạo.
