// Lập tuyến đường bằng OSRM (máy chủ demo công cộng, profile "driving").
//
// GIỚI HẠN (hiển thị cho người dùng):
//  • Cần Internet; máy chủ demo có giới hạn tải và không đảm bảo dịch vụ.
//  • Profile ô tô, KHÔNG phải xe máy: tuyến/thời gian chỉ mang tính tham khảo
//    (có thể đi vào đường xe máy không được phép, hoặc bỏ lỡ lối tắt xe máy).
//  • Chỉ dẫn rẽ là văn bản, không có giọng nói; tự dẫn lại chỉ khi bấm "Lập lại tuyến".

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteStep {
  final String instruction;
  final double distanceM;
  final LatLng location; // điểm thực hiện thao tác
  const RouteStep(this.instruction, this.distanceM, this.location);
}

class RouteResult {
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
  final List<RouteStep> steps;
  const RouteResult(this.points, this.distanceM, this.durationS, this.steps);

  double get distanceKm => distanceM / 1000.0;
}

class RouteService {
  RouteService._();

  static const String _base = 'https://router.project-osrm.org/route/v1/driving';

  static Uri buildUri(List<LatLng> waypoints) {
    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    return Uri.parse('$_base/$coords?overview=full&geometries=geojson&steps=true');
  }

  static String viInstruction(String type, String? modifier, String? name) {
    String dir() => switch (modifier) {
          'left' => 'rẽ trái',
          'right' => 'rẽ phải',
          'slight left' => 'chếch sang trái',
          'slight right' => 'chếch sang phải',
          'sharp left' => 'ngoặt gấp sang trái',
          'sharp right' => 'ngoặt gấp sang phải',
          'uturn' => 'quay đầu',
          _ => 'đi thẳng',
        };
    final road = (name != null && name.isNotEmpty) ? ' vào $name' : '';
    return switch (type) {
      'depart' => 'Xuất phát$road',
      'arrive' => 'Đến nơi',
      'roundabout' || 'rotary' => 'Vào vòng xuyến$road',
      'exit roundabout' || 'exit rotary' => 'Ra khỏi vòng xuyến$road',
      'continue' => 'Tiếp tục${modifier == null ? '' : ' ${dir()}'}$road',
      _ => '${dir()[0].toUpperCase()}${dir().substring(1)}$road',
    };
  }

  /// Phân tích JSON của OSRM; trả về null nếu không có tuyến. Hàm thuần.
  static RouteResult? parse(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['code'] != 'Ok' || j['routes'] is! List || (j['routes'] as List).isEmpty) {
      return null;
    }
    final r = (j['routes'] as List).first as Map;
    final coords = (r['geometry']?['coordinates'] as List?) ?? const [];
    final points = <LatLng>[
      for (final c in coords)
        if (c is List && c.length >= 2) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    if (points.length < 2) return null;
    final steps = <RouteStep>[];
    for (final leg in (r['legs'] as List? ?? const [])) {
      for (final s in ((leg as Map)['steps'] as List? ?? const [])) {
        final m = (s as Map)['maneuver'] as Map?;
        final loc = m?['location'] as List?;
        if (m == null || loc == null || loc.length < 2) continue;
        steps.add(RouteStep(
          viInstruction('${m['type']}', m['modifier'] as String?, s['name'] as String?),
          (s['distance'] as num?)?.toDouble() ?? 0,
          LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
        ));
      }
    }
    return RouteResult(
      points,
      (r['distance'] as num?)?.toDouble() ?? 0,
      (r['duration'] as num?)?.toDouble() ?? 0,
      steps,
    );
  }

  /// Lập tuyến qua danh sách điểm (>= 2). Ném Exception có thông điệp tiếng Việt khi lỗi.
  static Future<RouteResult> fetch(List<LatLng> waypoints) async {
    if (waypoints.length < 2) throw Exception('Cần ít nhất điểm đi và điểm đến.');
    try {
      final res = await http.get(buildUri(waypoints)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('Máy chủ lập tuyến trả lỗi ${res.statusCode}.');
      }
      final r = parse(utf8.decode(res.bodyBytes));
      if (r == null) throw Exception('Không tìm được tuyến đường giữa các điểm này.');
      return r;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Không lập được tuyến: $e');
    }
  }
}
