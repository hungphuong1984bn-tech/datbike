# Tab Tổng quan — thiết kế lại (Premium EV)

Bố cục (trên xuống): Header → Hero (ảnh xe · tốc độ · SOC · quãng đường) → Trạng thái xe →
Điều khiển nhanh → Thông số kỹ thuật → Năng lượng → Trung tâm điều khiển (Grab/ECE/Regen) →
Hành trình → Trạm sạc gần nhất.

File mới: overview_header, overview_metrics, overview_control_summary, overview_station.
File sửa: home_hero (bố cục mới), overview_status (thêm OverviewStatusStrip),
overview_energy (cờ showVehicleInfo), my_bike_screen (ghép lại build, nút nhanh co theo bề rộng),
charging_station_service (thêm loadLastCache, chỉ đọc).

Quy tắc dữ liệu giữ nguyên: không số mẫu; thiếu → "--"; cũ → nhãn "Dữ liệu cũ"; ước tính → "Ước tính".
Thẻ Grab/ECE/Regen chỉ hiển thị, không gửi lệnh, không tự đồng bộ khi mở tab.
Trạm sạc: chỉ dùng cache tìm kiếm đã lưu; không xin quyền vị trí; không số cổng trống/giá.
