# TH DATBIKE v2.9.0 — Bàn giao

Phiên bản: `2.9.0+54` (từ 2.8.0+53). Application ID giữ nguyên: `vn.mybike.mybike_app`.

## 0. Trạng thái trung thực (đọc trước)

| Hạng mục | Trạng thái |
|---|---|
| Build APK / `flutter analyze` / `flutter test` | **CHƯA chạy.** Môi trường tạo bản này không truy cập được `storage.googleapis.com`, `pub.dev`, `dl.google.com`, Gradle/Maven nên không có Flutter SDK/Android SDK. Chỉ chạy được Dart thuần (xem §6). |
| Kiểm thử trên xe thật | **CHƯA thực hiện** cho mọi tính năng mới. |
| Đồng bộ giao diện lên đồng hồ xe | **Không khả thi** với firmware 1.14.0 theo bằng chứng hiện có (§3). Không có nút giả. |
| Ảnh xe thật | **Chưa có** ảnh được cấp phép → làm khe tài nguyên + nhãn "ẢNH MINH HỌA" (§5). |

APK phải build ở máy có Flutter: `tool/build_release_apk.sh` hoặc GitHub Actions
(`.github/workflows/build_android.yml`, đã sửa thành 1 APK universal
`TH_DATBIKE-vX.Y.Z.apk`). APK debug-signed (xem build.gradle.kts) — cài đè lên
bản ký khác sẽ báo xung đột chữ ký.

## 1. Phân tích dữ liệu thu thập (session 29/10/2026)

Nguồn: 4 báo cáo kết nối, 7 session JSONL, `app_errors_1.jsonl`.

**Kết nối/xác thực**
- GATT: 8 service, 38 characteristic, MTU 517, telemetry **45 byte** giải mã hợp lệ, poll 700 ms (không notify).
- 2 lần đầu `authRejected` ("chưa có password đã lưu") → lần 3 ghép đôi OK (authResponse 2,4 s) → lần 4 reconnect bằng `appAuth` OK (tổng 2,06 s). Đúng luồng thiết kế; **không đổi** cơ chế ghép đôi/xác thực/mã hóa.

**Lỗi thật tìm thấy (đã sửa)**
- `app_errors`: `MissingPluginException … exportToDownloads` ×11. Nguyên nhân: Dart gọi kênh `vn.datbike/export` nhưng Kotlin chỉ đăng ký `exportToDownloads`/foreground service trên `vn.mybike/export` (kênh `vn.datbike` chỉ có `openMap`). Hệ quả kèm theo: `ForegroundService.start/stop` luôn thất bại im lặng → kết nối nền **chưa bao giờ** được giữ bằng foreground service (ảnh hưởng Auto Lock nền). Sửa: `MainActivity.kt` đăng ký cùng một handler cho cả hai tên kênh.
- `BLE_PROTOCOL_SPEC.md §6` mô tả struct telemetry sai (uint16/41 B). Đã sửa theo decoder + log thực (§ bảng offset).

**Phân loại chức năng**
- *Đang hoạt động (có bằng chứng log):* kết nối/ghép đôi/reconnect, telemetry (odo, tốc độ, dòng pha, xi-nhan, chân chống, V, %, nhiệt BMS/motor/ECU, trạng thái, lỗi, km còn lại), Regen mức 0/1 (ghi `a1d8e7c4` + đọc lại khớp, 3 lần), chặn ghi Grab khi xe chạy (`grab_write_blocked` @0,5 km/h), walk-up unlock (log: kích hoạt @ −44 dBm), đồng bộ giờ RTC.
- *Chưa xác minh:* Regen mức ≥ 2; mở khóa qua BLE **sau** khi đã khóa an toàn (tài liệu nói phải quẹt NFC); trạng thái khóa thực của xe (đọc `eec8fd7f` trả `00 00`, không có read-back).
- *Firmware không hỗ trợ (theo RE2 + GATT):* đổi giao diện/theme/bitmap đồng hồ xe; đèn pha & ga không có trong telemetry.

## 2. Regen nhiều mức

Mô-đun Regen của 2.8.0 đã đúng yêu cầu (chỉ gửi mức đã xác minh; hiển thị hiện tại/yêu cầu/xác nhận; timeout, mất kết nối, xe từ chối; không báo thành công khi chưa đọc lại) → **giữ nguyên**. Dữ liệu chỉ chứng minh **2 mức (0 và 1)**; app không tạo mức ảo. Mức ≥ 2 chỉ qua dò có kiểm soát khi xe đứng yên.

## 3. Đồng hồ xe — Dashboard Sync

