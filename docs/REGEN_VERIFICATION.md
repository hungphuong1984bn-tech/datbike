# Xác minh giao thức Regen (phanh tái sinh) — Dat Bike Quantum S1

## 1. Kết quả kiểm tra mã nguồn (v2.8.0, fw 1.14.0)

| Nguồn | Kết quả |
|---|---|
| `lib/core/ble/gatt.dart` | Không có UUID Regen. Các char ghi được: ECE, SpeedLimit, Grab, IdlingTurnOff, Distance, ChargingProfile, Power, Immobilizer, Name… |
| `lib/core/ble/ble_controller.dart` | `setRecupLevel()` chỉ lưu SharedPreferences, **không gửi BLE**. Chú thích ghi rõ fw 1.14.0 chưa hỗ trợ ghi RECUP. |
| `docs/BLE_PROTOCOL_SPEC.md` | Chỉ nhắc `phaseCurrent` âm khi phanh tái sinh (telemetry, chỉ đọc). Không có lệnh Regen. |
| Firmware Lab (`lab_catalog.dart`) | Không có mục Regen. `35a9b4f6` (VESC snapshot) chỉ đọc. |

**Kết luận:** chưa có bằng chứng xe nhận lệnh đổi Regen qua BLE. Có thể Regen nằm trong
cấu hình VESC (CAN, không đi qua BLE của Taplo) hoặc cấu hình chỉ đổi được bằng cách khác.

> Lưu ý: file tải lên là **2.8.0**, không phải 2.6.6. Mô-đun này được thêm vào 2.8.0.

## 2. Quy trình xác minh bắt buộc

1. **btsnoop**: Android → Developer options → *Enable Bluetooth HCI snoop log*. Mở app gốc
   Dat Bike (xe ĐỨNG YÊN, nghỉ máy), đổi Regen qua từng mức, mỗi lần ghi lại giờ + mức.
   Lấy `btsnoop_hci.log` (bug report).
2. **Wireshark**: lọc `btatt.opcode == 0x12 || 0x13` (Write Req/Rsp). Tìm handle được ghi
   *đúng lúc* đổi Regen. Map handle → UUID bằng Read By Type/Discovery trong cùng capture.
3. **Giải mã khung**: payload protected = `[counter u32][data][tag4]`; dùng
   `BikeSessionCrypto` trong repo để giải mã `data` và so với mức đã chọn.
4. **Firmware (Ghidra)**: tìm handler `onWrite…` của UUID đó: giá trị hợp lệ, NVS key,
   có kiểm tra tốc độ/trạng thái chạy không, có chuyển xuống VESC không.
5. **Đọc lại**: xác nhận char đọc được mức hiện tại và giá trị đổi đúng sau mỗi lần ghi.
6. **Điều kiện an toàn**: chỉ cho phép đổi khi đang chạy nếu có tài liệu nhà sản xuất hoặc
   bằng chứng firmware (handler chấp nhận khi chạy mà không ảnh hưởng ổn định). Nếu không
   có, giữ `requiresStandstill: true`.
7. Test trên xe kê chống, bánh không chạm đất, rồi đứng yên trên mặt đất.

## 3. Cách mở khóa trong mã khi đã xác minh

1. Trong `regen_controller.dart`, thay `regenSpecProvider` bằng `RegenProtocolSpec(verified: true, characteristicUuid: ..., levels: [...], evidence: 'btsnoop 2026-xx-xx + FUN_xxxx')`.
2. Viết `RegenTransport` thật: ghi qua cơ chế `_writeSetting` (protected write) trong
   `BleController`, đọc lại qua `readFwSettingRaw`; giải mã đúng định dạng đã xác minh.
3. Thay `regenTransportProvider`. Chạy `flutter test test/regen_test.dart`.
4. Test thực tế các mục: đổi mức, đọc lại, rớt kết nối giữa chừng, kết nối lại.

Cho tới lúc đó app **không gửi bất kỳ lệnh Regen nào**.


---

## 4. Cập nhật 28/10/2026 — Regen qua char Grab (nay hiển thị là "Regen") (`a1d8e7c4`)

**Bằng chứng hiện có**
- Lab 23/10: ghi `'1'` → đọc lại `01` (Ghidra `onWriteGrabMode @0x40153e30`, cùng parser boolean với ECE/SpeedLimit).
- Người dùng xác nhận 28/10: đổi Grab làm **dòng nạp ngược thay đổi** (chưa ghi hướng mạnh/yếu).

**Đã làm trong app**
- Mô-đun Regen nối vào Grab: mức 0 và 1 (đã xác minh), đọc lại xác nhận sau mỗi lần đổi.
- Chỉ đổi khi xe đứng yên và có telemetry mới (< 4 giây). Cổng này cũng áp cho công tắc Grab cũ
  trong Cài đặt/My Bike (`setFwGrabMode`), vì Grab giờ được coi là có ảnh hưởng Regen.
- **Nhiều mức:** app KHÔNG tự thêm mức. Nút "Dò thêm mức Grab" ghi thử 2, 3, 4, đọc lại, dừng ở mức
  đầu tiên xe không đọc lại đúng, rồi LUÔN khôi phục mức ban đầu. Mức dò được gắn "(thử nghiệm)".
- Bảng "Đo hiệu ứng" hiển thị công suất tức thời và đỉnh nạp ngược để so sánh các mức.

**Giới hạn cần biết**
- Parser boolean nhiều khả năng gộp mọi giá trị khác `'1'` về 0 → có thể xe chỉ có 0/1. Khi đó nút dò sẽ
  báo "Chỉ mức 0/1 được xác nhận" và không có thêm mức.
- Nếu xe đọc lại đúng mức ≥ 2, điều đó chỉ chứng minh **giá trị được lưu**, chưa chứng minh có thêm
  một nấc Regen khác. Phải đo bằng bảng "Đo hiệu ứng" (cùng tốc độ, cùng đoạn đường, chỉ nhả ga).
- Mức ≥ 2 có thể làm VESC hành xử ngoài dự kiến: chỉ dò khi xe đứng yên, tốt nhất kê chống.

**Quy trình đo một mức:** kê chống/đứng yên → chọn mức → Gửi xuống xe → thấy "Đã xác nhận từ xe" →
Reset đỉnh → chạy chậm nơi vắng ~15–20 km/h → nhả ga (không phanh) → ghi đỉnh nạp ngược và quãng giảm tốc.


---

## 5. Cập nhật 31/10/2026 — tách Grab khỏi Regen

Mục 4 ở trên coi char Grab (`a1d8e7c4`) là "Regen mức 0/1" và có nút "Dò thêm mức". Đã **thay đổi**:

* Grab được điều khiển riêng ở Trung tâm điều khiển vận hành (`docs/CONTROL_CENTER.md`) với đúng hai giá trị 0/1.
* Mô-đun Regen **khoá hoàn toàn** (`regenSpecProvider` = `unverified`): không có đường ghi, không bộ chọn mức.
* **Đã gỡ** nút/hàm "Dò thêm mức Grab" (ghi 2, 3, 4 xuống xe) và mức Grab tối đa 9 — chưa có bằng chứng và rủi ro làm VESC hành xử ngoài dự kiến.
* Quan sát "đổi Grab làm đổi dòng nạp ngược" được giữ như một **ảnh hưởng chéo chưa đo**, không phải bằng chứng có kênh Regen.
* Bảng "Đo hiệu ứng" giờ là thẻ chỉ đọc: dòng pha, điện áp, công suất V×I và hai cực trị (không giả định dấu — xem CONTROL_CENTER.md §1).
