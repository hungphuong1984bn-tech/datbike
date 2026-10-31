# THBIKE 2.11.0+56 — Giai đoạn 1: BLE Reliability

Nâng từ 2.10.0+55 (lịch sử version: 2.9.0+54 → 2.10.0+55 → 2.11.0+56).
Ký APK giữ nguyên cấu hình hiện tại (khóa debug) theo yêu cầu; không thay đổi applicationId.

## File tạo mới
- `lib/core/ble/ble_link_status.dart` — 14 trạng thái liên kết dẫn xuất (kết nối ≠ có dữ liệu), chất lượng RSSI, ánh xạ bước kết nối.
- `lib/core/ble/data_field.dart` — `DataField<T>` (giá trị, đơn vị, nguồn, thời điểm nhận, hợp lệ, mới/cũ/cache), `TelemetryFields`, `BatteryFields`.
- `lib/core/ble/ble_diag_stats.dart` — bộ đếm gói/lỗi/ngắt kết nối/notify/xác thực.
- `lib/core/ble/log_export.dart` — đọc JSONL, lọc thời gian/loại, xuất JSON/CSV, che dữ liệu nhạy cảm.
- `lib/core/ble/protocol_evidence.dart` — sổ mức bằng chứng giao thức.
- `lib/features/ble_diagnostics/ble_diagnostics_screen.dart` — trang "Chẩn đoán Bluetooth (BLE)" (Cài đặt › Chẩn đoán và phần mềm).
- Test: `ble_link_status_test`, `data_field_test`, `ble_diag_stats_test`, `log_export_test`, `protocol_evidence_test`.

## File sửa
- `ble_controller.dart`: chỉ THÊM các lời gọi `BleDiagStats.record*` và getter `currentConnectStage`. Không đổi luồng kết nối/xác thực/lệnh.
- `connect_diagnostics.dart`: thêm `Redactor.sanitizeStrict` (không đổi hành vi cũ).
- `auth_probe.dart`: chỉ sửa comment lỗi thời ("placeholder CHƯA VERIFY").
- `app_info.dart`, `pubspec.yaml`: 2.11.0+56. User-Agent không còn ghi cứng phiên bản.
- `profile_screen.dart`, `feature_catalog.dart`: lối vào + mục danh mục (trạng thái "Đang phát triển").

## Chưa làm trong giai đoạn này (cố ý)
- Không thêm UUID/command/payload mới; không đổi thuật toán xác thực.
- "Lưu thiết bị đã ghép nối / kết nối lại" đã có sẵn trong controller (last_bike_id, backoff 5 lần) — chưa sửa.
- Chưa thay `BlePhase` bằng trạng thái mới; `BleLinkStatus` là lớp suy ra song song, hiện chỉ trang chẩn đoán dùng.
- Chưa tích hợp `DataField` vào các màn hình khác (Giai đoạn 2/6).
- Chưa kiểm thử vòng đời BLE (kết nối lại, tắt Bluetooth) bằng test tự động: cần giả lập `flutter_blue_plus`.

## Kiểm chứng đã làm
Xem báo cáo trong cuộc trò chuyện: dart analyze + chạy test thuần Dart bằng shim. `flutter analyze/test/build apk` CHƯA chạy.
