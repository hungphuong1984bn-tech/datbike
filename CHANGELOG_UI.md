# Phần XV — Premium Smart EV UI (xem docs/UI_PREMIUM_PHASE15.md)
- Bác sĩ Pin đồng bộ Light/Dark (Bms.* theo AppColors; lớp phủ & biểu đồ theo chế độ)
- MỚI ui/ds/live_state.dart: LiveStateBanner (Disconnected/Connecting/Waiting/Stale), SkeletonBlock/Card, BottomActionBar
- StateKind thêm disconnected, stale
- Regen dùng DsScaffold + LiveStateBanner; Smart Unlock bỏ màu cam cứng; sửa chữ vô hình ở dialog "Đặt tên xe" (Light)
- main.dart: giới hạn text scale 0.9–1.4
- CHƯA chạy flutter analyze/test/build

# Redesign UI — "Digital Cockpit" (Premium EV)

Chỉ thay đổi trình bày. Không đổi: BLE/UUID/GATT, Provider, Repository, Service, API, dữ liệu, quyền hệ thống, chuỗi hiển thị (test vẫn khớp).
Bản gốc: thư mục `lib` được sao lưu trước khi sửa.

## File đã sửa (13) + 1 file mới
- ui/app_theme.dart   — palette Graphite/Navy/Electric Blue/Cyan (Dark + Light), radius lớn hơn, bóng nhẹ, theme nút/slider/tab/segmented, token `electric`, `electricGlow`, `electricGradient`
- ui/widgets.dart     — Panel, StatusPill, MetricTile, VehicleCommandButton (gradient Electric→Cyan), RoundControl, BatteryRangeCapsule, NoticeBanner, SectionTitle
- ui/ds/ds_tokens.dart, ui/ds/glass_card.dart — gradient hero/page, viền thẻ
- ui/gauge.dart      — vòng cung tốc độ Electric→Cyan có quầng sáng, số km/h lớn hơn
- ui/map_style.dart (MỚI) + features/navigation/charge_finder_screen.dart — bản đồ Google ở Dark Mode (chỉ thêm tham số `style`)
- features/home/home_shell.dart, my_bike_screen.dart, home_hero.dart — thanh điều hướng, nút thao tác nhanh dạng squircle, tốc độ nổi bật hơn
- features/battery/bms_theme.dart, cluster/cluster_screen.dart (theme mặc định), splash/splash_overlay.dart — đồng bộ màu

## Cố ý KHÔNG đổi
- Các theme người dùng tự chọn trong Dashboard Studio / Cluster (tính năng tùy biến).
- Bản đồ vẫn dùng đúng nguồn tile / trạm sạc cũ.

## Cần chạy trên máy có Flutter
flutter pub get && flutter analyze && flutter test
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols

# Phần XVI — Điều hướng 5 tab theo prompt Premium
- home_shell.dart: HOME · VEHICLE · CONTROL · MAP · SETTINGS (tab Xe/Điều khiển là trung tâm mới, tab Bản đồ = ChargeFinderScreen cũ)
- MỚI features/hubs/{hub_widgets,vehicle_hub_screen,control_hub_screen}.dart: chỉ đọc bleProvider/proximityProvider, thiếu dữ liệu → "N/A", dùng LiveStateBanner
- Bác sĩ Pin, Chẩn đoán, BLE, Sạc, Vận hành nay vào từ tab Xe; Smart Key, Regen, Control Center, Cài đặt xe vào từ tab Điều khiển
- Không đổi BLE/Smart Key/Regen. CHƯA chạy flutter analyze/test/build (sandbox không có Flutter)

# Phần XVII — Trang chủ theo mockup
- home_hero.dart: vòng SOC (CustomPaint, gradient) cạnh ảnh xe · tốc độ 64pt giữa + ODO · hàng Điện áp/Dòng điện/Công suất · thanh Regen
- Dòng điện = dòng pha (dấu đã kiểm chứng: + nạp ngược, − kéo ga); công suất = V×I giữ dấu. Mất kết nối → "--"
- Thanh Regen phản ánh dòng nạp ĐO ĐƯỢC (5 vạch ≈ 5 A/vạch) + Wh đã thu hồi; KHÔNG hiện "Mức 1–ECO" vì xe chưa có kênh đọc mức Regen
- HomeHeroCard thêm 3 tham số tuỳ chọn (odoKm, reading, recoveredWh); constructor cũ vẫn hợp lệ. my_bike_screen.dart chỉ thêm 3 tham số truyền vào + 1 import
- Bỏ _EnergyBar cũ (thay bằng vòng SOC). CHƯA chạy flutter analyze/test

