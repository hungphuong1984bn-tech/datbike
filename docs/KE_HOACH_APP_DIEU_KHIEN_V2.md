# KẾ HOẠCH DỰNG LẠI APP ĐIỀU KHIỂN XE — "Dat Bike V2" (bản cơ bản, tự động hoá tối đa)

Ngày: 2026-10-26 · Nền tảng: Flutter (giữ nguyên stack hiện tại: flutter_blue_plus + Riverpod)
Nguồn sự thật: giao thức đã verify trên xe thật (mainPcb 1.14.0) — mọi cơ chế trong kế hoạch
đều đã được chứng minh bằng LAB/log, không có giả định mới.

---

## 1. Mục tiêu & nguyên tắc

**Mục tiêu**: app dùng hằng ngày cho 1 chủ xe — mở app là mọi thứ tự chạy: kết nối, xác thực,
đồng bộ giờ taplo, đọc chỉ số, sẵn sàng điều khiển. User chỉ ra tay khi CẦN (bật/tắt, tìm xe, khóa).

**Nguyên tắc UX (bắt buộc với mọi tính năng):**
1. **Tự động mặc định** — mọi bước có thể tự làm thì tự làm, không hỏi.
2. **Im lặng khi suôn sẻ** — không toast/banner khi mọi thứ bình thường; trạng thái kết nối
   hiển thị bằng 1 chip cố định trên header, không bao giờ bằng popup.
3. **Chỉ confirm hành động nguy hiểm** (khóa an toàn cần thẻ NFC). Hành động nguy hiểm theo
   trạng thái xe thì **chặn thẳng + hướng dẫn**, không hỏi (vd tắt xe khi đang chạy).
4. **Không lệnh ngầm lên xe** ngoài chu trình tự động đã định nghĩa (sync giờ + đọc settings —
   1 ghi vô hại + toàn bộ là đọc). Cấm mọi "hiệu ứng phụ" (còi/đèn nhấp nháy) trong luồng tự động.
5. **Không đổ lỗi cho user** — thông điệp lỗi luôn kèm việc cần làm kế tiếp.

**Bỏ khỏi bản cơ bản (chuyển sang menu ẩn 'Chế độ nhà phát triển', mở bằng gõ 5 lần vào logo):**
OTA · VESC/dev-mode (b0ca953d — NGUY HIỂM: toggle làm motor ngừng publish) · LAB kiểm nghiệm ·
Grab · Distance auto · Profile sạc (Era) · Thêm thẻ NFC · Tắt BMS · Factory reset · RECUP/ga hồ sơ local.

---

## 2. Phạm vi tính năng

### Phải có (Must-have)
| Nhóm | Tính năng |
|---|---|
| Kết nối | Tự kết nối xe đã nhớ (bond); quét chỉ khi chưa có xe; tự reconnect thông minh |
| Xác thực | Tự handshake: đường bond-nhanh (status 0x01 → KHÔNG ghi auth) → password đã lưu → tự đăng ký password mới (self-register) — 100% tự động, user không nhập gì |
| Dashboard | Tốc độ, ODO, % pin, km còn lại, điện áp, dòng (âm=xả/dương=sạc), nhiệt BMS/motor/ECU, trạng thái xi-nhan/chân chống |
| Pin | 13 cell + cân bằng + cờ bảo vệ (đọc 30s/lần) |
| Điều khiển | BẬT/TẮT nguồn (an toàn) · TÌM XE (còi hú, chỉ khi xe tắt) · KHÓA AN TOÀN (auto tắt xe → ARM, cảnh báo thẻ NFC) |
| Tự động theo cự ly | (a) **Auto-Secure khi rời xa**: tắt xe → chờ → BẬT KHÓA AN TOÀN · (b) **Mở khóa khi đến gần** (on/off): RSSI cực mạnh 1-2m → tự disarm + giữ kết nối · (c) **Chống trộm rời xa ≥5m**: tự TẮT xe bất kể trạng thái → khóa an toàn (xem 4.6) |
| Đồng bộ giờ | Tự động 1 lần/phiên sau khi session sống (giây-trong-ngày giờ LOCAL) |
| Cài đặt | Giới hạn 60 km/h (đúng ngữ nghĩa ECE=cổng + khóa mode lái) · Tự tắt khi đỗ · Đặt tên xe |
| Chuyến đi | Trip hiện tại: quãng đường, thời gian, tốc độ TB/max, % pin dùng (tự bắt đầu/kết thúc theo isBikeOn) |
| Chẩn đoán | Ghi log JSONL toàn phiên (giữ nguyên hệ hiện tại — nó là sinh tồn của dự án) |

