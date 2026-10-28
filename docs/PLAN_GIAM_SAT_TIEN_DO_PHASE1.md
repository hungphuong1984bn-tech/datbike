# 📋 KẾ HOẠCH GIÁM SÁT TIẾN ĐỘ (PHASE 1) — `datbike_app`

> **Cập nhật lần cuối:** 2026-10-26  
> **Phạm vi:** Chỉ xử lý ứng dụng Flutter `datbike_app/` & chuẩn hóa theo kết quả dịch ngược độc lập Ghidra RE2 (`mainPcb-1.14.0.bin`).  
> **Trạng thái `firmware_reconstructed/`:** ⏸️ Tạm ngưng (chưa triển khai ở giai đoạn này).

---

## 📊 TỔNG QUAN TIẾN ĐỘ

| Nhóm công việc | Tiến độ | Trạng thái |
|---|---|---|
| **1. Dọn dẹp phân tích sai & Khóa an toàn cổng BLE** | `5 / 5` | ✅ **HOÀN THÀNH** |
| **2. Tối ưu Handshake (`authenticateSession`) & Bảo vệ Credential** | `3 / 3` | ✅ **HOÀN THÀNH** |
| **3. Xử lý `Stale-Tail Buffer` & Giải mã cổng đặc thù** | `3 / 3` | ✅ **HOÀN THÀNH** |
| **4. Hàng đợi lệnh tuần tự (`BleCommandQueue`) chống lỗi GATT 133** | `2 / 2` | ✅ **HOÀN THÀNH** |
| **5. Tích hợp Chế độ sạc dòng xe Era (`8a2b0d10`)** | `3 / 3` | ✅ **HOÀN THÀNH** |
| **6. Dọn dẹp các nút UI giả lập (Mock UI & OTA)** | `3 / 3` | ✅ **HOÀN THÀNH** |
| **7. Tinh chỉnh sau Review đợt 1 (`ble_controller.dart`)** | `4 / 4` | ✅ **HOÀN THÀNH** |
| **TỔNG CỘNG TIẾN ĐỘ PHASE 1** | **`23 / 23`** | 🚀 **100% HOÀN THÀNH** |

---

## ✅ PHẦN 1: ĐÃ HOÀN THÀNH (ĐÃ SỬA TRONG CODE)

