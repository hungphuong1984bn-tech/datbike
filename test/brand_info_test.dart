import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/brand/app_info.dart';
import 'package:mybike_app/features/about/feature_catalog.dart';

void main() {
  test('Phiên bản trong app khớp pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final v = line.substring('version:'.length).trim().split('+');
    expect(v[0], kAppVersion);
    expect(int.parse(v[1]), kAppBuildNumber);
  });

  test('Thông tin thương hiệu', () {
    expect(kAppName, 'THBIKE');
    expect(kDeveloperName, 'Vũ Thái Hùng');
    expect(kCopyright, '© 2026 Vũ Thái Hùng. All Rights Reserved.');
    expect(appReleaseDateVi, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
  });

  test('Tên hiển thị Android/iOS là THBIKE, applicationId giữ nguyên', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="THBIKE"'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "vn.mybike.mybike_app"'));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleDisplayName</key>\n\t<string>THBIKE</string>'));
  });

  test('Danh mục chức năng: đủ nhóm A–G, không trống', () {
    expect(kFeatureCatalog.map((g) => g.code).toList(),
        ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
    for (final g in kFeatureCatalog) {
      expect(g.items, isNotEmpty);
    }
    // Chức năng chưa có phải được ghi rõ là chưa hỗ trợ.
    final unsupported = kFeatureCatalog
        .expand((g) => g.items)
        .where((i) => i.status == FeatureStatus.unsupported)
        .map((i) => i.title)
        .toList();
    expect(unsupported, contains('Điều khiển cân bằng cell'));
    expect(unsupported, contains('Xác minh tương thích trạm với xe'));
  });
}