### Nice-to-have (sau bản gốc)
- Chỉ số IM (dòng motor) + duty từ char 35a9b4f6 (3 float: current/V/duty — đã verify).
- Trạng thái dev-mode hiển thị ở menu nhà phát triển (đọc b0ca953d, KHÔNG ghi).
- Xuất log/share 1 chạm; lịch sử chuyến đi lưu local.

---

## 3. Kiến trúc kỹ thuật

### 3.1 Máy trạng thái kết nối (thay thế BlePhase hiện tại)
```
IDLE → RESTORING → CONNECTING → HANDSHAKING → SYNCING → READY
        │             │(fail)      │(fail)       │(fail)
        ▼             ▼            ▼             ▼
     SCANNING → CONNECTING …   RECONNECTING (quiet 0-10s → visible 10-45s)
READY → LINK_LOST → RECONNECTING → (session sống lại → READY, KHÔNG lặp lại handshake
        nếu nonce status=0x01 — đường bond-nhanh)
READY → USER_DISCONNECT → IDLE
```
- Mỗi chuyển trạng thái phát 1 event log + cập nhật chip header. **Không** set message dài.
- `READY` = đã có session key + dashboard counter đã tăng ít nhất 1 lần (oracle đã verify).

### 3.2 Hàng đợi lệnh (CommandQueue) — gốc rễ của "không khó chịu"
- Mọi ghi BLE đi qua 1 queue tuần tự, **khoảng cách tối thiểu 800ms** giữa 2 lệnh (đúng
  cooldown CAN/BMS đã đo), tự chờ khi `isCommandBusy`, không bao giờ throw ra UI.
- Nút bấm → trạng thái nút `busy` (spinner nhỏ) → kết quả cập nhật optimistic, rollback + thông
  điệp hành động nếu fail. **Hết toast lỗi chồng toast lỗi.**
- Mọi handler tự động (auto-lock, time-sync) cũng đi qua queue — hết vĩnh viễn exception
  "Xe đang xử lý lệnh trước đó" như bug 25/10.

### 3.3 Pipeline telemetry
- 1 timer poll dashboard 700ms (giữ nguyên — đã chứng minh giữ link không cần thẻ NFC).
- Decode 1 nơi duy nhất (bảng offset chuẩn 21/10), NaN/Infinity được sanitize trước khi emit.
- Battery log đọc chu kỳ 30s; IM (nếu bật) đọc 5s chỉ khi tab Pin/mở.

### 3.4 Cấu trúc màn hình (4 tab, tối giản)
```
[ XE ]        dashboard + cụm nút điều khiển + trip hiện tại + chip trạng thái
[ PIN ]       13 cell, V/I, nhiệt, cờ bảo vệ, IM (nếu bật)
[ CHUYẾN ]    (nice-to-have) lịch sử chuyến
[ CÀI ĐẶT ]   giới hạn 60 · tự tắt khi đỗ · đặt tên xe · khóa an toàn · tin nhắn trạng thái
              + 'Chế độ nhà phát triển' ẩn (LAB/log/OTA/dev-mode READ-ONLY)
```
Màn quét chỉ xuất hiện khi CHƯA có xe remembered hoặc user chủ động "Đổi xe".

---

## 4. LUỒNG TỰ ĐỘNG CHI TIẾT (trái tim của bản kế hoạch)

### 4.1 Timeline từ lúc mở app (mục tiêu: READY ≤ 8 giây khi xe trong tầm)
```
T+0.0s  Khôi phục prefs: xe cuối (MAC), password đã đăng ký, cài đặt, tên xe.
        UI mở NGAY màn XE với dữ liệu cache cuối (trip/pin) + chip "Đang kết nối…".
T+0.3s  Kết nối trực tiếp MAC remembered (kèm cache-prime quét nhanh 3s cho BLE cache Android).
        ├─ THÀNH CÔNG → 4.2
        └─ FAIL (xe ngủ/xa) → im lặng chuyển SCANNING quét tên 'dat.bik' 20s
             ├─ thấy xe → CONNECTING → 4.2
             └─ không thấy → chip "Không thấy xe — kiểm tra nguồn xe" + nút "Quét lại".
                KHÔNG tự retry vòng lặp vô hạn; tự quét lại mỗi 30s nền im lặng.
```

