# Quy trình ký bản Release THBIKE

## Tình trạng trước thay đổi
- `build.gradle.kts` ký Release bằng **debug keystore**; repo không có keystore nào.
- Build chạy trên GitHub Actions nên debug key do runner tự sinh — **chữ ký APK có thể khác nhau giữa các lần build** (cần xác minh bằng `apksigner verify --print-certs` trên các APK đã phát hành).
- Hệ quả: APK từ CI không chắc cập nhật đè được lên bản cũ.

## Quy trình mới
1. Chạy **một lần** trên máy bạn: `tool/make_release_keystore.sh` → tạo `secrets/thbike-release.jks` (đã nằm trong `.gitignore`) và in ra 5 giá trị.
2. **Sao lưu file `.jks` + mật khẩu ở nơi an toàn, ngoài Git.** Mất khóa = không thể cập nhật app đã cài.
3. Thêm GitHub Secrets (Settings → Secrets and variables → Actions):
   `THBIKE_KEYSTORE_BASE64`, `THBIKE_STORE_PASSWORD`, `THBIKE_KEY_ALIAS`, `THBIKE_KEY_PASSWORD`, `THBIKE_CERT_SHA256`.
4. CI (`build_android.yml`) khi build release: dựng `android/key.properties` + `release.jks` từ Secrets, build, chạy `apksigner verify`, **so dấu vân tay chứng chỉ với `THBIKE_CERT_SHA256`** (lệch hoặc thiếu → dừng), tạo `.sha256` và `BUILD_REPORT.md`, rồi xóa khóa khỏi runner.
5. Build debug (chạy tay, chọn `debug`) không cần khóa riêng.
6. Máy dev không có `key.properties`: Release rơi về debug key kèm cảnh báo (chỉ thử nghiệm). CI đặt `THBIKE_REQUIRE_RELEASE_SIGNING=true` nên **không bao giờ** rơi về debug key.

## ⚠ Lần chuyển khóa đầu tiên — một lần duy nhất
Khóa mới KHÔNG thể trùng chữ ký debug cũ (do runner sinh, không có bản lưu). Vì vậy bản đầu tiên ký bằng khóa mới **không cài đè được** bản đang có trên điện thoại; Android sẽ yêu cầu gỡ app trước.
Gỡ app xóa dữ liệu cục bộ (lịch sử sạc, lịch sử pin, cài đặt, trạm yêu thích). Hiện app **chưa có chức năng xuất/phục hồi dữ liệu** (dự kiến Giai đoạn 5E).
Khuyến nghị: chỉ chuyển khóa sau khi có tính năng sao lưu, hoặc chấp nhận mất dữ liệu cục bộ. Từ bản có khóa mới trở đi, mọi bản cập nhật cài đè bình thường.
Không đổi `applicationId` (`vn.mybike.mybike_app`).
