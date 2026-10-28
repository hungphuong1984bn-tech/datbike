// Xuất hành trình ra GPX 1.1. CHỈ dùng điểm GPS đã ghi thật — không bao giờ
// xuất tuyến mô phỏng. Không phụ thuộc package ngoài.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_gps_point.dart';

class GpxExporter {
  GpxExporter._();

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Dựng chuỗi GPX. Trả về null nếu không có điểm nào để xuất.
  static String? build({
    required String name,
    required List<TripGpsPoint> points,
  }) {
    if (points.isEmpty) return null;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="My Bike App" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata><name>${_esc(name)}</name>'
          '<time>${points.first.timestamp.toUtc().toIso8601String()}</time></metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_esc(name)}</name>')
      ..writeln('    <trkseg>');
    for (final p in points) {
      b.write('      <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lng.toStringAsFixed(6)}">');
      if (p.altitude != null) b.write('<ele>${p.altitude!.toStringAsFixed(1)}</ele>');
      b.write('<time>${p.timestamp.toUtc().toIso8601String()}</time>');
      b.writeln('</trkpt>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return b.toString();
  }

  /// Ghi file GPX vào thư mục tạm rồi mở hộp thoại chia sẻ.
  /// Trả về thông báo cho người dùng (thành công hoặc lý do không xuất được).
  static Future<String> exportAndShare({
    required String name,
    required List<TripGpsPoint> points,
  }) async {
    final xml = build(name: name, points: points);
    if (xml == null) {
      return 'Chuyến đi này không có điểm GPS đã ghi nên không thể xuất GPX.';
    }
    try {
      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/$safe.gpx');
      await file.writeAsString(xml);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/gpx+xml')], text: name),
      );
      return 'Đã tạo file GPX (${points.length} điểm).';
    } catch (e) {
      return 'Xuất GPX thất bại: $e';
    }
  }
}
