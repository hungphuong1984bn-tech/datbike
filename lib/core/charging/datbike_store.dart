// Cửa hàng / dịch vụ Dat Bike (dữ liệu đóng gói assets/data/datbike_stores.json).
//
// Trung thực về dữ liệu:
//  • Danh sách do người dùng cung cấp: địa chỉ, hotline, giờ bán hàng/kỹ thuật.
//  • KHÔNG có tọa độ → không vẽ lên bản đồ bằng tọa độ tự đoán; mở Google Maps bằng địa chỉ.
//  • KHÔNG suy diễn cửa hàng nào có trạm sạc (chargingConfirmed chỉ ở datbike_stations.json).

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class DatBikeStore {
  final String id;
  final String name;
  final String address;
  final String province;
  final List<String> phones;
  final String hours;
  final bool salesOnly;

  const DatBikeStore({
    required this.id,
    required this.name,
    required this.address,
    required this.province,
    required this.phones,
    required this.hours,
    this.salesOnly = false,
  });

  factory DatBikeStore.fromJson(Map<String, dynamic> j) => DatBikeStore(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? 'Cửa hàng Dat Bike',
        address: (j['address'] as String?) ?? '',
        province: (j['province'] as String?) ?? '',
        phones: [
          for (final p in (j['phones'] as List? ?? const []))
            if ('$p'.trim().isNotEmpty) '$p'.trim(),
        ],
        hours: (j['hours'] as String?) ?? '',
        salesOnly: j['salesOnly'] == true,
      );

  /// Liên kết tìm kiếm Google Maps theo "tên + địa chỉ" (không cần tọa độ, không cần API key).
  Uri get mapsSearchUri => Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$name, $address',
      });
}

class DatBikeStoreRepository {
  DatBikeStoreRepository._();

  static const String asset = 'assets/data/datbike_stores.json';

  /// Phân tích JSON; bỏ qua phần tử hỏng. Hàm thuần.
  static List<DatBikeStore> parse(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['stores'] is! List) return const [];
    final out = <DatBikeStore>[];
    for (final e in j['stores'] as List) {
      if (e is! Map) continue;
      final s = DatBikeStore.fromJson(Map<String, dynamic>.from(e));
      if (s.address.isEmpty) continue;
      out.add(s);
    }
    return out;
  }

  static Future<List<DatBikeStore>> load() async {
    try {
      return parse(await rootBundle.loadString(asset));
    } catch (_) {
      return const [];
    }
  }

  /// Danh sách tỉnh/thành, sắp theo số cửa hàng giảm dần. Hàm thuần.
  static List<String> provinces(Iterable<DatBikeStore> all) {
    final count = <String, int>{};
    for (final s in all) {
      if (s.province.isEmpty) continue;
      count[s.province] = (count[s.province] ?? 0) + 1;
    }
    final keys = count.keys.toList()
      ..sort((a, b) {
        final c = count[b]!.compareTo(count[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return keys;
  }

  static String _fold(String s) {
    const from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Lọc theo tỉnh/thành (null = tất cả) và từ khóa (tên, địa chỉ, hotline; không phân biệt dấu). Hàm thuần.
  static List<DatBikeStore> filter(
    Iterable<DatBikeStore> all, {
    String? province,
    String query = '',
  }) {
    final q = _fold(query.trim());
    return [
      for (final s in all)
        if ((province == null || s.province == province) &&
            (q.isEmpty || _fold('${s.name} ${s.address} ${s.phones.join(' ')}').contains(q)))
          s,
    ];
  }
}
