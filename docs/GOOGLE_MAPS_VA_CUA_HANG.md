# Google Maps + Cửa hàng Dat Bike (màn Trạm sạc)

## Đã làm
- Màn Tìm trạm sạc (`charge_finder_screen.dart`) dùng `google_maps_flutter` thay `flutter_map`.
- Màn mới `store_list_screen.dart`: 70 cửa hàng (assets/data/datbike_stores.json), lọc tỉnh/thành, tìm kiếm không dấu, gọi hotline, mở Google Maps theo địa chỉ, chép địa chỉ. Nút `storefront` trên thanh tiêu đề màn trạm sạc.
- Test: `test/datbike_store_test.dart`.

## Cấu hình khóa (bắt buộc để bản đồ hiện)
Thêm vào `android/local.properties` (không commit) hoặc biến môi trường:
`GOOGLE_MAPS_API_KEY=...` — bật "Maps SDK for Android" trong Google Cloud, nên giới hạn khóa theo package `vn.mybike.mybike_app` + SHA-1.
CI: đặt secret cùng tên. iOS CHƯA cấu hình (cần `GMSServices.provideAPIKey` trong AppDelegate).

## Giới hạn trung thực
- Danh sách cửa hàng KHÔNG có tọa độ → không hiện ghim trên bản đồ trong app; mở Google Maps ngoài theo tên+địa chỉ. Muốn ghim: bổ sung lat/lng xác nhận vào JSON.
- Không suy diễn cửa hàng nào có trạm sạc (`chargingConfirmed` chỉ ở datbike_stations.json).
- Ghim trạm dùng marker mặc định của Google tô theo loại (xanh lá = Dat Bike, cyan = đối tác, tím = cộng đồng, vàng = đang chọn); mất hiển thị icon tùy biến + hướng mũi tên vị trí cũ (dùng chấm xanh của Google).
- Các màn khác (hành trình, cockpit, bản đồ offline) vẫn dùng flutter_map; chưa chuyển.
- Chưa chạy `flutter pub get/analyze/test` (môi trường không có Flutter/mạng).
