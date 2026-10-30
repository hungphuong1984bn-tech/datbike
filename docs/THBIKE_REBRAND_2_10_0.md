# THBIKE 2.10.0+55 — Tái thương hiệu

Phiên bản: **2.10.0**, Build Number **55** (nâng từ 2.9.0+54). Ngày phát hành ghi trong `lib/core/brand/app_info.dart`.

## Giữ nguyên (theo yêu cầu)
`applicationId`/namespace `vn.mybike.mybike_app`, tên package Dart `mybike_app`, bundle ID iOS, cấu hình ký APK,
giao thức BLE/BMS, logic pin & sạc, tên kênh MethodChannel (`vn.mybike/export`, `vn.datbike/export`).

## Đã đổi
- Tên hiển thị: Android `android:label`, iOS `CFBundleDisplayName`/`CFBundleName`, `MaterialApp.title`, thông báo foreground, mô tả quyền iOS.
- Nguồn thông tin duy nhất: `lib/core/brand/app_info.dart` (có test đối chiếu với `pubspec.yaml`).
- Trang **Cài đặt → Giới thiệu THBIKE** (`lib/features/about/`), danh mục chức năng kèm trạng thái.
- Splash: native (`launch_background.xml` + `splash_logo.png`) và lớp phủ Flutter (`lib/features/splash/`).
- Icon: `python3 tool/make_thbike_icon.py` sinh launcher, adaptive (foreground + monochrome), splash, icon thông báo
  (`ic_stat_thbike`) và bộ AppIcon iOS.
- Thư mục xuất nhật ký: `Downloads/THBIKE_Logs` (trước đây giao diện ghi `DatBikeLogs` nhưng mã native ghi `MyBikeLogs`; nay thống nhất).
- Tên tệp bàn giao APK: `THBIKE-vX.Y.Z.apk`.

## Còn giữ tên "Dat Bike"
Chỉ khi nói về **xe/hãng xe thật** hoặc dữ liệu giao thức: tên mẫu xe do xe quảng bá (`Dat Bike Quantum S1`),
mô tả trong Firmware Lab, hướng dẫn đối chiếu với "app gốc", chú thích mã nguồn, dữ liệu mẫu trong test.

## Chưa kiểm chứng trong môi trường tạo bản sửa này
Không có Flutter SDK/thiết bị: chưa chạy `flutter analyze`, `flutter test`, build APK hay cài lên điện thoại.
Cần chạy các lệnh đó (hoặc CI) trước khi phát hành.
