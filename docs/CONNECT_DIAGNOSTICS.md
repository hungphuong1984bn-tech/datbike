# Chẩn đoán kết nối BLE — Datbike Quantum S1 (build 20261029-diag1)

## Cách lấy log/báo cáo sau mỗi lần kết nối
- Thư mục: `Android/data/vn.mybike.mybike_app/files/ble_logs/` (hoặc màn hình Logs trong app).
- `session_*.jsonl`: log từng bước (stage_start/ok/warn/failed, gatt_op, gatt_connect_callback, mtu_changed, bond_state, encryption_error, telemetry_first_read…).
- `connect_report_*.txt`: báo cáo tóm tắt — **bước cuối cùng thành công** và **bước đầu tiên thất bại**, mã lỗi, timeout, MTU thực tế, bằng chứng bond.
- Token/PIN/password/khóa phiên/response xác thực KHÔNG được ghi (Redactor che ở `BleLogger.event`).

## Các bước (ConnectStage) và loại lỗi (ConnectFailureKind)
permissions → adapter → scan → selectDevice → gattConnect → mtu → discoverServices → readFirmware/bonding → authChallenge → appAuth → authResponse → sessionKey → sessionRegister → notifications → telemetry.
Loại lỗi riêng: permissionDenied, adapterOff, busy, storageCorrupt, gattConnectFailed/Timeout, linkLostDuringSetup, serviceDiscoveryFailed, requiredServiceMissing, bondingFailed/Rejected, encryptionRequired, bondMismatchSuspected, authChallengeUnavailable, authRejected, appAuthFailed, sessionKeyInvalid, operationTimeout…

## Đối chiếu BLE_PROTOCOL_SPEC.md ↔ code (KHÔNG sửa code theo, chỉ ghi nhận)
| Mục | Tài liệu | Code (`bike_session_crypto.dart`) |
|---|---|---|
| §4.3 session key | `HMAC(nonce15, token‖password)` | HKDF 2 bước: `PRK=HMAC(nonce15, token‖pw)`, `key=HMAC(PRK,'DBsess1'‖0x01)` |
| §5.1 protected write | MAC trên `counter‖uuid‖payload` | MAC trên `'W'‖counter‖uuid16‖payload` |
| §5.2 protected read | keystream `counter‖uuid‖i` | `'R'‖counter4‖uuid16‖blockIdx` |
| §3 reconnect | ghi c8eaf27b trước 5e9a2c71 | khớp (SHA-256 `challenge>>>1 ‖ password`) |
Header comment của `bike_session_crypto.dart` ghi rõ công thức HKDF/'W'/'R' "chưa verify lại tag trên frame thật". Tài liệu §4.3/§5 và code đang **mâu thuẫn**; chỉ btsnoop mới phân xử được. Code KHÔNG bị đổi.
