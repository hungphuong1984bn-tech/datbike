# Trung tâm điều khiển vận hành (Grab · ECE · Regen)

Màn hình: `lib/features/control_center/control_center_screen.dart` (route `/control-center`).
Lõi: `lib/core/control/`. Ngày kiểm tra mã nguồn: 31/10/2026.

## 1. Bằng chứng đã có trong dự án

| Chế độ | Characteristic | Kiểu / lệnh | Bằng chứng | Mức |
|---|---|---|---|---|
| Grab | `a1d8e7c4-5b3f-4902-8a6e-9c0d2f1e3b4a` | Protected R/W, 1 byte, ghi ASCII `'0'`/`'1'`, đọc về u8 | Ghidra `onWriteGrabMode @0x40153e30` (parser boolean); Lab 23/10: ghi `1`→đọc `01`, ghi `0`→đọc `00` | Lab + decompile (chưa có test vector capture) |
| ECE | `3b56ac38-60fb-40f8-a42c-fa09e0714e44` | như trên | Ghidra `onWriteEceMode @0x40153bd0`; Lab 24/10 PASS ×3 | Lab + decompile |
| SpeedLimit | `0a19a49a-23bc-45ab-b2e9-4bf31665c76b` | như trên | Ghidra `onWriteSpeedLimit @0x40153d50`; chỉ có hiệu lực khi ECE = 1 | Lab + decompile |
| Regen | — | — | **Không có** characteristic Regen độc lập | Chưa xác minh |

Lưu ý quan trọng:

* **Grab ≠ Regen.** Người dùng quan sát ngày 28/10 rằng đổi kênh Grab làm đổi dòng nạp ngược. Đó là ảnh hưởng chéo chưa đo (không biết hướng mạnh/yếu), không phải bằng chứng có kênh Regen. Vì vậy Grab được điều khiển như Grab; thẻ Regen chỉ đọc.
* **Chỉ 0/1.** Parser là boolean; không có bằng chứng về nhiều mức. App không gửi giá trị nào khác 0/1.
* **60 km/h** là con số từ ghi chú dự án. Lab chỉ ghi "~60" kèm gợi ý kiểm chứng ("chạy xe xem có bị chặn ~60 km/h"). **Chưa có số đo độc lập.** App chỉ hiển thị "Giới hạn 60 km/h" khi đọc lại ECE = 1 **và** SpeedLimit = 1, kèm chú thích này.
* **Dấu dòng pha** mâu thuẫn giữa `bike_log.dart` ("dương = tái tạo") và tài liệu giao thức ("âm khi phanh tái sinh"). Thẻ Regen hiển thị giá trị có dấu + hai cực trị, không gắn nhãn "đang nạp ngược".
* **RECUP** (`BleController.setRecupLevel`) và độ nhạy ga là **hồ sơ cục bộ** (SharedPreferences), không ghi xuống xe và không được UI trình bày như thông số của xe.

## 2. Hành vi

* Không có đường tự động nào gọi `command()`: không khi mở app, không khi kết nối/kết nối lại BLE, không khi mở màn hình. Mở màn hình chỉ **đọc** (`sync()`).
* Giá trị công tắc luôn là giá trị **đọc từ xe**. Khi mất kết nối, giá trị bị xoá (không giữ giá trị cũ như thật). Cờ ECE/SpeedLimit/Grab **không còn được nạp từ cache** lúc khởi động `BleController`.
* Công tắc bị khóa cho tới khi đã đọc được trạng thái thật (không gạt "mù").
* Trước khi gửi: kết nối + xác thực + xe đứng yên + telemetry < 4 giây (tái dùng `regenBlockReason`). Chính sách "chỉ khi đứng yên" là **chính sách của app**, chưa có tài liệu nhà sản xuất yêu cầu hay cho phép khác.
* Hộp thoại xác nhận → gửi 1 lệnh → chờ 400 ms → đọc lại → so khớp. Không khớp / không đọc được / mất kết nối / bị từ chối → **KHÔNG XÁC NHẬN**. **Không tự thử lại.**
* Chống lệnh lặp: một lệnh tại một thời điểm + nguội 3 giây giữa hai lệnh ghi của cùng một chế độ.
* ECE ghi theo thứ tự đã Lab: SpeedLimit rồi ECE; nếu cờ đầu lỗi thì không ghi cờ sau. Nếu ghi được một phần, UI nói rõ và yêu cầu "Đồng bộ".
* Truy vết: mỗi lệnh có id `grab-<ms>-<n>` / `ece-…`, ghi vào `BleLogger` qua các sự kiện `mode_cmd_start`, `mode_write`, `mode_write_readback`, `mode_cmd_confirmed|not_confirmed|rejected|blocked_*`.
* Độc lập: Grab chỉ chạm `a1d8e7c4`; ECE chỉ chạm `3b56ac38` + `0a19a49a`; Regen không ghi gì.

