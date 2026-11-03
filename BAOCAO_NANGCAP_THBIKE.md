# Báo cáo nâng cấp THBIKE Premium — phiên làm việc này

Tác giả thực hiện thay đổi: Claude (theo yêu cầu Vũ Thái Hùng).
Không có Flutter SDK trong môi trường này (mạng bị chặn, không tải được SDK) →
**chưa chạy được** `flutter analyze` / `flutter test` / build APK. Cần bạn chạy
các lệnh này trên máy có Flutter, hoặc dùng GitHub Actions
`.github/workflows/build_android.yml` đã có sẵn trong repo.

---

## 1. Regen 5 cấp độ — VẪN KHÓA GHI, có lý do cụ thể

**Không mở khóa điều khiển ghi Regen trong phiên này.** Đây không phải giới
hạn tùy tiện — dựa trên chính 2 file bạn vừa gửi:

- `thbike_ble_log_20261102T193028_1.json`: toàn bộ `gatt_op` trong log chỉ có
  các bước bắt tay xác thực (discoverServices, đọc firmware, authChallenge,
  appAuth, authResponse, time-sync, sessionRegister). **Không có write nào**
  tới `a1d8e7c4` (Grab) hay bất kỳ characteristic nào khác trong suốt phiên
  ghi bằng chứng Regen. Tức là chính THBIKE chưa từng tự gửi lệnh đổi mức.
- Hai bản chụp "Firmware Lab" (`lab_read`, 19:24:18 và 19:24:25) chỉ cách
  nhau ~7 giây, **không có write nào xen giữa**, nhưng 4 characteristic vẫn
  đổi giá trị → đó là các thanh ghi đếm/counter/telemetry tự thay đổi theo
  thời gian, **không phải bằng chứng về một characteristic điều khiển Regen**.
- Chạy lại logic kiểm chứng của `regen_analysis.dart` trên
  `regen_evidence_1793622287049_1.json` (687 mẫu, 5 mốc do bạn đánh dấu
  1–5) cho kết quả:
  - **Dấu dòng pha ĐÃ kiểm chứng**: dương = nạp ngược (regen) — tương quan
    r = −0.775, 98% mẫu dương đi cùng giảm tốc, 84% mẫu âm đi cùng tăng tốc
    (đủ ngưỡng kết luận, n = 502 mẫu tốc độ > 3 km/h).
  - Dòng nạp trung bình theo mức đánh dấu: mức 1 ≈ 7,3 A, mức 3 ≈ 12,2 A,
    mức 2 ≈ 15,2 A, mức 4 ≈ 22,7 A, mức 5 ≈ 24,2 A.
  - Tương quan Spearman giữa **số mức** và dòng nạp trung bình = **0,90**
    (rất mạnh) — phù hợp giả thuyết số mức càng lớn thì Regen càng mạnh.
  - Riêng mức "1" chỉ có 1 đợt nạp hợp lệ → `lowData = true`, kém tin cậy.
  - **Nhưng đây là hiệu ứng quan sát được khi bạn chỉnh "Grab" ở ỨNG DỤNG
    GỐC (Datbike), không phải lệnh do THBIKE gửi.** Đúng như cảnh báo có
    sẵn trong `regen_protocol.dart`: "Char Grab (a1d8e7c4) KHÔNG được coi
    là Regen... Người dùng quan sát đổi Grab làm đổi dòng nạp ngược, nhưng
    đó là một ảnh hưởng chéo chưa đo, không phải bằng chứng về một char
    Regen" dành riêng cho THBIKE điều khiển.

**Kết luận:** có bằng chứng thống kê tốt rằng "Grab" ảnh hưởng tới cường độ
Regen theo đúng chiều 1→5 yếu→mạnh, nhưng **chưa có bằng chứng THBIKE tự ghi
được giá trị đó** (không có write nào trong log, không có btsnoop ghi lại
payload ghi). Mở khóa ghi lúc này nghĩa là đoán UUID/payload rồi gửi thử
xuống bộ điều khiển động cơ thật — đúng điều mục "YÊU CẦU BẮT BUỘC" của bạn
cấm làm. Mình giữ nguyên khóa theo đúng thiết kế phòng thủ đã có sẵn trong
code.

**Để mở khóa thật**, cần 1 trong hai:
1. File btsnoop (hoặc log `gatt_op`) chụp đúng lúc bạn đổi Grab 1→5 trên
   app gốc, cho thấy UUID + payload byte nào được ghi xuống xe; hoặc
