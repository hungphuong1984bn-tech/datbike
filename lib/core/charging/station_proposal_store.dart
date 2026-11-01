// Đề xuất điểm sạc MỚI của người dùng (cộng đồng). Lưu cục bộ, luôn ở trạng thái
// "chờ xác minh" — không bao giờ tự gắn nhãn Dat Bike chính thức, không tự "đang hoạt động".
//
// Kiểm duyệt: app chưa có máy chủ nhận đề xuất, nên bước duyệt do người quản trị làm bên ngoài:
// xuất JSON ([exportJson]) → đối chiếu nguồn chính thức → đưa vào assets/data/datbike_stations.json
// khi đã xác minh. Chống trùng: [checkDuplicate] so với dữ liệu đang có và các đề xuất trước đó.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/charging_station_service.dart';
import 'station_repository.dart';

enum ProposalState { pending, rejectedDuplicate }

class StationProposal {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String? phone;
  final String? note;

  /// Đường dẫn ảnh trên máy (nếu có). Ảnh chưa được tải lên đâu cả.
  final String? photoPath;
  final DateTime createdAt;
  final ProposalState state;

  const StationProposal({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.phone,
    this.note,
    this.photoPath,
    this.state = ProposalState.pending,
  });

  /// Luôn là điểm cộng đồng, chưa xác minh, chưa xác nhận có sạc.
  ChargingStation toStation() => ChargingStation(
        id: id,
        name: name,
        lat: lat,
        lng: lng,
        address: address,
        phone: phone,
        status: StationStatus.unverified,
        source: 'Người dùng đề xuất (chờ xác minh)',
        category: StationCategory.community,
        chargingConfirmed: false,
        updatedAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        if (phone != null) 'phone': phone,
        if (note != null) 'note': note,
        if (photoPath != null) 'photoPath': photoPath,
        'createdAt': createdAt.toIso8601String(),
        'state': state.name,
      };

  static StationProposal? fromJson(Object? o) {
    if (o is! Map) return null;
    final lat = o['lat'], lng = o['lng'];
    if (lat is! num || lng is! num) return null;
    return StationProposal(
      id: '${o['id']}',
      name: '${o['name'] ?? ''}',
      address: '${o['address'] ?? ''}',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      phone: o['phone'] as String?,
      note: o['note'] as String?,
      photoPath: o['photoPath'] as String?,
      createdAt: DateTime.tryParse('${o['createdAt']}') ?? DateTime.now(),
      state: ProposalState.values.firstWhere((s) => s.name == o['state'], orElse: () => ProposalState.pending),
    );
  }
}

class ProposalValidation {
  final String? error;
  const ProposalValidation(this.error);
  bool get ok => error == null;
}

class StationProposalStore {
  StationProposalStore._();

  static const _key = 'station_proposals_v1';

  /// Kiểm tra dữ liệu nhập. Hàm thuần. Tọa độ phải do người dùng nhập/lấy từ GPS, không tự điền.
  static ProposalValidation validate({
    required String name,
    required String address,
    required double? lat,
    required double? lng,
  }) {
    if (name.trim().length < 3) return const ProposalValidation('Nhập tên điểm sạc (ít nhất 3 ký tự).');
    if (address.trim().length < 5) return const ProposalValidation('Nhập địa chỉ điểm sạc.');
    if (lat == null || lng == null) return const ProposalValidation('Nhập tọa độ hợp lệ (vĩ độ, kinh độ).');
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return const ProposalValidation('Tọa độ nằm ngoài phạm vi hợp lệ.');
    }
    return const ProposalValidation(null);
  }

  /// Phân tích "21.04831, 105.881862" hoặc "21,04831 105,881862". null nếu không đọc được.
  static ({double lat, double lng})? parseLatLng(String text) {
    final nums = RegExp(r'-?\d+(?:[.,]\d+)?').allMatches(text).map((m) => m.group(0)!).toList();
    if (nums.length != 2) return null;
    // "21,04831 105,881862": dấu phẩy là thập phân khi hai số tách bằng khoảng trắng.
    final a = double.tryParse(nums[0].replaceAll(',', '.'));
    final b = double.tryParse(nums[1].replaceAll(',', '.'));
    if (a == null || b == null) return null;
    return (lat: a, lng: b);
  }

  static Future<List<StationProposal>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return [for (final e in l) ?StationProposal.fromJson(e)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<StationProposal> l) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final p in l) p.toJson()]));
    } catch (_) {}
  }

  /// Trạm đang có trùng với điểm đề xuất (dữ liệu đóng gói/OSM/cache và đề xuất cũ). null nếu không trùng.
  static ChargingStation? checkDuplicate(
    ChargingStation candidate,
    Iterable<ChargingStation> existing,
  ) {
    for (final s in existing) {
      if (StationDedupe.isDuplicate(s, candidate)) return s;
    }
    return null;
  }

  /// Lưu đề xuất. Trùng → không lưu, trả về trạm bị trùng.
  static Future<({StationProposal? saved, ChargingStation? duplicateOf})> submit({
    required String name,
    required String address,
    required double lat,
    required double lng,
    String? phone,
    String? note,
    String? photoPath,
    Iterable<ChargingStation> existing = const [],
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final p = StationProposal(
      id: 'user/${at.microsecondsSinceEpoch}',
      name: name.trim(),
      address: address.trim(),
      lat: lat,
      lng: lng,
      phone: (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      photoPath: photoPath,
      createdAt: at,
    );
    final mine = await all();
    final dup = checkDuplicate(p.toStation(), [...existing, for (final m in mine) m.toStation()]);
    if (dup != null) return (saved: null, duplicateOf: dup);
    await _write([p, ...mine]);
    return (saved: p, duplicateOf: null);
  }

  static Future<void> remove(String id) async {
    final l = await all();
    l.removeWhere((p) => p.id == id);
    await _write(l);
  }

  /// JSON cho người quản trị đối chiếu/duyệt bên ngoài app.
  static Future<String> exportJson() async => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'proposals': [for (final p in await all()) p.toJson()],
      });
}