Bằng chứng kiểm tra: không có characteristic nào cho theme/bitmap/frame/lệnh hiển thị; đường ghi liên quan màn hình duy nhất là giờ RTC `44e2bde6`; service `5b6d1069` là **OTA firmware** (không dùng; nguy cơ hỏng xe). → **On-Bike Display Sync: không hỗ trợ.**

`lib/core/dashboard/dashboard_sync.dart`: `DashboardSyncEngine` + `DisplaySyncSpec` + `DisplaySyncTransport` (trạng thái, tiến trình, ACK, timeout, thử lại, khôi phục, giới hạn Hz). Mặc định `DisplaySyncSpec.unverified` → engine **không bao giờ** gọi transport, không báo thành công, UI không có nút "Đồng bộ lên xe". Khi có btsnoop/handler thật: cấp spec `verified` + transport, không phải đổi kiến trúc. Kênh này phải đi qua hàng đợi GATT với ưu tiên thấp hơn lệnh điều khiển.

## 4. Kiến trúc mới / file

Mới
- `lib/core/proximity/proximity_engine.dart` — bộ quyết định Smart Unlock/Auto Lock (thuần Dart).
- `lib/core/proximity/proximity_controller.dart` — Riverpod, lưu độ nhạy/hiệu chỉnh, nhật ký.
- `lib/features/proximity/proximity_screen.dart` — UI.
- `lib/core/dashboard/{dashboard_model,dashboard_store,dashboard_sync}.dart`.
- `lib/features/dashboard_studio/{dashboard_view,dashboard_studio_screen,dashboard_live_screen}.dart`.
- `lib/ui/bike_image.dart`, `assets/images/real/README.md`, `tool/make_th_datbike_icon.py`.
- Tests: `test/proximity_engine_test.dart`, `test/dashboard_test.dart`.

Sửa
- `lib/core/ble/ble_controller.dart` (thay bộ đếm RSSI (a)/(b) bằng engine; `_runAutoSecureSequence`/`_runWalkUpUnlockAndPower` trả kết quả; reset engine khi mất kết nối; báo khóa tay).
- `android/.../MainActivity.kt` (hai kênh), `ConnectService.kt` (tên + icon thông báo), `AndroidManifest.xml` (nhãn), `res/*` (icon mọi mật độ, adaptive + monochrome, splash).
- `lib/main.dart` (tên, route), `profile_screen.dart` (2 mục menu), `my_bike_screen.dart` (BikeImage), `connect_diagnostics.dart`, `ble_logger.dart` (build tag), `pubspec.yaml`, `tool/build_release_apk.sh`, `.github/workflows/build_android.yml`, `docs/BLE_PROTOCOL_SPEC.md`.

## 5. Tính năng

**Smart Unlock / Auto Lock** (`Cài đặt → Smart Unlock / Auto Lock`)
- Lọc: trung vị 7 mẫu + loại outlier (>15 dB; lệch liên tiếp 3 mẫu = dịch chuyển thật) + Kalman.
- Hiệu chỉnh 1 m: đứng cách xe ~1 m, lấy trung vị 8 s; từ chối nếu <6 mẫu, nhiễu (σ>6 dB) hoặc quá yếu (<−75 dBm). Ngưỡng mở = RSSI@1m − biên, ngưỡng khóa = RSSI@1m − biên lớn hơn, luôn cách nhau ≥ 4 dB (hysteresis +2 dB). Độ nhạy Thấp/Vừa/Cao; thời gian xác nhận rời xa 3–15 s. Chưa hiệu chỉnh → dùng ngưỡng cũ −55/−83 dBm.
- Chống nhầm/lặp: "armed" (khóa tay xong không tự mở lại tới khi rời xa; chỉ tự khóa nếu từng ở gần), ≥20 s giữa hai lệnh, ≤3 lệnh/10 phút rồi khóa tạm, backoff 60 s sau lỗi, tạm dừng 10 s sau thao tác tay/Lab/khi bận lệnh.
- Điều kiện an toàn để khóa: đã xác thực, telemetry <4 s, tốc độ biết và ≤0,5 km/h, **không ở số lái** (mới), xe đang bật. Mất mẫu/mất kết nối **không** bị coi là rời xe.
- RSSI đọc từ kết nối đã xác thực với xe đã ghép đôi (reconnect theo remoteId) nên thiết bị BLE khác không ảnh hưởng được.
- "Thành công" = xe nhận ghi lệnh; **không** có xác nhận trạng thái khóa (giao thức không có read-back).
- Giữ nguyên: Chống trộm ≥5 m, cảnh báo quên tắt xe, bật xe sẵn sau mở khóa.

