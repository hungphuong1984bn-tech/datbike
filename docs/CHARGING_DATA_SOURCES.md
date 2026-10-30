# Nguồn dữ liệu Trung tâm tìm kiếm trạm sạc

## Đã tích hợp
| Chức năng | Nguồn | Ghi chú |
|---|---|---|
| Trạm sạc | OpenStreetMap qua Overpass API (`amenity=charging_station`) | Cộng đồng nhập; không có giá, không có tình trạng cổng trực tiếp. Giới hạn 150 phần tử/lần tải. |
| Tìm địa điểm / tỉnh thành | Nominatim (OSM) | Chỉ gọi khi người dùng bấm tìm (không tự hoàn thành); tối đa 1 yêu cầu/giây, có User-Agent. |
| Tuyến đường | OSRM demo công cộng, profile ô tô | Không đảm bảo dịch vụ; thời gian/tuyến chỉ để tham khảo cho xe máy. |
| Bản đồ nền | Ô OSM (OSM-FR) có cache offline sẵn của app | Dùng nhiều/thương mại cần nhà cung cấp tile riêng. |

## Chưa tích hợp (cần hợp đồng/khóa API — chưa xác minh điều khoản, hãy kiểm tra trước khi dùng)
Google Places / Mapbox / HERE (giá + giới hạn theo gói; dữ liệu trạm EV không đầy đủ tại VN),
Open Charge Map (miễn phí, độ phủ VN hạn chế), API của nhà vận hành (VinFast, Selex, …).

## Kiến trúc mở rộng
`ChargingStation` đã có `source`, `status`, `updatedAt`. Để thêm nguồn: viết hàm trả `List<ChargingStation>`
(đặt `source` đúng tên nguồn, chỉ đặt `status: active` khi nguồn xác nhận trực tiếp), rồi gộp vào danh sách
trong `ChargingStationService.fetchNear`. Chưa có lớp trừu tượng nhiều nguồn/khử trùng lặp — việc cần làm khi có nguồn thứ hai.