### 4.2 Handshake (100% tự động, 3 tầng dự phòng)
```
1. Đọc nonce (5e9a2c71, 16B):
   ├─ status=0x01 (bond còn, xe nhớ ta) → KHÔNG ghi auth (bài học 21/10: ghi thừa = xe
   │   đòi thẻ NFC!) → derive key bằng nonce đó + password đã lưu → 4.3
   └─ status=0x00 → ghi auth response = HMAC-SHA256(token fw,'DBauth'+nonce15)[:16]
       → đọc lại nonce mới:
          ├─ 0x01 → derive key → pin-write password ĐÃ LƯU → 4.3
          └─ 0x00 lần 1: thử lại 1 lần với nonce mới (max 2 — không spam 287 write như bản cũ)
          └─ vẫn 0x00 → TỰ ĐĂNG KÝ password mới 12 ký tự random (c8eaf27b ×2 + re-auth)
              → pin-write → derive → 4.3  (đường này đã chạy thật từ v1.2)
2. Toàn bộ quá trình ≤ 6s; nếu session-lock xe (link đứt đột ngột trước đó) → đợi 20s
   và thử lại TỰ ĐỘNG tối đa 3 vòng, chip hiển thị "Xe đang mở khoá phiên…".
```

### 4.3 Sau khi session sống (SYNCING — chạy nền 1 lần, tuần tự qua CommandQueue)
```
1. Verify session: đọc dashboard 2 lần — counter TĂNG = sống (đã là oracle chuẩn).
2. Sau 2s ổn định → ĐỒNG BỘ GIỜ TAPLO (1 protected write 'giây-trong-ngày local').
   Chỉ làm 1 LẦN/phiên + khi user bấm thủ công. Không sync nếu phiên sống < 10s
   (tránh ghi vào lúc xe đang mở khoá).
3. Đọc settings thật: speed-limit + ECE + idling (+ dev-mode flag b0ca953d READ-ONLY)
   → đồng bộ về UI trong 1 lần (hết trạng thái lệch giữa app và xe).
4. Chip chuyển "● SẴN SÀNG — Xe đang bật/tắt". Nếu xe đang TẮT: gợi ý nhẹ 1 dòng
   "Bấm để bật xe" (không popup).
```

### 4.4 Mất liên kết ngoài ý muốn
```
Pha 1 — QUIET (0-10s): retry mỗi 3s, UI gần như không đổi (chip nhấp nháy nhẹ).
  Hết pha 1 mà telemetry trước đó cho thấy xe ĐANG BẬT → nghi issue gần → tiếp pha 2.
  Nếu xe đang TẮT → KHÔNG spam: xe tắt là bình thường (user vừa tắt bằng app/chìa),
  chỉ chờ user mở lại; tự dò lại mỗi 15s nền.
Pha 2 — VISIBLE (10-45s): chip "Mất kết nối — đang tìm lại xe…" + retry 3s/lần.
Sau 45s: chip "Không kết nối được — chạm để thử lại". Ngừng auto ( pin battery).
Tự HOSTILE-CASE: kill-app/màn hình khóa → khi mở lại app chạy lại toàn bộ 4.1 (đường
bond-nhanh đảm nhiệm việc này nhanh gọn).
```