**App Dashboard / Dashboard Studio** (`Cài đặt → Dashboard Studio`)
- 6 theme (Sport, Premium, Cyber, Touring, Minimal, Night), 3 bố cục, màu nhấn, 16 widget, nhiều profile (tự lưu, khôi phục profile đang chọn, chịu lỗi dữ liệu hỏng).
- Mỗi giá trị gắn nguồn XE / GPS ĐT / TÍNH TOÁN / KHÔNG CÓ; dữ liệu xe cũ (>4 s) hoặc thiếu → `--`; đèn pha luôn `--` (xe không cung cấp); Regen chỉ hiện khi đã đọc lại.
- Always-On: màn hình phụ toàn màn hình, xoay ngang, giữ sáng. Ghi rõ "đồng hồ phụ trên điện thoại, không phải đồng hồ xe". Không mở luồng BLE mới.
- Đồng hồ cổ điển `/cluster` được giữ nguyên.

**Hình xe / thương hiệu**
- Ảnh hiện có là **ảnh minh họa AI** (biển số giả). Đặt ảnh thật có phép vào `assets/images/real/quantum_s1.jpg`; app tự dùng, nếu chưa có hiển thị ảnh cũ + nhãn "ẢNH MINH HỌA".
- Tên "TH DATBIKE" (manifest, tiêu đề, About, thông báo). Icon mới (`python3 tool/make_th_datbike_icon.py`), mọi mật độ, adaptive + monochrome, splash, icon thông báo.

## 6. Kiểm thử đã thực hiện

| Loại | Kết quả |
|---|---|
| Tự động, Dart thuần (Dart 3.13.7, shim `flutter_test`) | **59/59 đạt**: 32 `proximity_engine_test` + 21 `dashboard_test` + `bike_log_test` hiện có. Chuỗi RSSI/dữ liệu xe trong test là **mô phỏng**. Việc chạy test đã bắt được 1 lỗi thật trong engine (loại outlier làm chậm khi rời xe) — đã sửa. |
| Cú pháp toàn dự án | `dart format` parse sạch 100% file `lib/`, `test/`. |
| `flutter analyze`, `flutter test` (toàn bộ), widget test, build | **Chưa chạy** (không có Flutter SDK). Mã UI/BLE mới được rà thủ công đối chiếu API, nhưng **chưa biên dịch** — có thể còn lỗi kiểu/cảnh báo phải sửa khi build lần đầu. |
| Trên xe thật | **Chưa.** |

## 7. Cần thử trên xe thật (xe đứng yên, trên chân chống)

1. Cài APK, ghép đôi, ngắt/kết nối lại; xác nhận `Cài đặt → Nhật ký` không còn `MissingPluginException`; thông báo foreground xuất hiện; khóa màn hình 10 phút vẫn còn kết nối.
2. Smart Unlock → hiệu chỉnh ở ~1 m (thử 3 lần: σ và giá trị ổn định?). Đo thực tế ngưỡng mở/khóa ở 0,5 / 1 / 1,5 / 2 / 3 m, túi quần/cầm tay, có vật cản, có nhiều thiết bị BLE xung quanh. Ghi lại khoảng cách tại thời điểm kích hoạt.
3. **Quan trọng:** Auto Lock → sau khi khóa an toàn, quay lại gần: xe có kết nối lại bằng BLE để Smart Unlock mở được không, hay buộc quẹt NFC? Kết quả quyết định Smart Unlock sau Auto Lock có dùng được hay không.
4. Auto Lock nền: màn hình tắt, app ở nền, điện thoại sắp hết pin; kiểm tra không khóa khi xe ở số lái/đang chạy.
5. Regen: lặp 0↔1, xác nhận đọc lại; không thử mức ≥2 khi xe đang chạy.
6. Dashboard: từng theme trên Xiaomi 15T Pro dọc/ngang ngoài nắng và ban đêm; kiểm tra thiếu quyền GPS/Bluetooth.

## 8. Giới hạn còn lại

- RSSI không phải khoảng cách; sai số vài dB là bình thường. Không bảo đảm chính xác 1 m.
- Không có read-back trạng thái khóa; app không xác nhận được xe đã khóa/mở thật.
- Đồng bộ giao diện lên đồng hồ xe: không thể (firmware, theo bằng chứng hiện có).
- Đèn pha/ga không hiển thị (telemetry không có).
- Regen chỉ 2 mức đã xác minh.
- Tối ưu pin/Android Doze cho Auto Lock nền trên Xiaomi (HyperOS) cần người dùng tắt giới hạn pin cho app; chưa kiểm chứng.
- APK ký bằng khóa debug.
