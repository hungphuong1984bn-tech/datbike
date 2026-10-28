# ⚡ My Bike App

Ứng dụng mã nguồn mở (Open Source) điều khiển xe điện thông minh và bảng đồng hồ Cockpit HUD thời gian thực, được phát triển bằng Flutter.

---

## 📱 Tính Năng Nổi Bật

- **Giao diện Cockpit HUD Chuyên Nghiệp**: Đồng hồ tốc độ kỹ thuật số, đo công suất tiêu thụ/tái tạo (kW), điện áp pin, dòng xả, nhiệt độ và quãng đường (Trip ODO) hiển thị mượt mà ở cả chế độ dọc và xoay ngang.
- **Điều Khiển Xe Thông Minh**: Bật/tắt nguồn xe từ xa, tìm xe trong bãi (nháy đèn & hú còi định vị an toàn).
- **Tự Động Khóa Khi Rời Xa (Walk-Away Proximity Lock)**: Tự động tắt máy và cảnh báo âm thanh khi phát hiện người dùng mang điện thoại rời xa xe dựa trên cường độ sóng BLE RSSI.
- **Bảo Vệ Pin Điện Thoại Tuyệt Đối**: Thuật toán ngắt kết nối tự động sau 5 lần thử với exponential backoff (2s, 4s, 8s, 16s, 30s) — giải phóng 100% tài nguyên CPU và radio Bluetooth khi bạn rời xe.
- **Kiến Trúc Bảo Mật Cao Cấp (SecureKeyManager)**:
  - **XOR Sharding & Runtime Masking**: Toàn bộ Token, Key và Seed xác thực xe được mã hóa phân mảnh, không lưu chuỗi tĩnh thô trong mã nhị phân `.so`, vô hiệu hóa các công cụ quét chuỗi hoặc dịch ngược (Decompiler).
  - **Phần Cứng Keystore/Keychain**: Mã PIN xe và Token phiên được mã hóa an toàn bằng chip bảo mật phần cứng AES-256-GCM qua `flutter_secure_storage`.

---

## 🛠️ Yêu Cầu Môi Trường (Prerequisites)

- **Flutter SDK**: `>= 3.13.2` (Khuyến nghị Flutter 3.24 trở lên).
- **Dart SDK**: `>= 3.13.2`.
- **Android**: Android Studio với Android SDK (minSdk 26 — Android 8.0+, compileSdk 34+), Java 17.
- **iOS**: macOS với Xcode 15+, CocoaPods (hỗ trợ iOS 13.0+).

---

## 🚀 Hướng Dẫn Cài Đặt & Build Ứng Dụng

### 1. Lấy mã nguồn & Cài đặt dependencies

```bash
# Clone repository về máy
git clone https://github.com/ducmandev/mybike_app.git
cd mybike_app

# Tải và cài đặt các package phụ thuộc
flutter pub get
```

### 2. Phân tích mã nguồn

Kiểm tra cú pháp và phân tích tĩnh:

```bash
flutter analyze
```

### 3. Chạy ứng dụng trực tiếp (Development Mode)

Kết nối điện thoại bật chế độ USB Debugging:

```bash
flutter run
```

---

### 4. Build Ứng Dụng Cho Android (APK & App Bundle)

#### a. Build file cài đặt Debug APK (Dùng thử nghiệm nhanh)
```bash
flutter build apk --debug
```
*File xuất ra tại: `build/app/outputs/flutter-apk/app-debug.apk`*

#### b. Build file Release APK Tối Ưu (Production)
Tối ưu hóa dung lượng và làm rối mã nhị phân (Obfuscation):
```bash
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
```
*File xuất ra tại: `build/app/outputs/flutter-apk/app-release.apk`*

#### c. Build file APK phân tách theo kiến trúc chip (Giảm 50% dung lượng file cài)
```bash
flutter build apk --split-per-abi --release
```
*Tạo ra các file APK chuyên biệt cho từng loại chip: `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`.*

#### d. Build Android App Bundle (.aab) để phát hành Google Play
```bash
flutter build appbundle --release
```

---

### 5. Build Ứng Dụng Cho iOS

> **Lưu ý**: Cần máy tính chạy macOS và đã cài đặt Xcode.

```bash
# Cài đặt CocoaPods
cd ios
pod install
cd ..

# Build bản Release IPA
flutter build ipa --release
```

---

## ☁️ Build APK trên GitHub (không cần cài Flutter)

1. Đẩy toàn bộ mã nguồn lên một repo GitHub (nhánh `main`).
2. Vào tab **Actions → Build Android APK → Run workflow** (chọn `release` hoặc `debug`). Mỗi lần push lên `main` cũng tự build.
3. Khi chạy xong, mở lần chạy đó → mục **Artifacts → MyBike-Android-APK** → tải về. Với Xiaomi 15T Pro (arm64) dùng file có đuôi `arm64-v8a-release.apk`.
4. Muốn có GitHub Release kèm APK: tạo tag, ví dụ `git tag v2.7.0 && git push origin v2.7.0`.

Lưu ý: bản release hiện ký bằng khóa debug (đủ để cài thử/sideload). Bước *Analyze* và *Unit tests* chỉ cảnh báo, không chặn build — hãy đọc log của chúng.