### 4.5 Luồng điều khiển từng nút (đều qua CommandQueue + interlock)
| Nút | Điều kiện chạy | Chuỗi lệnh | Kết quả UX |
|---|---|---|---|
| BẬT XE | xe TẮT + KHÔNG khóa + speed<0.5 | protected '1' (7f13fe5c) + plain '1' (350d9a82) | nút busy ~1.5s → "Xe đã bật" + haptic nhẹ; dashboard tự cập nhật isBikeOn |
| TẮT XE | xe BẬT + speed<0.5 (nếu đang chạy: NÚT VÔ HIỆU + dòng "Dừng xe trước khi tắt") | protected '0' + plain '0' | như trên |
| TÌM XE | xe TẮT + đứng yên (đang bật: hiện 1 dòng "Tìm xe chỉ hoạt động khi xe tắt") | plain '1' → 350d9a82, lặp 1.5s trong 10s | nhạc swallow im lặng; nhấn lần nữa = dừng (KHÔNG gửi '0'!) |
| KHÓA AN TOÀN | speed<0.5 | (nếu xe bật) TẮT xe → đợi 2s → ARM '1' (eec8fd7f) | dialog duy nhất trong app: quy trình + "thẻ NFC trong tay?" ; sau khóa chip đỏ "ĐANG KHÓA" |
| MỞ KHÓA | còn kết nối | disarm '0' | nếu mất kết nối: hướng dẫn "Quẹt thẻ NFC lên xe rồi bấm kết nối lại" |

### 4.6 Tự động theo cự ly (Proximity Automation) — 3 cơ chế, 3 công tắc riêng trong Cài Đặt

Đặc điểm chung: quyết định dựa trên **RSSI đã lọc Kalman** (đã có) + **hysteresis 2 ngưỡng
vào/ra khác nhau** + **yêu cầu bền vững theo thời gian** trước khi hành động — chống kích hoạt
nhầm khi sóng nhấp nhô. Mọi lệnh đi qua CommandQueue (điều kiện kích hoạt bao gồm: queue rỗng,
không ở menu nhà phát triển/LAB, user không vừa thao tác chủ động trong 10s). Ngưỡng RSSI mặc
định dưới đây, **hiệu chỉnh được** bằng wizard 1 phút (4.6.d).

#### a) Auto-Secure khi rời xe (mặc định OFF; bật 1 lần, nhớ vĩnh viễn)
```
Điều kiện: ON · xe đang BẬT · đứng yên (speed<0.5) · RSSI ≤ ngưỡng "rời xa"
          (mặc định -85 dBm ≈ 8-10m) LIÊN TỤC 3 chu kỳ (~3s) · queue rỗng.
Chuỗi lệnh (đúng quy trình khóa chuẩn 4.5, hoàn toàn tự động):
  1. TẮT nguồn xe (protected '0' 7f13fe5c + plain '0' 350d9a82)
  2. Đợi 2s (BMS ổn định)
  3. BẬT KHÓA AN TOÀN (ARM '1' → eec8fd7f)
  4. Chip đỏ "XE ĐÃ TỰ KHÓA AN TOÀN" + 1 notification (duy nhất, không lặp)
     + event log auto_secure_triggered {rssi, steps}.
Nếu link BLE đứt ngay sau ARM (hành vi gốc xe: cần thẻ NFC) → chip
"ĐÃ KHÓA — quẹt thẻ NFC để mở" + CHẮN auto-reconnect spam.
```

#### b) Mở khóa khi đến gần — Walk-Up Unlock (mặc định OFF)
```
Điều kiện: ON · xe đang KHÓA AN TOÀN (app biết trạng thái) · link BLE còn sống ·
          RSSI ≥ ngưỡng "cực mạnh" (mặc định -55 dBm ≈ 1-2m) LIÊN TỤC 2 chu kỳ (~2s).
Chuỗi: MỞ KHÓA AN TOÀN (disarm '0' → eec8fd7f) → chip "ĐÃ MỞ KHÓA — sẵn sàng" →
       user bấm BẬT XE như thường (KHÔNG tự bật xe — an toàn).
Giữ kết nối khi đứng gần: poll dashboard duy trì liên tục (chính là cơ chế giữ-link
       đã chứng minh); khi app mở + ở gần, tăng tần suất đọc RSSI để phản xạ nhanh.
Ngoại lệ thật: nếu sau ARM link đã đứt hẳn → KHÔNG thể disarm qua BLE — app phát hiện
       (ARM xong mất link, không recover) và hướng dẫn "Quẹt thẻ NFC lên xe để mở"
       (hành vi gốc firmware, app không vượt được).
```