# Phần XVIII — Gọn Trang chủ
- overview_metrics.dart: bỏ ô Điện áp pin và ODO (đã có ở thẻ Hero) → còn 4 ô (BMS, động cơ, ECU, chế độ lái), lưới 2 cột khi số ô không chia hết cho 3
- MỚI overview_collapsible.dart: khối thu gọn (AnimatedSize, widget con không dựng khi đóng)
- my_bike_screen.dart: "Năng lượng & phiên sạc" thu gọn mặc định, tự mở khi đang sạc, người dùng bấm thì theo lựa chọn của họ
- Giữ nguyên: Điều khiển nhanh, Trung tâm điều khiển (công tắc Grab/ECE), Hành trình, Trạm sạc gần nhất. Không xóa chức năng nào
- CHƯA chạy flutter analyze/test

# Phần XIX — Trang chủ rút gọn
- Thứ tự mới: Header · Hero · Trạng thái · Điều khiển nhanh · Trung tâm điều khiển · 4 khối thu gọn
- Thu gọn mặc định (OverviewCollapsible): Thông số kỹ thuật · Năng lượng & phiên sạc (tự mở khi đang sạc) · Hành trình · Trạm sạc gần nhất
- Trung tâm điều khiển (công tắc Grab/ECE) được kéo lên trên các khối thu gọn. Không xóa chức năng, không đổi logic
- CHƯA chạy flutter analyze/test

# Phần XX — Smart Key radar
- MỚI features/proximity/smart_key_radar.dart: SmartKeyRadarCard (CustomPaint) — vòng chia 4 mức theo giới hạn (2 m → 0,5/1/1,5/2... gấp đôi giới hạn), vòng giới hạn nhấn màu, dải trễ gần/xa (1,8–2,2 m), điểm điện thoại, quầng mờ theo độ tin cậy, tia quét (tắt khi giảm chuyển động)
- Trung thực: BLE không biết hướng → điểm đặt góc cố định, có ghi chú; chưa kết nối/chưa có mẫu → không vẽ điểm, hiện "--"
- proximity_screen.dart: chỉ chèn radar lên đầu danh sách + 1 import. Engine/controller/ngưỡng/_StatusCard không đổi
- MỚI test/smart_key_radar_test.dart (4 test widget). CHƯA chạy flutter analyze/test

# Phần XXI — Regen 5 nút (trạng thái KHÓA)
- MỚI features/regen/regen_level_panel.dart (RegenLevelPanel): 5 cột xanh→cam · 5 nút tròn 1–5 (ECO/LIGHT/NORMAL/STRONG/MAX) · dòng "Mức trên xe" · giải thích từng cấp · nút Áp dụng
- KHÓA (spec.verified=false, hiện tại): không mức nào tô sáng, bấm nút → SnackBar nêu lý do, nút "Áp dụng · đã khóa" vô hiệu (key regen_apply_locked), không có "Đọc lại"
- MỞ KHÓA (khi verified=true): chọn → Áp dụng (hộp thoại xác nhận) → RegenController.apply() (cổng an toàn + ghi + đọc lại + so khớp); "Xe xác nhận" chỉ hiện khi currentIndex đã đọc lại từ xe; chống bấm lặp (busy)
- regen_screen.dart: thay _RegenLevelSelector/_LevelButton bằng RegenLevelPanel. Giữ key regen_level_selector / regen_level_btn_i / regen_level_lock_reason. Không đổi RegenController/protocol
- MỚI test/regen_level_panel_test.dart. CHƯA chạy flutter analyze/test

# Phần XXII — Smart Key rút gọn
- proximity_screen.dart: ConsumerWidget → ConsumerStatefulWidget (chỉ để giữ trạng thái mở/đóng); toàn bộ logic, callback, key công tắc/slider giữ nguyên
- Luôn hiện: cảnh báo chưa kết nối · Radar · Thẻ trạng thái · Bật / tắt (mở khóa thông minh, bật xe sẵn, tự động khóa)
- Thu gọn (mặc định đóng): Giới hạn khoảng cách (bật nhanh) · Độ nhạy & xác nhận rời xa · Hiệu chỉnh 1 m + 2 m (tự mở khi đang đo) · Giới hạn cần biết · Nhật ký sự kiện
- Dùng lại OverviewCollapsible từ Trang chủ. Không đổi engine/controller. CHƯA chạy flutter analyze/test