2. Tự thử nghiệm bằng màn "Firmware Lab" của THBIKE: ghi thử (ở xe ĐỨNG
   YÊN, không drive gear) một giá trị vào `a1d8e7c4`, đọc lại ngay, rồi đối
   chiếu với log nạp dòng — nếu khớp nhiều lần liên tiếp, đó là bằng chứng
   đủ để set `RegenProtocolSpec.verified = true`.

Phần còn lại của Regen đã sẵn sàng để bật ngay khi có bằng chứng:
- `regen_controller.dart`: cổng an toàn (kết nối, xác thực, đứng yên), ghi
  → đọc lại → so khớp, không báo thành công nếu xe chưa xác nhận. Không
  sửa gì — đã đúng theo yêu cầu Phần 1.3.
- `regen_analysis.dart`: bộ phân tích dòng nạp đầy đủ (kiểm chứng dấu, tách
  đợt regen, so sánh 5 mức, xếp hạng Spearman) — đã có, đã chạy thử bằng
  Python đối chiếu logic, khớp kết quả ở trên. Không cần sửa.

---

## 2. Smart Key 2 mét — đã chỉnh theo đúng yêu cầu

File: `lib/core/proximity/proximity_engine.dart`, `proximity_controller.dart`.

- **Vùng trễ đúng theo yêu cầu**: vùng nhận diện gần nay là **≤ 1,8 m**,
  vùng xác nhận rời xa là **≥ 2,2 m** (hằng số `rangeZoneHalfWidthM = 0.2`
  quanh `rangeLimitM`), khoảng giữa giữ nguyên trạng thái trước đó — khớp
  đúng mục 2.2 của prompt. Trước đây hai ngưỡng cách nhau 1,5 dB cố định,
  không map rõ ràng ra mét.
- **Độ tin cậy ước lượng khoảng cách**: thêm `distanceConfidence()` (0–1,
  heuristic dựa trên số mẫu trong cửa sổ lọc, độ nhiễu, mức hiệu chỉnh) và
  `windowStdDev`, đã đưa vào `ProximitySnapshot.distanceConfidence` để màn
  hình hiển thị độ tin cậy như mục 2.2 yêu cầu.
- Test mới: hysteresis 1,8/2,2 m, vùng đệm giữ trạng thái, độ tin cậy tăng
  theo số mẫu/hiệu chỉnh và về 0 khi mẫu cũ — trong `proximity_engine_test.dart`.

File mới: `lib/core/proximity/smart_key_state.dart` + test
`test/smart_key_state_test.dart` — máy 7 trạng thái đúng tên trong mục 2.3:
`LOCKED / SEARCHING / AUTHENTICATING / NEARBY / UNLOCKED / DISCONNECTED /
SECURITY_LOCK`, cộng 4 màu (xanh/vàng/đỏ/xám) đúng mục 3.3. Quy tắc quan
trọng được code hóa, có test:
- RSSI/khoảng cách **không bao giờ** đủ để vào `nearby`/`unlocked` — luôn
  đòi `authorized == true` trước.
- Mất BLE khi xe **có thể** đang chạy (tốc độ null, telemetry cũ, hoặc > 0)
  → chỉ `disconnected` kèm `warning`, không tự khóa — khớp đúng yêu cầu
  "Khi mất BLE lúc xe chạy, chỉ chuyển sang trạng thái mất kết nối và cảnh
  báo".
- Lỗi bảo mật (`securityFault`) luôn thắng mọi trạng thái khác → `SECURITY_LOCK`.

Đây là máy trạng thái **hiển thị/diễn giải**, không thay thế
`ProximityEngine` (vẫn là nơi duy nhất quyết định unlock/lock thật). Cần nối
`smart_key_state.dart` vào `proximity_screen.dart` để hiển thị (chưa làm
trong phiên này — xem mục "Việc còn lại" bên dưới).