#### c) Chống trộm: tự tắt xe khi rời xa ≥5m (mặc định OFF — tính năng NẶNG)
```
Điều kiện: ON · RSSI ≤ ngưỡng "5m" (mặc định -78 dBm) LIÊN TỤC 5 chu kỳ (~5s) · queue rỗng.
          ← 5 giây bền CHẮT: không bao giờ tắt xe giữa chừng vì sóng nhấp nhô.
Hành vi (theo yêu cầu chủ xe): TẮT NGUỒN XE BẤT KỂ TRẠNG THÁI (kể cả đang chạy) —
          ưu tiên chống trộm do chủ xe cấu hình; sau đó nối tiếp chuỗi Auto-Secure
          (đợi 2s → ARM khóa an toàn).
Giới hạn vật lý: chỉ gửi được khi app VẪN còn link BLE; nếu mất link hoàn toàn thì
          không thể gửi — ghi event theft_aware_link_lost {last_rssi} để hậu kiểm.
Khi speed>0.5 tại lúc kích hoạt → vẫn thực hiện (theo thiết kế), log speed lúc lệnh.
Chip/notification đỏ "CHỐNG TRỘM: xe đã tắt + khóa (thiết bị ở cách xa ≥5m)".
```

#### d) Wizard hiệu chỉnh RSSI (chạy 1 lần khi bật bất kỳ tính năng cự ly nào)
```
"Đứng cạnh xe"  → đo 5s → mốc RSSI_gần.
"Lùi ra 5m"     → đo 5s → mốc RSSI_5m.
App tự đặt: gần = RSSI_gần − 5dB · 5m = RSSI_5m + 3dB · rời-xa(a) = RSSI_5m − 7dB.
Bỏ qua được (dùng mặc định) cho ai không muốn đo.
```

#### e) Tương tác giữa các cơ chế
- (c) và (a) dùng chung chuỗi "tắt → ARM"; (c) chỉ thêm "bất kể trạng thái + ngưỡng gần hơn".
- (b) là đối trọng: sau khi (b) mở khóa, bộ đếm chu kỳ RSSI reset (chống tắt lại ngay).
- Cả 3 tạm ngừng khi: menu nhà phát triển/LAB mở, queue đang chạy, user thao tác trong 10s
  gần nhất (user-intent-first).
- Mặc định cả 3 OFF — bật từng cái trong Cài Đặt → "Tự động theo cự ly", kèm mô tả ngắn
  đúng hậu quả ("Xe sẽ TẮT và KHÓA khi điện thoại ở cách ~5m — kể cả đang chạy").

---

## 5. BẢNG QUY TẮC CHỐNG-PHIỀN (anti-annoyance) — review bắt buộc mỗi PR
| # | Quy tắc |
|---|---|
| 1 | Sự kiện kết nối/handshake/sync KHÔNG dùng toast/snackbar/dialog — chỉ chip header + log |
| 2 | Toast chỉ cho kết quả hành động user chủ động, tối đa 1 toast cùng lúc, tự tắt 4s, có thể vuốt tắt |
| 3 | Dialog xác nhận duy nhất: KHÓA AN TOÀN. Mọi hành vi nguy hiểm theo trạng thái → chặn + hướng dẫn |
| 4 | Không chồng lệnh: queue + debounce nút (chặn double-tap 800ms) |
| 5 | Không nhấp nháy layout: dữ liệu cache hiển thị ngay, thay thế mượt khi có dữ liệu mới (fade 150ms) |
| 6 | Không tự phát tiếng/nhấp nháy trên xe trong nền — cấm find-bike/honk trong mọi auto flow |
| 7 | Mọi message lỗi = việc cần làm kế tiếp ("Đặt thẻ NFC lên đầu đọc xe…", "Đưa điện thoại lại gần xe…") |
| 8 | Chip trạng thái ≤ 4 trạng thái hiển thị: SẴN SÀNG / ĐANG KẾT NỐI / MẤT KẾT NỐI / ĐANG KHÓA |
| 9 | Không giăng cản khi xe không có: app vẫn mở được toàn bộ UI offline, chỉ vùng điều khiển mờ + nhắc |
| 10 | Không bao giờ xoá/đè message đang hiển thị bằng message hệ thống (bug wipe 700ms bản cũ) |

---

## 6. An toàn (interlock) — cứng trong controller, không phụ thuộc UI
1. Cấm tắt nguồn/khóa khi speed > 0.5 km/h — NGOẠI LỆ DUY NHẤT: luồng chống trộm 4.6.c
   do CHỦ XE chủ động bật (ưu tiên chống trộm > an toàn vận hành theo lựa chọn của user).