- [x] **[1.1] Chuẩn hóa bảng định danh 28 cổng GATT trong [`gatt.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/gatt.dart)**
  - Đính chính vai trò thật của `b0ca953d`, `44e2bde6`, `87efab0d`, `4cb05df8`, `91e84eb0`, `35a9b4f6`, `73d50009`, `2c73e84e`, `460a5bc5`.
- [x] **[1.2] Khóa an toàn cổng `b0ca953d` (`onWriteVescProgamming` @ `0x4015565c`)**
  - Đã chặn hàm [`setBikeLights`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L618-L625) trong `ble_controller.dart` và gỡ nút bấm "Đèn xe" trên [`vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart#L1041-L1060) vì handler thật là phép đảo bit XOR (`cfg+0x62 ^= 1`) làm ngắt `vescPollTask` (`IM = 0`) và `canCheckConnectionTask`.
- [x] **[1.3] Tắt tự động quét 28 cổng (`_scheduleSniffOnce()`) khi kết nối thường**
  - Đã gỡ lời gọi `_scheduleSniffOnce()` tại dòng [`1247`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L1247) và [`1903`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L1903) trong `ble_controller.dart` để tránh nghẽn GATT và không làm xoay token của `87efab0d`.
- [x] **[1.4] Sửa lỗi lệch đồng hồ Taplo về `00:00` khi thử Password trong [`tryPassword`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2623-L2643)**
  - Đã đổi payload gửi vào `44e2bde6` (`Gatt.timeSyncChar`) ở `counter = 0` từ `pw.codeUnits` sang `secondsOfDay.codeUnits` (tổng số giây trong ngày theo giờ địa phương).
- [x] **[1.5] Đồng bộ toàn bộ mô tả & `writeMode` trong [`lab_catalog.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/firmware_lab/lab_catalog.dart)**
  - Đã cập nhật `b0ca953d` (`LabRisk.danger` XOR toggle), `87efab0d` (`LabWriteMode.plain`), `2c73e84e` (`LabWriteMode.none`, `4 × uint32 LE`), `35a9b4f6` (`3 × float32 LE`), `460a5bc5` (`LabWriteMode.none`), `44e2bde6` (Time Sync).

---

## 🛠️ PHẦN 2: CHECKLIST CÁC HẠNG MỤC CẦN TỰ CODE TIẾP

### Nhóm 2: Tối ưu Handshake (`authenticateSession`) & Bảo vệ Credential
> **File cần sửa:** [`lib/core/ble/ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2485-L2735)

- [x] **[2.1] Đưa bước đọc `5e9a2c71` lên trước và thêm nhánh Fast-Path khi `status1 == 0x01`**
  - **Vấn đề:** Hiện tại dòng `2489–2525` luôn ghi 64B SHA256 hex vào `c8eaf27b`, và dòng `2546–2583` luôn ghi 16B HMAC vào `5e9a2c71` kể cả khi xe đã nhớ phiên (`status1 == 0x01`).
  - **Cách code:**
    ```dart
    // 1. Đọc 5e9a2c71 trước tiên để kiểm tra trạng thái phiên trên xe
    final nonce1 = await authChar
        .read()
        .timeout(const Duration(milliseconds: 800), onTimeout: () => Uint8List(0));
    if (nonce1.length != 16) return false;
    var nonce15 = Uint8List.fromList(nonce1.sublist(0, 15));
    final status1 = nonce1[15];

    Uint8List? acceptedNonce;
    if (status1 == Gatt.authStatusOk && !forceRegister) {
      // FAST-PATH: Xe đã chấp nhận xác thực từ trước -> giữ nguyên nonce1, KHÔNG ghi lại 5e9a2c71
      acceptedNonce = Uint8List.fromList(nonce1);
      BleLogger.instance.event('auto_handshake_fast_path', {'hex': BleLogger.hex(nonce1)});
    } else {
      // SLOW-PATH (status1 == 0x00):
      // Thực hiện Bước 1.5 (giải challenge SHA256 trên c8eaf27b)
      // Sau đó chạy vòng lặp ghi 16B HMAC vào 5e9a2c71 và đọc lại post status
    }
    ```

- [x] **[2.2] Chặn tự động ghi đè `self-register` khi đã có mật khẩu lưu (`hasStoredPassword`)**
  - **Vấn đề:** Tại dòng [`2698`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2698), nếu `tryPassword` bị timeout 1 lần do nhiễu sóng BLE, App tự chạy `self-register` ghi đè mật khẩu mới lên `c8eaf27b`, làm hỏng mật khẩu đã lưu nếu xe đang khóa.
  - **Cách code:** Sửa điều kiện tại dòng `2698`:
    ```dart
    // Chỉ cho phép self-register tự động khi chưa từng có password lưu (!hasStoredPassword)
    // hoặc khi người dùng bấm nút Force Register (forceRegister == true)
    if (!live && appAuthChar != null && (!hasStoredPassword || forceRegister)) {
      ...
    }
    ```

---

### Nhóm 3: Cắt bỏ rác `Stale-Tail Buffer` & Giải mã cổng đặc thù
> **File cần sửa:**
> - [`lib/core/session/bike_session_crypto.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/session/bike_session_crypto.dart#L86-L110)
> - [`lib/core/ble/ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L840-L885)

- [x] **[3.1] Thêm tham số `expectedLength` vào `BikeSessionCrypto.decryptProtectedRead`**
  - **Vấn đề:** Firmware `MainPCB` dùng lại buffer `AttValue` mà không xóa các byte đuôi của gói dài trước đó (`00_SCOPE.md` mục Stale-tail).
  - **Cách code trong `bike_session_crypto.dart`:**
    ```dart
    static Uint8List? decryptProtectedRead({
      required Uint8List sessionKey,
      required String characteristicUuid,
      required List<int> packet,
      int? expectedLength,
    }) {
      if (packet.length <= 4) return null;
      ...
      if (expectedLength != null && out.length > expectedLength) {
        return Uint8List.sublistView(out, 0, expectedLength);
      }
      return out;
    }
    ```
  - **Bảng `expectedLength` chuẩn theo từng UUID:**
    | UUID | Tên cổng | `expectedLength` (bytes) |
    |---|---|---|
    | `6d2eb205` | `dashboardCharacteristic` | `41` |
    | `018e6a6f` | `bikeLogCharacteristic` | `108` |
    | `84c7be0b` | `batteryLogCharacteristic` | `207` |
    | `2c73e84e` | `logBufferStatsChar` | `16` (`4 × uint32 LE`) |
    | `35a9b4f6` | `vescSnapshotChar` | `12` (`3 × float32 LE`) |
    | `4cb05df8` | `legacyAppAuthChar` | `12` |
    | `5d681587` | `distanceChar` | `2` (`uint16 LE`) |
    | `c75ebe03` | `addCardChar` | `2` |
    | `0a19a49a`, `3b56ac38`, `a1d8e7c4`, `69c79762`, `b0ca953d`, `8a2b0d10`, `91e84eb0` | Các cổng flag/profile 1 byte | `1` (`uint8`) |

- [x] **[3.2] Giải mã hiển thị đủ 3 trường float cho `35a9b4f6` (`vescSnapshotChar`) và 4 trường uint32 cho `2c73e84e` (`logBufferStatsChar`)**
  - **Cách code:**
    ```dart
    // Cổng 35a9b4f6 (12 byte = 3 × float32 LE)
    if (plain.length >= 12) {
      final bd = ByteData.sublistView(plain, 0, 12);
      final motorCurrent = bd.getFloat32(0, Endian.little); // A (0.0 khi xe đỗ)
      final vescVoltage  = bd.getFloat32(4, Endian.little); // V (~76.6V)
      final dutyCycle    = bd.getFloat32(8, Endian.little); // 0.0..1.0 (~0.854)
    }

    // Cổng 2c73e84e (16 byte = 4 × uint32 LE)
    if (plain.length >= 16) {
      final bd = ByteData.sublistView(plain, 0, 16);
      final s0 = bd.getUint32(0, Endian.little);
      final s1 = bd.getUint32(4, Endian.little);
      final s2 = bd.getUint32(8, Endian.little);
      final s3 = bd.getUint32(12, Endian.little);
    }
    ```

- [x] **[3.3] Không giải mã `decryptProtectedRead` khi đọc cổng `87efab0d` (`beepScanChar`) trong Lab**
  - **Vấn đề:** Cổng `87efab0d` được đăng ký qua `FUN_4015030c` (**PLAIN Read**), trả trực tiếp chuỗi token xoay ngẫu nhiên, không có 4 byte counter ở đầu.
  - **Cách code:** Trong hàm xử lý nút Đọc của Firmware Lab, nếu `uuid == Gatt.beepScanChar`, hiển thị trực tiếp `utf8.decode(rawBytes, allowMalformed: true)` thay vì gọi `decryptProtectedRead`.

---

### Nhóm 4: Hàng đợi lệnh tuần tự (`BleCommandQueue`) chống đụng độ GATT
> **File cần sửa:** [`lib/core/ble/ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart)

- [x] **[4.1] Thêm cơ chế chờ `_waitWhileCommandBusy` cho `turnOnBike` / `turnOffBike`** *(Đã hoàn thành)*
- [x] **[4.2] Bọc toàn bộ thao tác `read()` / `write()` vào hàng đợi tuần tự `_enqueueGatt`**
  - **Vấn đề:** Tránh việc `_pollDashboard` (700ms) và `fetchBatteryDetails` đang gọi `read()` thì người dùng bấm nút gọi `write()` cùng lúc gây lỗi `GATT_INTERNAL_ERROR (129)` hoặc `GATT_ERROR (133)`.
  - **Cách code:**
    ```dart
    Future<void>? _gattChain;

    Future<T> _enqueueGatt<T>(Future<T> Function() action) {
      final prev = _gattChain ?? Future.value();
      final completer = Completer<T>();
      _gattChain = prev.catchError((_) {}).then((_) async {
        try {
          completer.complete(await action());
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      return completer.future;
    }
    ```
  - Sử dụng `_enqueueGatt(() => c.read())` và `_enqueueGatt(() => c.write(...))` tại `_pollDashboard`, `fetchBatteryDetails`, `_writeSetting`, `_sendPowerCommand`.

---

### Nhóm 5: Tích hợp hoàn chỉnh Chế độ sạc dòng xe Era (`8a2b0d10` — Charging Service `8a2b0d00`)
> **Đặc tả kỹ thuật từ Firmware (`mainPcb-1.14.0.bin` — handler `@0x40154240`):**
> - **Service UUID:** `8a2b0d00-9c52-4f5a-9d3e-1f7a0c4b6e21` (`Gatt.chargingService`)
> - **Characteristic UUID:** `8a2b0d10-9c52-4f5a-9d3e-1f7a0c4b6e21` (`Gatt.chargingProfileChar`)
> - **Khác biệt quan trọng nhất so với mọi cổng Setting khác:**
>   - Các cổng `ECE`, `SpeedLimit`, `Grab`, `Idling` nhận **ASCII `'0'` (`0x30`) / `'1'` (`0x31`)**.
>   - Riêng cổng Sạc Era (`8a2b0d10`) nhận **1 BYTE SỐ NGUYÊN THÔ (RAW `uint8`)**:
>     - `0x00` (`0`) = **Standard** (Sạc tiêu chuẩn, bảo vệ tuổi thọ pin)
>     - `0x01` (`1`) = **Fast** (Sạc nhanh)
>     - `0x02` (`2`) = **Boost** (Sạc siêu tốc — trong hàm `@0x40154240` có nhánh kiểm tra `bnei == 2` riêng)
>   - Firmware dùng lệnh `l8ui payload[0]` → ghi vào `obj+2` → lưu NVS namespace `'charging'`, key `'defaultProfile'`.
>   - **Protected Read:** Trả về `1 byte raw uint8` (`0x00`, `0x01`, hoặc `0x02`). Lưu ý cắt `expectedLength: 1` để không dính `stale-tail` (như log LAB ngày 23/10 từng thấy `"00 00 31 00..."`).

- [x] **[5.1] Hàm ghi `setFwChargingProfile(int profile)` trong [`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L706-L711)** *(Đã có sẵn & đúng chuẩn RAW byte `[profile.clamp(0, 2)]`)*
- [x] **[5.2] Bổ sung đọc đồng bộ trạng thái `chargingProfile` từ xe trong `syncFwSettingsFromBike()` ([`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L765-L815))**
  - **Vấn đề:** Khi kết nối xe, cần đọc cổng `8a2b0d10` để cập nhật `state.chargingProfile` (`0`, `1`, `2`) đúng với giá trị đang lưu trong NVS `'charging'/'defaultProfile'` của xe.
  - **Cách code trong `ble_controller.dart`:**
    ```dart
    // Đọc profile sạc (8a2b0d10) — lấy đúng byte đầu tiên (raw u8: 0, 1, 2)
    final chgDec = await readFwSettingRaw(Gatt.chargingProfileChar, 'charging_profile');
    if (chgDec.isNotEmpty) {
      final profile = chgDec[0];
      if (profile >= 0 && profile <= 2) {
        state = state.copyWith(chargingProfile: profile);
      }
    }
    ```
- [x] **[5.3] Mở lại bộ 3 nút chọn Chế độ sạc Era (`Standard / Fast / Boost`) trên [`vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart#L1177-L1204)**
  - **Vấn đề:** Tại dòng `1177–1204` của `vehicle_settings_screen.dart`, mục Profile sạc hiện chỉ là một khung text tĩnh báo `"ĐÃ TẮT"`, chưa có 3 nút bấm gọi `setFwChargingProfile(0/1/2)` để điều khiển cho xe dòng Era (hoặc test NVS trên Quantum).
  - **Cách code thay thế khối `Container` tại dòng `1177–1204` trong `vehicle_settings_screen.dart`:**
    ```dart
    // Chế độ sạc dòng xe Era (8a2b0d10 — RAW byte 0x00 / 0x01 / 0x02)
    Text(
      'CHẾ ĐỘ SẠC DÒNG XE ERA (STANDARD / FAST / BOOST)',
      style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 4),
    Text(
      'Ghi 1 byte RAW (0x00=Standard, 0x01=Fast, 0x02=Boost) vào cổng 0x8A2B0D10 (NVS charging/defaultProfile). Hoạt động trên dòng Dat Bike Era (trên Quantum S1 chỉ lưu NVS).',
      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textDim),
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        _buildSegmentOption(
          label: 'Standard',
          desc: '0x00 · Bền pin',
          isSelected: ble.chargingProfile == 0,
          onTap: () async {
            ref.read(bleProvider.notifier).setChargingProfile(0);
            _showResult(await ref.read(bleProvider.notifier).setFwChargingProfile(0));
          },
        ),
        const SizedBox(width: 8),
        _buildSegmentOption(
          label: 'Fast',
          desc: '0x01 · Sạc nhanh',
          isSelected: ble.chargingProfile == 1,
          onTap: () async {
            ref.read(bleProvider.notifier).setChargingProfile(1);
            _showResult(await ref.read(bleProvider.notifier).setFwChargingProfile(1));
          },
        ),
        const SizedBox(width: 8),
        _buildSegmentOption(
          label: 'Boost',
          desc: '0x02 · Siêu tốc',
          isSelected: ble.chargingProfile == 2,
          onTap: () async {
            ref.read(bleProvider.notifier).setChargingProfile(2);
            _showResult(await ref.read(bleProvider.notifier).setFwChargingProfile(2));
          },
        ),
      ],
    ),
    ```

---

### Nhóm 6: Dọn dẹp các tính năng giả lập (Mock UI & OTA)
> **File cần sửa:**
> - [`lib/features/home/my_bike_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/home/my_bike_screen.dart#L157-L159)
> - [`lib/features/settings/vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart#L430-L564)
> - [`lib/core/ota/ota_service.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ota/ota_service.dart#L72-L86)

- [x] **[6.1] Thay thế nút "Mở cốp" giả lập (`_quickTrunkRelease`) trên [`my_bike_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/home/my_bike_screen.dart#L157-L159)**
  - **Vấn đề:** Hiện chỉ bật Snackbar giả lập, không có lệnh BLE.
  - **Cách code:** Thay bằng nút **"Đồng bộ giờ"** gọi `ref.read(bleProvider.notifier).syncTimeWithBike()`.
- [x] **[6.2] Chuyển thẻ `_buildPerformanceCard` (RECUP & Độ nhạy ga) xuống mục Nâng cao trong [`vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart#L430-L564)**
  - **Vấn đề:** Hai thanh chọn này chỉ lưu `SharedPreferences` trên điện thoại chứ firmware `v1.14.0` không có cổng BLE tương ứng.
- [x] **[6.3] Xóa dữ liệu trả về giả (`v1.14.2`) khi lỗi mạng trong [`ota_service.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ota/ota_service.dart#L72-L86)**
  - **Cách code:** Trong khối `catch (e)` của `fetchLatest()`, trả về `return null;` thay vì trả về `FirmwareRelease(version: '1.14.2', ...)` giả.

---

### Nhóm 7: Tinh chỉnh sau Review đợt 1 (4 mục nhỏ còn sót trong [`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart))

- [x] **[7.1] Xóa khối `serialChar.write(frame2)` gửi nhầm `livePw.codeUnits` tại dòng [`2882–2892`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2882-L2892)**
  - **Vấn đề:** Trong `tryPassword` (dòng `2716–2729`), bạn đã sửa thành gửi `secondsOfDay.codeUnits` vào `44e2bde6` (`serialChar`). Nhưng ở dòng `2882–2892` (sau khi `if (live && liveKey != null)`), vẫn còn sót khối code cũ gửi `data: livePw.codeUnits` vào `Gatt.bikeSerial` (`44e2bde6`). Khi `livePw` là mật khẩu 12 ký tự chữ+số, lệnh này làm `atoi()` trên xe đặt đồng hồ Taplo về `00:00`, đồng thời đụng độ GATT với lệnh `unawaited(syncTimeWithBike())` ngay ở dòng `2904`.
  - **Cách code (tại dòng `2874–2905` của `ble_controller.dart`):**
    Xóa hẳn khối `if (serialChar != null) { ... }` (dòng `2882–2892`) và `unawaited(syncTimeWithBike());` (vì `tryPassword` đã vừa đồng bộ `secondsOfDay` xong), chỉ giữ lại:
    ```dart
      // Token lên 87efab0d nếu session sống (đồng bộ giờ 44e2bde6 đã thực hiện trong tryPassword)
      if (live && liveKey != null) {
        final sessionUuidChar = find(Gatt.sessionUuid);
        if (sessionUuidChar != null) {
          await sessionUuidChar
              .write(token.codeUnits, withoutResponse: false)
              .timeout(const Duration(milliseconds: 800));
          BleLogger.instance.event('auto_handshake_uuid_sent', {'token': token});
        }
        _sessionKey = liveKey;
        _activePassword = livePw;
        _startKeepalive();
        state = state.copyWith(
          isAuthorized: true,
          sessionKey: liveKey,
          lastTimeSynced: DateTime.now(),
          message: 'SESSION HỢP LỆ — password '
              '"$livePw" sẵn sàng điều khiển',
        );

        BleLogger.instance.event('auto_handshake_success');
        return true;
      }
    ```

- [x] **[7.2] Bọc `_enqueueGatt` cho lệnh `timeChar.write` trong hàm [`syncTimeWithBike`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2266-L2274)**
  - **Vấn đề:** Tại dòng `2266` và `2274`, `timeChar.write(...)` gọi trực tiếp mà chưa đi qua hàng đợi `_enqueueGatt`, có thể đụng độ với chu kỳ 700ms của `_pollDashboard()`.
  - **Cách code (tại dòng `2259–2280` của `ble_controller.dart`):**
    ```dart
      if (_sessionKey != null) {
        final frame = BikeSessionCrypto.buildProtectedWrite(
          sessionKey: _sessionKey!,
          counter: _writeCounter++,
          characteristicUuid: Gatt.currentTimeChar,
          data: payload,
        );
        await _enqueueGatt(() => timeChar.write(frame, withoutResponse: false));
        ...
      } else {
        await _enqueueGatt(() => timeChar.write(payload, withoutResponse: false));
        ...
      }
    ```

- [x] **[7.3] Bọc `_enqueueGatt` cho lệnh `sw.write` trong hàm [`_sendFindBikeHonk`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L2386)**
  - **Vấn đề:** Khi bật Tìm xe, `Timer.periodic` (mỗi 1000–1500ms) gọi `_sendFindBikeHonk()` ghi vào `350d9a82`. Nếu không bọc `_enqueueGatt`, lệnh ghi còi sẽ đụng với lệnh đọc `_pollDashboard()` (700ms).
  - **Cách code (tại dòng `2386` của `ble_controller.dart`):**
    ```dart
    await _enqueueGatt(() => sw.write('1'.codeUnits, withoutResponse: false));
    ```

- [x] **[7.4] Sửa điều kiện nhận diện trạng thái bật của `distanceChar` (`5d681587`) trong [`refreshFwSettings`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L784)**
  - **Vấn đề:** Cổng `5d681587` lưu `uint16 LE` trong NVS `'distance'` với giá trị mặc định là `8` (khi bật là `1` hoặc `8`, khi tắt là `0`). Dòng `784` hiện kiểm tra `dist[0] == 1` sẽ báo tắt nhầm nếu xe đang ở mức default `8`.
  - **Cách code (tại dòng `784` của `ble_controller.dart`):**
    ```dart
    distanceMode: dist.isNotEmpty && dist[0] > 0 ? 1 : 0,
    ```

---

## 🗂️ BẢNG TRA CỨU NHANH 28 CỔNG GATT (CHUẨN RE2)

| UUID (8 ký tự đầu) | Service | Chế độ Đọc (Read) | Chế độ Ghi (Write) | Ý nghĩa thật trong `mainPcb-1.14.0.bin` |
|---|---|---|---|---|
| `5e9a2c71` | Auth (`10cb0217`) | **Plain Read** (`16B`) | **Plain Write** (`16B`) | `15B Nonce + 1B Status` / Ghi `HMAC-SHA256(pairingToken, "DBauth" \|\| nonce15)[0:16]` |
| `c8eaf27b` | Auth (`10cb0217`) | **Plain Read** (`4B`) | **Plain Write** (`12B`/`64B`) | Challenge 4B / Ghi `app-token` 12 ký tự hoặc 64B SHA256 hex |
| `4cb05df8` | Auth (`10cb0217`) | **Protected Read** (`12B`) | *Không dùng* | `LEGACY_APP_AUTH` (12B dữ liệu theo phiên) |
| `91e84eb0` | Auth (`10cb0217`) | **Protected Read** (`1B`) | *Không dùng* | Cờ tĩnh `0x01` |
| `6d2eb205` | Dashboard (`cf6900a7`) | **Protected Read** (`41B`) | *Read-Only* | Telemetry chính 41B (`buildBikeLogPacket` @ `0x400e0cb8`) |
| `84c7be0b` | Dashboard (`cf6900a7`) | **Protected Read** (`207B`) | *Read-Only* | Battery Log Protobuf (13 cell, pack V/I, temp) |
| `018e6a6f` | Dashboard (`cf6900a7`) | **Protected Read** (`108B`) | *Read-Only* | Bike Identity Log Protobuf (Tên, Model, Serial) |
| `0a19a49a` | MasterCfg (`f7e2c8a1`) | **Protected Read** (`1B u8`) | **Protected Write** (`'1'`/`'0'`) | Giới hạn tốc độ (`onWriteSpeedLimit`, chỉ áp dụng khi `ECE == 1`) |
| `3b56ac38` | MasterCfg (`f7e2c8a1`) | **Protected Read** (`1B u8`) | **Protected Write** (`'1'`/`'0'`) | Chế độ ECE (`onWriteEceMode`, mở cổng giới hạn tốc độ & khóa chuyển mode) |
| `a1d8e7c4` | MasterCfg (`f7e2c8a1`) | **Protected Read** (`1B u8`) | **Protected Write** (`'1'`/`'0'`) | Chế độ Grab (`onWriteGrabMode`) |
| `7f13fe5c` | Info (`d4905f67`) | *Write-Only (Echo)* | **Protected Write** (`'1'`/`'0'`) | Công tắc Bật/Tắt nguồn động (`'1'` = Bật, `'0'` = Tắt) |
| `350d9a82` | Info (`d4905f67`) | *Write-Only* | **Plain Write** (`'1'`/`'0'`) | Phối hợp bật/tắt nguồn; khi xe tắt máy ghi `'1'` = **Còi tìm xe** |
| `eec8fd7f` | Info (`d4905f67`) | **Protected Read** (`2B`) | **Protected Write** (`'1'`/`'0'`) | **Khóa an toàn (ARM)**: `'1'` = Khóa chống trộm + bắt quẹt NFC, `'0'` = Mở |
| `b0ca953d` | Info (`d4905f67`) | **Protected Read** (`1B u8`) | **Protected Write** (*XOR Toggle*) | ⚠️ **Cờ nạp VESC (`cfg+0x62 ^= 1`)**: Ngắt `vescPollTask` (`IM=0`) & tắt đèn |
| `44e2bde6` | Info (`d4905f67`) | *Tĩnh `"28825"`* | **Protected Write** (*ASCII*) | **Đồng bộ giờ RTC Taplo** (Tổng số giây trong ngày `0..86399` giờ local) |
| `87efab0d` | Info (`d4905f67`) | **Plain Read** (*Token xoay*) | **Plain Write** (*NVS `'beep'`*) | Đọc trả token xoay mỗi lần đọc; Ghi lưu NVS `'beep'` (stub, không kêu còi) |
| `88c30d2c` | Info (`d4905f67`) | **Protected Read** (*ASCII*) | **Protected Write** (*ASCII ≤20B*) | **Tên xe thật** (Lưu NVS `'ble-info'/'name'`, giữ nguyên sau khi tắt xe) |
| `460a5bc5` | Info (`d4905f67`) | **Protected Read** | *Read-Only (Write rỗng)* | Cổng tên cũ (Không có Write handler trong `BLEInfo`) |
| `5d681587` | Info (`d4905f67`) | **Protected Read** (`2B u16`) | **Protected Write** (`'1'`/`'0'`) | Khoảng cách BLE tự động (`onWriteDistance`, NVS `'distance'`) |
| `69c79762` | Info (`d4905f67`) | **Protected Read** (`1B u8`) | **Protected Write** (`'1'`/`'0'`) | Tự tắt xe khi đỗ (`idlingTurnOff`) |
| `1f4108ad` | Info (`d4905f67`) | *Write-Only* | **Protected Write** (`'1'`) | Tắt hẳn BMS sau 1000ms (`onWriteTurnOffBms`, chỉ chạy khi xe bật & đỗ) |
| `a23df519` | Info (`d4905f67`) | *Write-Only* | **Protected Write** (*≠ rỗng*) | Factory Reset cài đặt BLE |
| `d1da175e` | Info (`d4905f67`) | **Plain Read** (`"1.14.0"`) | *Read-Only* | Phiên bản Firmware (Yêu cầu kết nối đã Bond) |
| `041d5a06` | Info (`d4905f67`) | **Protected Read** (`17B`) | **Protected Write** | Số Serial khung xe (`"RL9C4NGSSSCC00187"`) |
| `4aae98e9` | Info (`d4905f67`) | **Protected Read** (`"QT_S1"`) | *Read-Only* | Mã Model xe |
| `73d50009` | Info (`d4905f67`) | **Protected Read** (*ASCII*) | *Read-Only* | Chuỗi hash Manifest 3 board (`"1adadba-#-8c02b07-896e9a7"`) |
| `35a9b4f6` | Info (`d4905f67`) | **Protected Read** (`12B`) | *Read-Only* | Snapshot VESC `3 × float32 LE`: `[motorCurrent, vescVoltage, dutyCycle]` |
| `2c73e84e` | Info (`d4905f67`) | **Protected Read** (`16B`) | *Read-Only (Write rỗng)* | Thống kê Log Buffer nội bộ `4 × uint32 LE` (`FUN_400edc10/c3c/c64/cf8`) |
| `8a2b0d10` | Charging (`8a2b0d00`) | **Protected Read** (`1B u8`) | **Protected Write** (**1B RAW `0x00`/`0x01`/`0x02`**) | **Chế độ sạc dòng xe Era** (`@0x40154240` → NVS `'charging'/'defaultProfile'`): `0`=Standard, `1`=Fast, `2`=Boost |
| `c75ebe03` | NFC / Info | **Protected Read** (`2B`) | **Protected Write** (`'1'`/`'0'`) | Đăng ký thẻ NFC mới (`RfidCardManager`: mở cửa sổ quẹt thẻ ~10s) |
| `68311857`<br>`07765f94`<br>`46a7b351`<br>`4244dedb`<br>`e0b2b4b4` | OTA (`5b6d1069`) | `e0b2b4b4`: Read | **WriteNoResp** (Truyền gói bin) | Kênh truyền dữ liệu nạp Firmware OTA (`FAST_OTA_SERVICE`), **không phải** còi xe |

