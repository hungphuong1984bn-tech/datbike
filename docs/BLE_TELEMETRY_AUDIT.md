# Kiểm tra BLE & Telemetry (2.11.1)

## Đã có sẵn, đạt
- Mutex `_establishBusy`: 1 handshake/lúc; `connect()` chờ restore/reconnect xong rồi mới chạy.
- Debounce sự kiện disconnect trùng (`_reconnectPending`).
- `data_field.dart` đã định nghĩa nguồn / thời điểm / hợp lệ / độ mới cho từng trường; nguồn `cache` không bao giờ là "trực tiếp".
- Tắt nguồn đã chặn khi telemetry cũ; telemetry "không hợp lý" bị loại, không cập nhật mốc thời gian.

## Đã sửa
1. Hàng đợi GATT: thêm trần 15 s/thao tác (trước đây 1 thao tác treo chặn mọi lệnh sau nó), và xả hàng đợi khi mất link/teardown (lệnh của link cũ không chạy nhầm lên link mới).
2. Poll dashboard + đọc pin không còn xếp chồng vào hàng đợi khi link chậm.
3. Re-auth do telemetry hỏng giới hạn 1 lần/30 s (chống bão xác thực).
4. Cổng an toàn: khóa an toàn (thủ công), khóa trong luồng khóa, và còi tìm xe nay từ chối khi chưa có khung tốc độ mới (trước đây dùng tốc độ cũ làm tốc độ hiện tại). Luồng tự khóa đã tự kiểm tra tốc độ nên không bị chặn thêm.
5. Mất link → xóa mốc thời gian telemetry; thêm `telemetryFields` (từng trường có nguồn/thời điểm/hợp lệ; chưa có khung của kết nối hiện tại thì toàn bộ "chưa có dữ liệu").

## Không làm (chưa có bằng chứng kỹ thuật / cần thiết bị thật)
- Không thêm UUID/characteristic/lệnh/trường mới.
- Không rút ngắn thời gian kết nối: các mốc thời gian hiện tại chưa có số đo từ xe thật để chứng minh có thể giảm an toàn. Dùng log `connect_*` hiện có để đo trước.
- Không đổi chu kỳ poll 700 ms (`Gatt.dashboardPollMs`) khi chưa có dữ liệu đo.
- Cập nhật lạc quan sau lệnh bật/tắt (đổi `curTele.state` trực tiếp) vẫn còn; nên thay bằng chờ khung telemetry xác nhận.