2. Cấm bật nguồn khi đang KHÓA AN TOÀN (isLocked).
3. Tìm xe chỉ khi xe TẮT; dừng tìm xe KHÔNG bao giờ gửi '0' (gói '0' = lệnh tắt nguồn).
4. KHÔA AN TOÀN bắt buộc qua dialog cảnh báo thẻ NFC (mất BLE = phải quẹt thẻ).
5. B0ca953d (dev-mode/đèn): CHỈ ĐỌC trạng thái ở menu phát triển; **không có nút ghi** —
   ghi char này = toggle dev-mode làm motor ngừng publish (phân tích firmware 26/10).
6. Speed-limit: bật = ECE+SpeedLimit đồng bộ; tắt = nhắc power-cycle 1 dòng duy nhất (không lặp).

---

## 7. Lộ trình triển khai
| Mốc | Nội dung | Tiêu chí đạt |
|---|---|---|
| M1 — Bộ khung V2 | Máy trạng thái + CommandQueue + luồng 4.1-4.3 + dashboard + Bật/Tắt/Tìm xe | Mở app → READY tự động ≤ 8s (3/3 lần); 0 toast khi suôn sẻ; test widget cho state machine |
| M2 — Ổn định | Reconnect 2 pha + trip tự động + time-sync polish + battery tab | Rơi link 10 lần/tự hồi 9; kill-app 5 lần/tự hồi; session-lock tự qua trong ≤ 60s |
| M3 — Cài đặt & khóa | Giới hạn 60 (đúng ngữ nghĩa ECE) + tự tắt khi đỗ + đặt tên + KHÓA AN TOÀN chuẩn | Checklist trên xe: mỗi nút chạy đúng bảng 4.5, không hiệu ứng ngoài ý muốn |
| M3.5 — Tự động theo cự ly | 3 cơ chế 4.6 (auto-secure tắt→ARM · walk-up unlock · chống trộm 5m) + wizard RSSI | Test thật: rời xe → xe TẮT+KHÓA đúng 10/10 lần, KHÔNG false-positive khi để điện thoại trên xe; đến gần → tự mở khóa ≤3s; cả 3 OFF mặc định |
| M4 — Trải nghiệm | IM display (35a9b4f6), menu phát triển ẩn, export log, haptic/tuỳ chọn | User-acceptance 1 tuần sử dụng thực tế, log sạch (0 exception trong app_errors) |

**Nguyên tắc chuyển tiếp**: không viết mới từ số 0 — tái sử dụng toàn bộ lớp đã verify của
code hiện tại (crypto/session crypto/poll/decoder/logger/LAB), chỉ thay phần orchestration
(state machine + queue) và UI. Code cũ ở nhánh features/firmware-settings là tham chiếu.

---

## 8. Rủi ro & giảm thiểu
| Rủi ro | Giảm thiểu |
|---|---|
| Session-lock xe sau link đứt đột ngột | Luồng 4.2 có vòng chờ 20s ×3 tự động (đã chứng minh hoạt động) |
| BLE cache Android khiến direct-connect fail | Giữ cache-prime quét 3s (đã có) + đường scan fallback |
| Password đã lưu bị rotate (app gốc kết nối xen vào) | Tự self-register lại (đã chạy thật); phát hiện qua oracle counter đứng yên |
| User bấm loạn nút khi xe đang bận | CommandQueue + nút busy + debounce — không throw, không toast bão |
| Hiệu ứng khó chịu trên xe (còi/đèn tự phát) | Quy tắc 6 + bỏ hẳn nút ghi dev-mode khỏi UI cơ bản |
| False-positive RSSI (tắt/khóa nhầm khi user vẫn cạnh xe, túi áo/đéfono che sóng) | Kalman + hysteresis + bền 3-5 chu kỳ + wizard hiệu chỉnh theo máy; chống trộm (c) yêu cầu xác nhận 5s; không bao giờ tự ARM khi link yếu không gửi được |
| ARM làm xe rớt link → walk-up unlock không disarm được | Đường dẫn thẻ NFC (hành vi gốc) + app nhận diện và hướng dẫn; walk-up hoạt động khi link còn sống nhờ poll liên tục |
