# 📋 KẾ HOẠCH GIÁM SÁT TIẾN ĐỘ (PHASE 2) — `datbike_app` & RE2 CHUYÊN SÂU

> **Ngày lập:** 2026-10-26  
> **Tiền đề:** Phase 1 (`23 / 23` hạng mục chuẩn hóa giao thức, khóa an toàn `b0ca953d`, sửa lệch giờ `44e2bde6`, cắt `Stale-Tail`, hàng đợi `_enqueueGatt`) đã hoàn thành 100% ([xem Phase 1](file:///d:/CuaMan/dat-bike/datbike_app/docs/PLAN_GIAM_SAT_TIEN_DO_PHASE1.md)).  
> **Mục tiêu Phase 2:**
> 1. Kiểm thử thực địa (Field Test) bản Build Phase 1 và xác nhận qua log thực tế.
> 2. Đưa các cổng chẩn đoán đã giải mã (`35a9b4f6` VESC Snapshot, `73d50009` Board Manifest, `018e6a6f` Bike Identity) từ Lab lên giao diện chính của `datbike_app`.
> 3. Giải mã nốt các byte/trường còn ẩn trong gói 41B Dashboard (`byte 12`, `byte 13..14`, `byte 32`) và 207B Battery Protobuf.
> 4. Dịch ngược giao thức nạp OTA (`5b6d1069`) từ `mainPcb-1.14.0.bin`.

---

## 📊 TỔNG QUAN TIẾN ĐỘ PHASE 2

| Nhóm công việc | Tiến độ | Trạng thái |
|---|---|---|
| **1. Kiểm thử thực địa (Field Test) bản Build Phase 1** | `0 / 5` | 🧪 **ĐANG TEST TRÊN XE** |
| **2. Đưa dữ liệu Chẩn đoán VESC & Định danh Board lên UI chính** | `0 / 4` | ⏳ **CHỜ CODE** |
| **3. Giải mã nốt 4 Byte ẩn trong gói 41B Dashboard (`6d2eb205`)** | `0 / 3` | ⏳ **CHỜ NGHIÊN CỨU & CODE** |
| **4. Mở rộng giải mã Protobuf Pin 207B (`84c7be0b`) & Xe 108B (`018e6a6f`)** | `0 / 3` | ⏳ **CHỜ CODE** |
| **5. Dịch ngược & Thiết kế luồng OTA BLE (`5b6d1069`)** | `0 / 2` | ⏳ **CHỜ NGHIÊN CỨU** |
| **TỔNG CỘNG TIẾN ĐỘ PHASE 2** | **`0 / 17`** | 🚀 **BẮT ĐẦU PHASE 2** |

---

## 🧪 NHÓM 1: KIỂM THỬ THỰC ĐỊA (FIELD TEST) BẢN BUILD PHASE 1

> **Mục đích:** Xác nhận thực tế trên xe các bản vá của Phase 1 hoạt động mượt mà và đối chiếu file log `.jsonl` xuất ra từ ứng dụng.

- [ ] **[1.1] Test Handshake Fast-Path & Reconnect không cần thẻ NFC**
  - **Cách test:** Kết nối xe lần 1 → Tắt Bluetooth điện thoại (hoặc đóng app) → Bật lại cho app tự kết nối lại.
  - **Kỳ vọng trong log:** Xuất hiện sự kiện `auto_handshake_fast_path` (khi `status1 == 0x01`), kết nối thành công ngay trong ~1–2 giây mà không ghi đè `c8eaf27b` hay `5e9a2c71`.
- [ ] **[1.2] Test Đồng bộ giờ tự động (`44e2bde6`) trong Handshake**
  - **Cách test:** Quan sát đồng hồ trên màn hình LCD Taplo của xe ngay khi App báo `"SESSION HỢP LỆ"`.
  - **Kỳ vọng:** Đồng hồ Taplo giữ đúng giờ hiện tại của điện thoại (nhờ sự kiện `auto_handshake_time_sync_probe` gửi `secondsOfDay`), **không còn bị nhảy về `00:00` hay `16:16`**.
- [ ] **[1.3] Test Hàng đợi tuần tự `_enqueueGatt` dưới tải cao**
  - **Cách test:** Trong lúc xe đang kết nối (App đang poll Dashboard 700ms + đọc Pin mỗi 2.1s), bấm liên tục các nút: Bật/Tắt giới hạn 60 km/h (`ECE + SpeedLimit`), Chế độ Grab, Tự tắt khi đỗ, Đồng bộ giờ, Bật/Tắt nguồn xe.
  - **Kỳ vọng:** Không xảy ra lỗi `GATT_INTERNAL_ERROR (129)` hay `GATT_ERROR (133)`, mọi lệnh đều trả về xác nhận `oldHex → newHex`.
- [ ] **[1.4] Test chuỗi Tự động khóa khi rời xa (`_runAutoSecureSequence`)**
  - **Cách test:** Bật tùy chọn "Tự khóa khi rời xa" → Để xe đang BẬT nguồn (đứng yên `0 km/h`) → Cầm điện thoại đi ra xa > 5–7m.
  - **Kỳ vọng:** Xe tự tắt nguồn (`turnOffBike` chờ `_waitWhileCommandBusy` không bị văng Exception) → Đợi 2 giây → Tự bật Khóa An Toàn (`eec8fd7f` = `'1'`).
- [ ] **[1.5] Test đọc `35a9b4f6` (VESC 3×float) và `2c73e84e` (Log Buffer 4×u32) trong Firmware Lab**
  - **Cách test:** Mở màn hình Firmware Lab → Bấm ĐỌC trên mục `vesc_char` (`35a9b4f6`) và `unknown_2c73e84e` (`2c73e84e`).
  - **Kỳ vọng:** Dòng `parsed:` hiển thị rõ `VESC: I=0.00A, V=76.xxV, duty=0.xxx` và `LogBuffer: s0=..., s1=..., s2=..., s3=...` (đã cắt sạch `stale-tail` ở đúng 12B và 16B).

---

## 🛠️ NHÓM 2: ĐƯA DỮ LIỆU CHẨN ĐOÁN VESC & ĐỊNH DANH BOARD LÊN UI CHÍNH

> **Vấn đề:** Hiện tại các thông số quý giá từ cổng `35a9b4f6` (Snapshot VESC 3 float), `73d50009` (Hash phiên bản 3 board VCU/BMS/CTRL) và `018e6a6f` (Bike Identity Protobuf 108B) mới chỉ xem được khi vào Firmware Lab bấm đọc thủ công.  
> **File cần sửa:**
> - [`lib/core/ble/ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart)
> - [`lib/features/settings/vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart) (hoặc màn hình Chẩn đoán / Thông tin xe)

- [ ] **[2.1] Thêm các trường chẩn đoán vào `BleState` trong [`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L95-L236)**
  - **Cách code:**
    Thêm vào `BleState` và `copyWith`:
    ```dart
    final String? bikeModelCode;    // từ 4aae98e9 (vd: "QT_S1")
    final String? boardManifest;    // từ 73d50009 (vd: "1adadba-#-8c02b07-896e9a7")
    final double? vescCurrent;      // từ 35a9b4f6 float[0] (A)
    final double? vescVoltage;      // từ 35a9b4f6 float[1] (V)
    final double? vescDutyCycle;    // từ 35a9b4f6 float[2] (0.0..1.0)
    ```

- [ ] **[2.2] Viết hàm `fetchVehicleDiagnostics()` trong [`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart)**
  - **Cách code:**
    ```dart
    /// Đọc trọn bộ thông tin định danh & snapshot VESC (đã qua _enqueueGatt + cắt Stale-Tail)
    Future<void> fetchVehicleDiagnostics() async {
      if (state.phase != BlePhase.connected || _sessionKey == null) return;

      // 1. Model xe (4aae98e9)
      final modelDec = await readFwSettingRaw(Gatt.bikeModelChar, 'bike_model');
      final modelStr = modelDec.isEmpty ? null : BleLogger.tryUtf8(modelDec)?.trim();

      // 2. Manifest 3 boards (73d50009)
      final mfDec = await readFwSettingRaw(Gatt.boardManifestChar, 'board_manifest');
      final mfStr = mfDec.isEmpty ? null : BleLogger.tryUtf8(mfDec)?.trim();

      // 3. Serial khung xe (041d5a06)
      await readDeviceSerial();

      // 4. Tên xe lưu trong NVS (88c30d2c)
      final fwName = await readFwBikeName();

      // 5. VESC Snapshot 12B = 3 x float32 LE (35a9b4f6)
      double? vI, vV, vDuty;
      final vescDec = await readFwSettingRaw(Gatt.vescSnapshotChar, 'vesc_snapshot');
      if (vescDec.length >= 12) {
        final bd = ByteData.sublistView(vescDec, 0, 12);
        vI = bd.getFloat32(0, Endian.little);
        vV = bd.getFloat32(4, Endian.little);
        vDuty = bd.getFloat32(8, Endian.little);
      }

      state = state.copyWith(
        bikeName: (fwName != null && fwName.isNotEmpty) ? fwName : state.bikeName,
        bikeModelCode: modelStr ?? state.bikeModelCode,
        boardManifest: mfStr ?? state.boardManifest,
        vescCurrent: vI ?? state.vescCurrent,
        vescVoltage: vV ?? state.vescVoltage,
        vescDutyCycle: vDuty ?? state.vescDutyCycle,
      );
    }
    ```

- [ ] **[2.3] Tự động gọi `fetchVehicleDiagnostics()` & `refreshFwSettings()` sau khi kết nối thành công**
  - **Vị trí:** Trong `_establish()` ([`ble_controller.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/ble/ble_controller.dart#L1560-L1565)) sau khi `state.isAuthorized == true`.
  - **Cách code:**
    ```dart
    if (state.isAuthorized) {
      unawaited(refreshFwSettings());
      unawaited(fetchVehicleDiagnostics());
    }
    ```

- [ ] **[2.4] Hiển thị thẻ "Thông tin Phần cứng & Snapshot VESC" trên [`vehicle_settings_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/settings/vehicle_settings_screen.dart)**
  - **Cách code:** Hiển thị rõ:
    - **Model:** `ble.bikeModelCode ?? 'QT_S1'`
    - **Số khung (VIN/Serial):** `ble.frameSerial ?? '—'`
    - **Hash Firmware 3 Board (`VCU-#-BMS-CTRL`):** `ble.boardManifest ?? '—'`
    - **VESC Snapshot:** Dòng `I = ${ble.vescCurrent} A` · Áp `V = ${ble.vescVoltage} V` · `Duty = ${(ble.vescDutyCycle ?? 0) * 100}%` kèm nút "Làm mới".

---

## 🔍 NHÓM 3: GIẢI MÃ NỐT 4 BYTE ẨN TRONG GÓI 41-BYTE DASHBOARD (`6d2eb205`)

> **Bối cảnh kỹ thuật (từ hàm `buildBikeLogPacket` @ `0x400e0cb8` trong [decomp_builders.log](file:///d:/CuaMan/dat-bike/datbike-eproject/work/firmware_re2/logs/decomp_builders.log#L6-L65) & [`bike_log.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/proto/bike_log.dart#L15-L39)):**  
> Trong 41 byte của gói `6d2eb205`, đã xác định chính xác 37 byte. Còn **4 byte (`offset 12`, `13..14`, `32`)** đang giữ thông tin trạng thái chi tiết của xe:
> - `offset 12` (`1 byte` từ `param_1 + 0xe8`): Mã trạng thái vận hành (`state`).
> - `offset 13..14` (`2 byte uint16 LE` từ `param_1 + 0xea`): Trong `list_ece_mgr.log` dòng `51–53` & `103`, trường này được khởi tạo bằng `0x0002`.
> - `offset 32` (`1 byte` từ `param_1 + 0xed`): Đang gán vào `brake` (khởi tạo bằng `0x01` trong `list_ece_mgr.log` dòng `107–109`).

- [ ] **[3.1] Ghi log riêng 4 byte `[12, 13, 14, 32]` khi thao tác trên xe để lập bảng ánh xạ trạng thái**
  - **Cách thực hiện:** Trong [`decodeDashboardStruct`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/proto/bike_log.dart#L42-L87), trích xuất thêm:
    ```dart
    final rawStateByte = data[12];
    final rawField13_14 = bd.getUint16(13, Endian.little);
    final rawByte32 = data[32];
    ```
  - **Kịch bản quan sát trên xe:**
    1. Đá chân chống cạnh xuống vs gạt chân chống lên → xem byte nào (`12`, `13..14`, hay `32`) đổi bit.
    2. Bóp phanh trái / phanh phải → xem `data[32]` hoặc `data[12]` đổi giá trị thế nào.
    3. Chuyển Mode lái trên cùm công tắc (`Drive` ↔ `Sport` ↔ `Reverse`) → xem `rawField13_14` hoặc `data[12]` đổi giá trị thế nào.
    4. Cắm sạc pin → xem `data[12]` nhảy sang mã trạng thái sạc nào.

- [ ] **[3.2] Cập nhật enum `BikeState` & hiển thị Mode lái (`D / S / R`) + Trạng thái Chân chống / Đang sạc trong [`bike_log.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/proto/bike_log.dart)**
  - Sau khi có bảng giá trị từ `[3.1]`, bổ sung các getter `drivingMode`, `isSideStandDown`, `isCharging` vào `BikeLogMsg`.

- [ ] **[3.3] Hiển thị Huy hiệu (Badge) Mode lái (`D / S / R`) và Cảnh báo Chân chống trên [`my_bike_screen.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/features/home/my_bike_screen.dart)**

---

## 🔋 NHÓM 4: MỞ RỘNG GIẢI MÃ PROTOBUF PIN 207B (`84c7be0b`) & XE 108B (`018e6a6f`)

> **File cần sửa:** [`lib/core/proto/bike_log.dart`](file:///d:/CuaMan/dat-bike/datbike_app/lib/core/proto/bike_log.dart)

- [ ] **[4.1] Viết bộ giải mã `decodeBikeIdentityLog(Uint8List bytes)` cho cổng `018e6a6f` (108B)**
  - **Cấu trúc đã xác minh trong Lab (`lab_catalog.dart` dòng 518):**
    - Tag `0x0a` (Field 1, Length-delimited string): Tên xe (`"Dat Bike Quantum S1"`)
    - Tag `0x12` (Field 2, Length-delimited string): Mã Model (`"QT_S1"`)
    - Tag `0x1a` (Field 3, Length-delimited string): Số Serial (`"RL9C4NGSSSCC00187"`)
    - Các tag varint/fixed32 tiếp theo (`0x20`, ...): Thông số cấu hình phụ của xe.

- [ ] **[4.2] Kiểm tra và bổ sung các trường sức khỏe Pin (Cycle Count, SOH, Độ lệch áp Cell $\Delta V_{\text{cell}}$) trong `BatteryLogMsg` (`84c7be0b`)**
  - **Cách code:** Tính toán tự động từ mảng `cellVols`:
    - `minCellVol`, `maxCellVol`, `deltaCellMv = (maxCellVol - minCellVol) * 1000` (mV).
    - Cảnh báo nếu $\Delta V_{\text{cell}} > 30\text{ mV}$ (lệch áp cell cần cân bằng).

- [ ] **[4.3] Hiển thị Độ lệch áp Cell ($\Delta V_{\text{cell}}$ mV) & Trạng thái cân bằng từng Cell trên Tab Pin**

---

## 📦 NHÓM 5: DỊCH NGƯỢC GIAO THỨC NẠP OTA BLE (`5b6d1069` — CHẾ ĐỘ NGHIÊN CỨU AN TOÀN)

> **Lưu ý an toàn:** Chỉ dịch ngược mã máy từ `mainPcb-1.14.0.bin` và viết tài liệu / trình kiểm tra gói tin, **không gửi lệnh ghi OTA xuống xe thật** cho đến khi xác minh 100% cơ chế Dual-Partition Rollback của ESP32.

- [ ] **[5.1] Decompile 6 handler của `FAST_OTA_SERVICE` (`5b6d1069`) trong Ghidra (`mainPcb-1.14.0.bin`)**
  - Xác định vai trò chính xác của từng cổng:
    - `e0b2b4b4-4b1e-4f3e-8f1e-6b3e4b4b4b4b` (Read / Write control & status)
    - `68311857-4f93-4060-a42d-16da35a5843c` (`writeNoResp`)
    - `07765f94-d850-4e87-a2cf-6bae5d9a0b67` (`writeNoResp`)
    - `46a7b351-6e28-4f88-8432-562506d20152` (`writeNoResp`)
    - `4244dedb-7b6b-4774-9525-d37fde1c67da` (`writeNoResp`)
- [ ] **[5.2] Bổ sung tính năng kiểm tra mã băm SHA256/MD5 của file `.bin` tải về từ `OtaService.downloadBoard()` so với trường `hash` trên server Dat Bike**