# Phần XXIII — Cài đặt 9 nhóm + Thống kê hành trình Ngày/Tuần/Tháng
- app_settings_screen.dart: nhóm lại theo prompt — Cài đặt giao diện · Dashboard · Smart Key · Regen · Bluetooth · (Đơn vị đo) · Thông báo · Quản lý thiết bị · Thông tin ứng dụng · Phiên bản và bản quyền. Chỉ thêm dòng điều hướng tới route có sẵn (/proximity, /regen, /regen-evidence, /logs); không đổi logic
- MỚI core/trips/trip_stats.dart (thuần Dart) + features/hubs/trip_stats_card.dart: bộ lọc Ngày (7) / Tuần (8) / Tháng (6), tổng km, số chuyến, thời gian, tốc độ TB (km ÷ giờ thật), biểu đồ cột; không có chuyến → trạng thái trống. Gắn vào tab VEHICLE
- MỚI test/trip_stats_test.dart. CHƯA chạy flutter analyze/test/build (sandbox không có Flutter, tải SDK bị chặn)

# Phần XXIV — Header Trang chủ + Skeleton loading
- overview_header.dart: thêm chấm Smart Key (xanh/vàng/đỏ/xám theo SmartKeyView, chạm → /proximity) và chuông thông báo có huy hiệu số cảnh báo; tham số tuỳ chọn nên nơi gọi cũ vẫn hợp lệ. Màn < 400dp dùng biểu tượng Bluetooth gọn
- my_bike_screen.dart: suy ra SmartKeyView từ dữ liệu thật (như màn Smart Key; securityFault=false vì chưa có tín hiệu riêng). Cảnh báo = mã lỗi bộ điều khiển (≠0) + cảnh báo Smart Key; chuông mở bảng liệt kê, rỗng → "Không có cảnh báo". KHÔNG có hộp thư thông báo lưu trữ
- ui/ds/live_state.dart: MỚI SkeletonGrid. Tab VEHICLE và màn Vận hành hiện skeleton khi đã kết nối nhưng chưa có gói dữ liệu đầu (thay "N/A"/vòng xoay); mất kết nối vẫn dùng banner/StateView
- MỚI test/header_skeleton_test.dart (3 test). CHƯA chạy flutter analyze/test/build

# Phần XXV — Lịch sử hoạt động Smart Key + Battery Center Điện/Dòng
- MỚI core/proximity/activity_history.dart: lưu BỀN (SharedPreferences, tối đa 200) các sự kiện thật của ProximityEngine; bỏ sự kiện "zone"; giải mã chịu lỗi. proximity_controller.dart chỉ thêm 1 dòng ghi + 1 import (engine/ngưỡng không đổi)
- MỚI features/proximity/activity_history_screen.dart: danh sách mới→cũ, lọc Mở khóa/Khóa/Lỗi/Hiệu chỉnh/Khác, skeleton khi đang tải, trạng thái trống. Mở từ "Nhật ký sự kiện" trong màn Smart Key
- MỚI features/battery/views/electrical_view.dart: tab "Điện" (Bác sĩ Pin) — điện áp & dòng hiện tại + min/TB/max ~10 phút, 2 biểu đồ lớn, công suất |V×I| ghi rõ là tính toán; dấu dòng chưa xác minh nên không gắn nhãn sạc/xả
- history_view.dart: thêm biểu đồ Dòng điện BMS trung bình theo ngày/tuần/tháng
- MỚI test/activity_history_test.dart. CHƯA chạy flutter analyze/test/build

# Phần XXVI — Lịch sử hành trình trên tab MAP
- MỚI features/home/trip_history_screen.dart: danh sách chuyến (mới→cũ), lọc Hôm nay / Tuần này / Tháng này / Tất cả, tổng số chuyến & km; mỗi dòng có ngày giờ, km, thời gian, tốc độ TB/tối đa; chuyến không có tuyến GPS ghi rõ "Không có dữ liệu tuyến GPS" (không vẽ tuyến giả). Chạm → TripRouteScreen có sẵn (bản đồ + phát lại), không đổi màn đó
- charge_finder_screen.dart: thêm 1 nút "Lịch sử hành trình" vào cụm nút bản đồ (+ 1 import). Logic trạm sạc không đổi
- trip_stats.dart: thêm tripsInCurrentPeriod() + test. CHƯA chạy flutter analyze/test/build
