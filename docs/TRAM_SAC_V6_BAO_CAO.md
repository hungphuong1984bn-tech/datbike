# Báo cáo — chức năng Trạm sạc THBIKE V6

## 1. Nguyên nhân lỗi máy chủ ban đầu (chỉ nêu điều đọc được từ mã)
- `ChargingStationService.fetchNear` (V6) gọi MỘT endpoint duy nhất `https://overpass-api.de/api/interpreter`
  bằng một lần POST, timeout 25 giây, KHÔNG retry, KHÔNG máy chủ dự phòng.
- Mọi lỗi (429/5xx/timeout/DNS/JSON) bị gộp thành một chuỗi; nếu không có cache trong bán kính 15 km thì trả danh sách rỗng.
- Cache chỉ giữ MỘT vùng (lần tìm gần nhất).
- CHƯA xác nhận được mã lỗi thực tế trên máy người dùng (môi trường phân tích không gọi được Overpass). Cần log/ảnh lỗi để kết luận.

## 2. Nguồn dữ liệu đã tích hợp
| Nguồn | Trạng thái |
|---|---|
| `assets/data/datbike_stations.json` (đóng gói) | 1 điểm: Dat Bike Khánh Anh – 116 Nguyễn Văn Cừ, Bồ Đề, Hà Nội — địa chỉ/tọa độ do người dùng cung cấp, người dùng xác nhận có trạm sạc (chưa có xác nhận từ dat.bike); trạng thái hoạt động chưa xác minh |
| OpenStreetMap / Overpass | 3 máy chủ thử lần lượt (cấu hình ở `StationRepository.overpassEndpoints`; chưa kiểm tra sống) |
| Cache cục bộ | Nhiều vùng (tối đa 8), tự nhận cache v2 cũ |
| Đề xuất của người dùng | Lưu cục bộ, luôn "cộng đồng / chờ xác minh" |

Trang chính thức dat.bike/tram-sac-dien chỉ nêu địa chỉ 49B Tú Xương (Q.3, TP.HCM) cho trạm Dat Charge đầu tiên, không có tọa độ/SĐT/giờ;
trang danh sách cửa hàng nạp bằng JavaScript nên chưa lấy được. Các điểm này CHƯA có trong dữ liệu vì thiếu tọa độ xác thực.

## 3. Thêm điểm Dat Bike mới
Thêm bản ghi vào `assets/data/datbike_stations.json` (id, name, lat, lng, address, category=`datBike`, status=`unverified`,
`chargingConfirmed` chỉ `true` khi có xác nhận). Không suy diễn cửa hàng nào có sạc; không tự tạo tọa độ.

## 4. Kiểm thử
Test đơn vị: `test/station_repository_test.dart`, `test/station_proposal_test.dart` (máy chủ ổn, 404/500/429, timeout, retry,
mất mạng, JSON hỏng, trùng lặp, cache nhiều vùng, đề xuất, bộ lọc loại điểm, chuẩn hóa số gọi).
CHƯA chạy (môi trường không có Flutter SDK). CHƯA kiểm thử trên Xiaomi 15T Pro; GPS thật, marker, chỉ đường, gọi điện cần thử trên máy.

## 5. Chưa làm / hạn chế
- Đề xuất chưa đính kèm ảnh (chưa có thư viện chọn ảnh; model đã có trường `photoPath`).
- Duyệt đề xuất làm ngoài app (xuất JSON) vì chưa có máy chủ nhận đề xuất.
- Workflow CI vẫn để Analyze/Test `continue-on-error` như bản gốc: test lỗi không chặn build, phải đọc log.
- Dữ liệu OSM không có trạng thái trực tiếp; điểm OSM luôn "chưa xác minh" trừ khi thẻ nói rõ đóng/tạm ngừng.
