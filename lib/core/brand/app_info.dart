// Nhận diện & thông tin phát hành THBIKE — NGUỒN DUY NHẤT trong mã Dart.
//
// Các giá trị phiên bản PHẢI khớp `version:` trong pubspec.yaml
// (dạng  <kAppVersion>+<kAppBuildNumber>). test/brand_info_test.dart đọc
// pubspec.yaml và so khớp để không bao giờ lệch.

import 'dart:io' show Platform;

const String kAppName = 'THBIKE';
const String kAppTagline = 'Ứng dụng xe điện thông minh';
const String kDeveloperName = 'Vũ Thái Hùng';
const String kCopyright = '© 2026 Vũ Thái Hùng. All Rights Reserved.';

/// Phiên bản hiển thị (không có tiền tố "v").
const String kAppVersion = '2.10.0';

/// Build Number (phần sau dấu + trong pubspec.yaml).
const int kAppBuildNumber = 55;

/// Ngày phát hành bản này (ISO yyyy-MM-dd) — cập nhật mỗi lần phát hành.
const String kAppReleaseDate = '2026-10-30';

/// Giữ tương thích với mã cũ đang dùng 'vX.Y.Z'.
const String kAppVersionName = 'v$kAppVersion';

/// Chuỗi dựng dùng trong log/chẩn đoán.
const String kAppBuildTag = '20261030-v$kAppVersion+$kAppBuildNumber';

/// Ngày phát hành dạng dd/MM/yyyy cho giao diện.
String get appReleaseDateVi {
  final p = kAppReleaseDate.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : kAppReleaseDate;
}

/// Nền tảng đang chạy.
String get appPlatformName {
  try {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  } catch (_) {
    return 'Không xác định';
  }
}