**Dự phòng thẻ / phát lại**: đọc `lib/core/session/bike_session_crypto.dart`
— mỗi lệnh ghi bảo vệ (`buildProtectedWrite`) đã gồm **counter tăng dần** +
tag HMAC tính trên `'W' ‖ counter ‖ uuid ‖ data`, nên phát lại y nguyên một
frame cũ sẽ bị counter cũ chặn (xe sẽ từ chối vì counter không tăng). Đây là
cơ chế chống phát lại hợp lệ, đã có sẵn, không cần thêm. Phần "thẻ NFC dự
phòng" là tính năng **phần cứng của xe** (nêu trong README/disclaimer) —
ứng dụng chỉ có thể nhắc người dùng mang theo thẻ, không thể tự thêm luồng
mở khóa bằng thẻ qua BLE vì đó không phải giao thức của app.

---

## 3. Giao diện — đã nối tiếp (phiên 2)

**`lib/features/proximity/proximity_screen.dart`**: thêm `_SmartKeyBadge`
(chấm màu + tiêu đề + mô tả theo `deriveSmartKey()`, cảnh báo nổi bật khi
mất BLE lúc xe có thể đang chạy) ngay đầu `_StatusCard`; thêm hiển thị độ
tin cậy khoảng cách (%) và vùng gần/xa (m) vào dòng trạng thái sẵn có.
⚠️ **Giới hạn đã biết**: `bluetoothOn` / `permissionGranted` trong
`SmartKeyInput` hiện đặt cứng `true` vì `BleState` chưa expose 2 cờ này
(chỉ có `BlePermissions.check()` dạng hàm async, không phải provider phản
ứng) — đã ghi chú `TODO` ngay trong code thay vì giả vờ đã nối. Tương tự
`securityFault` luôn `false` vì chưa có tín hiệu "nghi phát lại/xác thực bất
thường" nào trong `BleState` hiện tại — không bịa thêm cờ mới.

**`lib/features/regen/regen_screen.dart`**: thêm `_RegenLevelSelector` — 5
nút ECO/LIGHT/NORMAL/STRONG/MAX **luôn hiển thị nhưng vô hiệu hóa** khi
`RegenProtocolSpec.verified == false` (hiện tại luôn vậy), kèm dòng lý do
lấy thẳng từ `RegenController.state.message` + ghi chú rõ: nhãn 5 nút chỉ
là UI chuẩn bị sẵn, KHÔNG map tới giá trị/characteristic nào đã xác minh.
Thêm nút mở thẳng màn "Bằng chứng Regen" (đã có sẵn, không đổi) để người
dùng tiếp tục thu thập dữ liệu hướng tới việc xác minh.

## 4. Việc CHƯA làm (ưu tiên tiếp theo)

1. Nối thật `bluetoothOn` / `permissionGranted` vào `SmartKeyInput` — cần
   bọc `BlePermissions.check()` thành 1 provider trạng thái (StateNotifier)
   thay vì hàm gọi rời rạc.
2. Vòng tròn radar + lịch sử khóa/mở xe trên màn Smart Key (mục 3.3) — hiện
   mới có badge trạng thái dạng text/chấm màu, chưa có hoạt ảnh radar.
3. Dashboard chính gộp đủ 11 chỉ số ở mục 3.1 — chưa làm trong 2 phiên này.
4. Chạy `flutter analyze` / `flutter test` / build APK trên máy có Flutter —
   **bắt buộc** trước khi coi là hoàn thành, vì môi trường này không có SDK
   và không tải được (mạng bị chặn tới `storage.googleapis.com`).
5. Mở khóa Regen thật: cần btsnoop/`gatt_op` chụp đúng lúc đổi Grab trên app
   gốc (thấy UUID+payload ghi), hoặc tự ghi thử bằng Firmware Lab khi xe
   đứng yên, đọc lại nhiều lần để đối chiếu — xem mục 1 ở trên.

## 5. Danh sách file đã sửa/thêm (cả 2 phiên)

- Sửa: `lib/core/proximity/proximity_engine.dart`,
  `lib/core/proximity/proximity_controller.dart`,
  `lib/features/proximity/proximity_screen.dart`,
  `lib/features/regen/regen_screen.dart`,
  `test/proximity_engine_test.dart`
- Mới: `lib/core/proximity/smart_key_state.dart`,
  `test/smart_key_state_test.dart`
- Không sửa (đã đúng/đủ, hoặc chưa đủ bằng chứng cho phép sửa): toàn bộ
  `lib/core/regen/regen_controller.dart`, `regen_protocol.dart`,
  `regen_analysis.dart`, `regen_evidence.dart`, `lib/core/session/*`,
  `lib/core/ble/ble_controller.dart`, `lib/features/regen/regen_evidence_screen.dart`