## 🧭 Đồng hồ lái xe dọc (v2.7.0)

Mở từ biểu tượng đồng hồ trên thanh trên của màn Dashboard (route `/cluster`). Khóa Portrait mặc định; chỉ xoay ngang khi bật "Cho phép xoay ngang". Có 4 giao diện (Sport/Minimal/Touring/Original), bật/tắt và kéo sắp xếp ô dữ liệu, màu nhấn/nền/cỡ chữ, ngày-đêm, giữ sáng, toàn màn hình, kết hợp bản đồ, phân biệt tốc độ XE (BLE) và GPS, đánh dấu dữ liệu cũ. Đồng hồ **không có nút điều khiển xe**. Cấu hình lưu cục bộ (`cluster_config_v1`).

## 🔌 Trạm sạc & Dẫn đường (v2.8.0)

Mở từ biểu tượng trạm sạc trên thanh trên của Dashboard (route `/charge-finder`): GPS hiện tại, trạm sạc quanh bạn (OpenStreetMap/Overpass), lập tuyến (OSRM demo), chạm giữ bản đồ để chọn điểm đến — nếu pin ước tính không đủ, app đề xuất trạm gần tuyến xa nhất mà vẫn tới được với pin ≥ 15% và lập lại tuyến qua trạm đó. Chỉ dẫn rẽ dạng văn bản. Pin đến nơi/tầm đi luôn là **ước tính**, kèm cơ sở tính; chỉ tính khi có % pin trực tiếp (< 4 giây) từ xe. Giới hạn: cần Internet (trạm có lưu cache lần cuối), tuyến theo profile ô tô, không giọng nói, không xác minh trạm tương thích Datbike.

## 🛡️ Thay đổi an toàn (v2.8.0)

- Bỏ ngoại lệ "chống trộm tắt xe khi đang chạy": mọi tự động tắt/khóa (rời xa, chống trộm) giờ **không bao giờ** chạy khi tốc độ > 0,5 km/h hoặc khi chưa có telemetry mới (< 4 giây).
- Tắt/khóa xe thủ công bị chặn nếu chưa có dữ liệu tốc độ mới (không còn coi "chưa biết tốc độ" là 0).

---

## ⚠️ ĐIỀU KHOẢN SỬ DỤNG & TUYÊN BỐ MIỄN TRỪ TRÁCH NHIỆM (DISCLAIMER)

> ### 🔴 QUAN TRỌNG: VUI LÒNG ĐỌC KỸ TRƯỚC KHI SỬ DỤNG
>
> 1. **Dự Án Cộng Đồng Phi Lợi Nhuận (Open Source)**:  
>    Dự án này là mã nguồn mở độc lập, do cộng đồng tự phát triển cho mục đích nghiên cứu, học tập kỹ thuật Bluetooth Low Energy (BLE) và nâng cao trải nghiệm cá nhân. Ứng dụng **không phải** là sản phẩm chính thức của bất kỳ hãng sản xuất xe máy điện nào.
>
> 2. **Tự Chịu Rủi Ro (Use at Your Own Risk)**:  
>    - Ứng dụng can thiệp và tương tác trực tiếp với bộ điều khiển trung tâm (ECU/BMS) của xe qua sóng Bluetooth.  
>    - Mọi thao tác điều khiển — bao gồm bật/tắt nguồn, khóa xe, tìm xe hú còi, điều chỉnh khoảng cách — **đều tiềm ẩn rủi ro kỹ thuật, an toàn vận hành, an toàn giao thông và có thể ảnh hưởng đến chính sách bảo hành của xe**.  
>    - **Người sử dụng và bất kỳ ai biên dịch mã nguồn này phải tự chịu 100% trách nhiệm** đối với phương tiện, thiết bị di động, an toàn tài sản và tính mạng của bản thân cũng như người tham gia giao thông.
>
> 3. **Miễn Trừ Trách Nhiệm Pháp Lý**:  
>    Tác giả, các cá nhân đóng góp mã nguồn (contributors) và bất kỳ bên liên quan nào **hoàn toàn KHÔNG chịu bất kỳ trách nhiệm pháp lý, bồi thường trực tiếp hay gián tiếp** đối với bất kỳ sự cố, hỏng hóc thiết bị, lỗi phần mềm, tai nạn giao thông, tổn thất dữ liệu hoặc thiệt hại vật chất nào phát sinh từ việc sử dụng hoặc không thể sử dụng phần mềm này.
>
> 4. **Khuyến Cáo An Toàn Bắt Buộc**:  
>    - **Tuyệt đối không** thao tác bấm điện thoại hoặc nhìn màn hình ứng dụng khi đang điều khiển phương tiện di chuyển trên đường.  
>    - Luôn mang theo thẻ từ NFC hoặc chìa khóa dự phòng vật lý để phòng ngừa tình huống điện thoại hết pin hoặc mất kết nối Bluetooth.

---

## 📄 Giấy Phép (License)

Dự án được phân phối dưới giấy phép mã nguồn mở **MIT License**. Bạn được tự do sử dụng, chỉnh sửa và phân phối theo các điều khoản của giấy phép này.