## 3. Đã gỡ khỏi mã (vì vi phạm nguyên tắc)

* `RegenController.probeHigherLevels()` — tự ghi 2, 3, 4 xuống xe để "dò mức".
* `GrabMaxLevelNotifier` / `RegenProtocolSpec.grab(maxLevel)` — cho phép mức tới 9 (kể cả "thử nghiệm").
* `BleController.writeGrabLevelRaw` (0..9), `setFwGrabMode`, `setFwEceMode`, `setFwSpeedLimit`, `grabBlockReason`, `readGrabRaw`, `noteGrabLevel`, `resyncGrabFromBike`.
* `BleController.setSafeSpeedLimit60` — khi mất kết nối nó **đổi trạng thái ECE trên UI** và hứa "khi kết nối lại app sẽ ghi xuống xe" (không có mã nào làm vậy). Đây là trạng thái giả.
* `setEceMode` / `setGrabMode` / `setSpeedLimitMode` — setter cache cục bộ.
* Công tắc ECE/Grab ở `my_bike_screen.dart` và `vehicle_settings_screen.dart` → thay bằng lối vào Trung tâm điều khiển (một đường lệnh duy nhất).

## 4. Chưa hỗ trợ / ngoài phạm vi

* Điều khiển mức Regen: không có giao thức. Mở khoá theo `docs/REGEN_VERIFICATION.md` khi có btsnoop/Ghidra.
* Nhiều mức Grab: không có bằng chứng.
* Firmware Lab (`/lab`) có "Custom char tester" cho phép ghi **bất kỳ UUID/payload** (kể cả Grab/ECE với giá trị lạ) mà **không qua cổng an toàn**. Đây là công cụ nghiên cứu chủ động, **chưa bị thay đổi**; cần quyết định riêng có giữ/khoá không.
* `vehicle_settings_screen.dart` còn nhãn "Giới hạn: 50 km/h / 30 km/h" cho `speedLimitMode` trong các phần khác, mâu thuẫn với ghi chú 60 km/h — chưa đối chiếu.
* Thư mục gốc `core/` và `main.dart` (ngoài `lib/`) là bản **cũ** của mã nguồn, không được build; chứa các hàm ghi cũ. Nên xoá hoặc đồng bộ để tránh nhầm.

## 4b. Câu hỏi thiết kế cần chủ dự án xác nhận

"ECE OFF" ở đây là **tắt tuỳ chọn giới hạn do firmware cung cấp** (cặp cờ ECE+SpeedLimit đã Lab), có hộp thoại cảnh báo và cổng đứng yên. Nếu yêu cầu "không vô hiệu hoá giới hạn tốc độ" nghĩa là **không cho phép tắt**, chỉ cần khoá nhánh `command(false)` của `EceModeController` (một dòng).

## 5. Kiểm thử

`test/control_center_test.dart` (mới), `test/regen_test.dart` và `test/immobilizer_and_safe_speed_test.dart` (đã chỉnh). Các lớp giả trong test chỉ để kiểm tra máy trạng thái; chúng không chứng minh xe thật phản hồi đúng.

Tình huống có test tự động: bật/tắt Grab, bật/tắt ECE (cặp cờ), khởi động không tự gửi/đọc, ngắt–kết nối lại không gửi lệnh, xe không phản hồi (từ chối / không đổi / lỗi GATT / không đọc lại được / mất kết nối giữa chừng), xe đang chạy, telemetry cũ, chưa biết tốc độ, chưa kết nối, chống lệnh lặp, giá trị thô lạ, ba chế độ không chạm nhau, Regen không có đường ghi, giao diện (3 thẻ, 2 công tắc, xác nhận trước khi gửi, 320 dp).

## 6. Cần thiết bị thật để xác minh

1. Ghi/đọc lại Grab 0↔1 trên xe thật: xe có đọc lại đúng? Độ trễ 400 ms có đủ không?
2. ECE ON/OFF: cả hai cờ đọc lại đúng? Mức trần thực tế đo được bao nhiêu km/h?
3. Hướng và độ lớn ảnh hưởng của Grab lên dòng nạp ngược (bảng cực trị trong thẻ Regen); kiểm chứng dấu dòng pha.
4. Hành vi khi mất kết nối giữa lệnh ECE (cờ đầu đã ghi, cờ sau chưa).
5. Xe có từ chối đổi khi đang chạy không (nếu có, chính sách "đứng yên" có thể nới theo bằng chứng).
6. Thử kê chống trước, rồi mặt đất.
