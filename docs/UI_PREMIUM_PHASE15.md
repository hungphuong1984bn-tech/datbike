# Phần XV — Nâng cấp giao diện Premium Smart EV

**Trạng thái xác minh:** CHƯA chạy `flutter analyze`, `flutter test`, `flutter build`, chưa thử trên thiết bị
(môi trường soạn thảo không có Flutter/Dart SDK). Đã kiểm tra tĩnh: cân bằng ngoặc mọi file đã sửa,
quét ngữ cảnh `const` cho toàn bộ chỗ dùng `Bms.*`, đối chiếu diff với bản gốc. Chạy trước khi phát hành:

    flutter pub get && flutter analyze && flutter test && flutter build apk

## Hiện trạng (kết quả rà soát)
Hệ thống thiết kế (token, `Panel`, `GlassCard`, `StateView`, `FreshnessBadge`, thanh điều hướng 5 tab, Dark/Light)
đã có từ các đợt trước nên **không viết lại**. Khoảng hở thật sự tìm thấy:

| Vấn đề | Vị trí | Xử lý |
|---|---|---|
| Bác sĩ Pin luôn ép Dark, Light mode không đồng bộ (226 chỗ `Bms.*` là hằng số) | `features/battery/**` | `Bms.*` thành getter theo `AppColors`; Light dùng biến thể đậm cho chữ/ngữ nghĩa |
| Lớp phủ `Colors.white` cứng (lưới biểu đồ, ô nhập, thanh nền) vô hình ở Light | views + widgets BMS | `Bms.overlay(a)` (trắng ở Dark, mực ở Light), `Bms.sunken` |
| Vòng SOC không vẽ lại khi đổi sáng/tối | `health_view.dart` | `shouldRepaint` xét thêm chế độ sáng/tối |
| Thiếu trạng thái Disconnected / Stale dùng chung | Regen và các màn đọc telemetry | `LiveStateBanner`, `StateKind.disconnected/stale` |
| Không có khung chờ khi tải | toàn app | `SkeletonBlock` / `SkeletonCard` |
| `Colors.white54` trên dialog sáng (chữ đếm ký tự gần như vô hình) | `vehicle_settings_screen.dart` | `AppColors.textMuted` |
| `Colors.orange` cứng ở banner Smart Unlock | `proximity_screen.dart` | `AppColors.amber` |
| Chữ hệ thống rất lớn gây tràn ở màn nhỏ | `main.dart` | giới hạn text scale 0.9–1.4 |

## Thành phần mới — `lib/ui/ds/live_state.dart`
- `resolveLiveLevel(phase, lastTelemetryAt, now)` — hàm thuần: `disconnected · connecting · waiting · stale · live`
  (có test `test/live_state_test.dart`).
- `LiveStateBanner` — ẩn khi dữ liệu mới (≤ 5 s); khi không: nêu rõ chưa/mất kết nối, đang kết nối, đang chờ dữ liệu,
  dữ liệu cũ kèm giờ nhận. Nút "Kết nối" cao ≥ 48 dp. Chỉ ĐỌC `bleProvider`.
- `SkeletonBlock/Card` — nhấp nháy nhẹ, đứng yên khi bật "giảm chuyển động".
- `BottomActionBar` — thanh thao tác neo đáy (vùng ngón cái) cho màn phụ. **Chưa gắn vào màn nào**; dùng khi cần.

## Bảng 5 trạng thái
| Trạng thái | Thành phần |
|---|---|
| Loading | `StateView(kind: loading)` · `SkeletonCard` |
| Empty | `StateView(kind: empty)` |
| Error | `StateView(kind: error)` + thử lại |
| Disconnected | `LiveStateBanner` · `StateView(kind: disconnected)` |
| Stale | `LiveStateBanner` · `FreshnessBadge` · `DataStateBanner` (BMS) |

## Cố ý KHÔNG đổi
- **Trung tâm điều khiển**: đã có `cc_link_banner` nêu điều kiện gửi lệnh; thêm banner nữa sẽ trùng và dễ làm lệch test.
- **Bác sĩ Pin**: mỗi tab đã có `DataStateBanner` theo độ mới của gói BMS.
- **Dashboard HUD / Cluster / Dashboard Studio**: palette riêng do người dùng tự chọn (tính năng tùy biến).
- Màu trắng trên nút đặc, marker bản đồ, thanh HUD tối nổi trên bản đồ (Hành trình): chủ ý, không phải lỗi theme.
- Không đổi BLE/GATT, provider, repository, dữ liệu, quyền hệ thống. Không thêm số liệu mẫu.

## Cần kiểm bằng mắt trên máy
1. Bác sĩ Pin ở Light: 6 tab, biểu đồ, vòng SOC, ô nhập ở tab Bảo vệ; đổi sáng↔tối khi đang mở màn.
2. Regen ở 320 dp, chữ hệ thống 130% và 140%.
3. `LiveStateBanner`: rút kết nối khi đang mở Regen → "Mất kết nối" rồi "Kết nối lại" rồi biến mất khi có khung mới.
4. Tương phản chữ ngoài nắng ở Light (`Bms.textFaint` → `AppColors.textMuted`).

## Còn lại (chưa làm)
- Chưa gắn `SkeletonCard` vào các màn đang dùng vòng xoay (Trạm sạc, Nhật ký, OTA).
- `trip_route_screen`, `my_bike_screen`, `vehicle_settings_screen` còn nhiều màu cứng (tím `8B5CF6`, xanh `38BDF8`…) cần rà theo từng ngữ cảnh.
- Giới hạn text scale 1.4 là đánh đổi với trợ năng; nên hỏi người dùng thật.
