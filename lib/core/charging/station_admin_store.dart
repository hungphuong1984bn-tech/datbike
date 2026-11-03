// Quản lý dữ liệu trạm sạc do quản trị viên nhập: thêm / sửa / xóa / ẩn-hiện /
// xác minh, duyệt đề xuất, lịch sử thay đổi, xuất CSV/JSON.
//
// PHÂN QUYỀN & GIỚI HẠN (nói thẳng, không giả vờ bảo mật máy chủ):
//  • "Quản trị viên" ở đây là quyền CỤC BỘ trên thiết bị, mở khóa bằng mã PIN
//    (băm SHA-256 có muối, lưu trong kho bảo mật Keystore/Keychain). Mọi hàm ghi
//    đều từ chối khi chưa mở khóa. Đây KHÔNG phải xác thực máy chủ: ai có máy và
//    biết PIN thì là quản trị viên. Phân quyền thật đa người dùng cần Backend.
//  • Dữ liệu lưu SharedPreferences trên máy; chưa tự đồng bộ lên đâu cả
//    (xem station_sync.dart).
//  • Điểm do admin tạo KHÔNG BAO GIỜ mang nhãn "Dat Bike chính thức"; chỉ là
//    đối tác hoặc cộng đồng. Trạng thái "đang hoạt động" chỉ có khi đã xác minh.

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/charging_station_service.dart';
import '../session/secret_store.dart';
import 'station_analytics.dart';
import 'station_log.dart';
import 'station_proposal_store.dart';

const List<String> kStationTypes = [
  'Trạm sạc công cộng',
  'Điểm sạc đối tác',
  'Điểm sạc tại cửa hàng',
  'Trạm đổi pin',
  'Khác',
];

// ═════════════ Quyền quản trị cục bộ ═════════════

class StationAdminAuth {
  StationAdminAuth._();

  static const _hashKey = 'station_admin_pin_hash_v1';
  static const _saltKey = 'station_admin_pin_salt_v1';
  static const _nameKey = 'station_admin_name_v1';
  static const int maxFails = 5;
  static const Duration lockout = Duration(seconds: 60);

  static bool _admin = false;
  static String _name = '';
  static int _fails = 0;
  static DateTime? _lockedUntil;

  static bool get isAdmin => _admin;
  static String get actor => _admin ? (_name.isEmpty ? 'admin' : _name) : '';

  /// Chỉ cho kiểm thử.
  static void debugSet({required bool admin, String name = 'tester'}) {
    _admin = admin;
    _name = name;
  }

  static void lock() {
    _admin = false;
  }

  static void assertAdmin() {
    if (!_admin) throw StateError('Cần quyền quản trị viên để thực hiện thao tác này.');
  }

  /// PIN hợp lệ: 4–12 ký tự, không toàn khoảng trắng.
  static String? validatePin(String pin) {
    final p = pin.trim();
    if (p.length < 4) return 'Mã PIN cần ít nhất 4 ký tự.';
    if (p.length > 12) return 'Mã PIN tối đa 12 ký tự.';
    return null;
  }

  static String hashPin(String pin, String salt) {
    var h = utf8.encode('$salt:$pin');
    for (var i = 0; i < 2000; i++) {
      h = sha256.convert(h).bytes;
    }
    return base64Url.encode(h);
  }

  static String _newSalt() {
    final r = math.Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static Future<String?> _read(SharedPreferences p, String key) async =>
      await SecretStore.instance.read(key) ?? p.getString(key);

  static Future<bool> hasPin() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (await _read(p, _hashKey)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<String> savedName() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_nameKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Tạo PIN lần đầu và mở khóa. Trả về thông báo lỗi hoặc null nếu thành công.
  static Future<String?> setupPin(String pin, String name) async {
    final err = validatePin(pin);
    if (err != null) return err;
    if (name.trim().length < 2) return 'Nhập tên quản trị viên (để ghi vào lịch sử thay đổi).';
    try {
      final p = await SharedPreferences.getInstance();
      if ((await _read(p, _hashKey)) != null) return 'Đã có mã PIN quản trị.';
      final salt = _newSalt();
      await SecretStore.instance.save(p, _saltKey, salt);
      await SecretStore.instance.save(p, _hashKey, hashPin(pin.trim(), salt));
      await p.setString(_nameKey, name.trim());
      _admin = true;
      _name = name.trim();
      _fails = 0;
      return null;
    } catch (e) {
      return 'Không lưu được mã PIN: $e';
    }
  }

  /// Mở khóa bằng PIN. Trả về thông báo lỗi hoặc null nếu thành công.
  static Future<String?> unlock(String pin, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    if (_lockedUntil != null && t.isBefore(_lockedUntil!)) {
      return 'Nhập sai nhiều lần. Thử lại sau ${_lockedUntil!.difference(t).inSeconds + 1} giây.';
    }
    try {
      final p = await SharedPreferences.getInstance();
      final salt = await _read(p, _saltKey);
      final hash = await _read(p, _hashKey);
      if (salt == null || hash == null) return 'Chưa tạo mã PIN quản trị.';
      if (hashPin(pin.trim(), salt) == hash) {
        _admin = true;
        _name = p.getString(_nameKey) ?? '';
        _fails = 0;
        _lockedUntil = null;
        return null;
      }
      _fails++;
      if (_fails >= maxFails) {
        _fails = 0;
        _lockedUntil = t.add(lockout);
        return 'Nhập sai $maxFails lần. Khóa ${lockout.inSeconds} giây.';
      }
      return 'Mã PIN không đúng.';
    } catch (e) {
      return 'Không kiểm tra được mã PIN: $e';
    }
  }
}

// ═════════════ Mô hình ═════════════

class ManagedStation {
  final String id;

  /// Mã trạm tự động, vd. THB-000012.
  final String code;
  final String name;
  final String address;
  final String province;
  final String district;
  final double lat;
  final double lng;
  final StationCategory category;
  final String stationType;
  final VehicleSupport vehicle;
  final int? ports;
  final double? powerKw;
  final String note;
  final String? photoPath;

  /// Đã được quản trị viên xác minh. Chỉ khi true mới có thể hiện "đang hoạt động".
  final bool verified;
  final String? verifiedBy;
  final DateTime? verifiedAt;

  /// Trạng thái vận hành áp dụng khi đã xác minh (active / paused / closed).
  final StationStatus operating;

  /// Dữ liệu đang được cập nhật (Marker xanh dương).
  final bool updating;
  final bool hidden;
  final String createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;
  final int rev;

  const ManagedStation({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.province = '',
    this.district = '',
    this.category = StationCategory.community,
    this.stationType = 'Trạm sạc công cộng',
    this.vehicle = VehicleSupport.unknown,
    this.ports,
    this.powerKw,
    this.note = '',
    this.photoPath,
    this.verified = false,
    this.verifiedBy,
    this.verifiedAt,
    this.operating = StationStatus.active,
    this.updating = false,
    this.hidden = false,
    this.updatedBy,
    this.rev = 1,
  });

  /// Trạng thái hiển thị: chưa xác minh thì luôn "chưa xác minh".
  StationStatus get effectiveStatus => verified ? operating : StationStatus.unverified;

  ChargingStation toStation() => ChargingStation(
        id: id,
        name: name,
        lat: lat,
        lng: lng,
        operator: 'THBIKE',
        capacity: ports?.toString(),
        vehicle: vehicle,
        status: effectiveStatus,
        powerKw: powerKw,
        address: _fullAddress,
        source: 'Quản trị viên THBIKE (cục bộ)',
        category: category == StationCategory.datBike ? StationCategory.partner : category,
        chargingConfirmed: verified,
        updatedAt: updatedAt,
      );

  String get _fullAddress {
    final parts = [address.trim(), district.trim(), province.trim()].where((e) => e.isNotEmpty).toList();
    // Không lặp quận/tỉnh nếu địa chỉ đã chứa.
    final out = <String>[];
    for (final p in parts) {
      if (out.isEmpty || !out.first.toLowerCase().contains(p.toLowerCase())) out.add(p);
    }
    return out.join(', ');
  }

  ManagedStation copyWith({
    bool? verified,
    bool clearVerification = false,
    String? verifiedBy,
    DateTime? verifiedAt,
    StationStatus? operating,
    bool? updating,
    bool? hidden,
    String? updatedBy,
    DateTime? updatedAt,
    int? rev,
  }) =>
      ManagedStation(
        id: id,
        code: code,
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        province: province,
        district: district,
        category: category,
        stationType: stationType,
        vehicle: vehicle,
        ports: ports,
        powerKw: powerKw,
        note: note,
        photoPath: photoPath,
        verified: verified ?? this.verified,
        verifiedBy: clearVerification ? null : (verifiedBy ?? this.verifiedBy),
        verifiedAt: clearVerification ? null : (verifiedAt ?? this.verifiedAt),
        operating: operating ?? this.operating,
        updating: updating ?? this.updating,
        hidden: hidden ?? this.hidden,
        updatedBy: updatedBy ?? this.updatedBy,
        rev: rev ?? this.rev,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'address': address,
        'province': province,
        'district': district,
        'lat': lat,
        'lng': lng,
        'category': category.name,
        'type': stationType,
        'vehicle': vehicle.name,
        if (ports != null) 'ports': ports,
        if (powerKw != null) 'powerKw': powerKw,
        'note': note,
        if (photoPath != null) 'photoPath': photoPath,
        'verified': verified,
        if (verifiedBy != null) 'verifiedBy': verifiedBy,
        if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
        'operating': operating.name,
        'updating': updating,
        'hidden': hidden,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        if (updatedBy != null) 'updatedBy': updatedBy,
        'updatedAt': updatedAt.toIso8601String(),
        'rev': rev,
      };

  static T _enum<T extends Enum>(List<T> values, Object? n, T fallback) {
    for (final v in values) {
      if (v.name == n) return v;
    }
    return fallback;
  }

  static ManagedStation? fromJson(Object? o) {
    if (o is! Map) return null;
    final lat = o['lat'], lng = o['lng'];
    if (lat is! num || lng is! num) return null;
    final created = DateTime.tryParse('${o['createdAt']}') ?? DateTime.now();
    return ManagedStation(
      id: '${o['id']}',
      code: '${o['code'] ?? ''}',
      name: '${o['name'] ?? ''}',
      address: '${o['address'] ?? ''}',
      province: '${o['province'] ?? ''}',
      district: '${o['district'] ?? ''}',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      category: _enum(StationCategory.values, o['category'], StationCategory.community),
      stationType: '${o['type'] ?? kStationTypes.first}',
      vehicle: _enum(VehicleSupport.values, o['vehicle'], VehicleSupport.unknown),
      ports: (o['ports'] as num?)?.toInt(),
      powerKw: (o['powerKw'] as num?)?.toDouble(),
      note: '${o['note'] ?? ''}',
      photoPath: o['photoPath'] as String?,
      verified: o['verified'] == true,
      verifiedBy: o['verifiedBy'] as String?,
      verifiedAt: DateTime.tryParse('${o['verifiedAt']}'),
      operating: _enum(StationStatus.values, o['operating'], StationStatus.active),
      updating: o['updating'] == true,
      hidden: o['hidden'] == true,
      createdBy: '${o['createdBy'] ?? ''}',
      createdAt: created,
      updatedBy: o['updatedBy'] as String?,
      updatedAt: DateTime.tryParse('${o['updatedAt']}') ?? created,
      rev: (o['rev'] as num?)?.toInt() ?? 1,
    );
  }
}

// ═════════════ Kho dữ liệu ═════════════

class StationAdminStore {
  StationAdminStore._();

  static const _key = 'station_managed_v1';
  static const _hiddenKey = 'station_hidden_ext_v1';
  static const _histKey = 'station_change_log_v1';
  static const _seqKey = 'station_seq_v1';
  static const int maxHistory = 2000;

  /// Trạm gần hơn ngưỡng này coi là TRÙNG (chặn lưu).
  static const double duplicateMeters = 15;

  /// Trạm gần hơn ngưỡng này thì CẢNH BÁO, cho phép xác nhận vẫn lưu.
  static const double nearMeters = 100;

  // ── Hàm thuần ──

  /// Kiểm tra dữ liệu nhập. null = hợp lệ.
  static String? validate({
    required String name,
    required String address,
    required double? lat,
    required double? lng,
    int? ports,
    double? powerKw,
  }) {
    if (name.trim().length < 3) return 'Nhập tên trạm (ít nhất 3 ký tự).';
    if (address.trim().length < 5) return 'Nhập địa chỉ trạm.';
    if (lat == null || lng == null) return 'Nhập tọa độ hợp lệ (vĩ độ, kinh độ).';
    if (lat.isNaN || lng.isNaN || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return 'Tọa độ nằm ngoài phạm vi hợp lệ.';
    }
    if (lat == 0 && lng == 0) return 'Tọa độ (0, 0) không hợp lệ.';
    if (ports != null && (ports < 1 || ports > 500)) return 'Số cổng sạc không hợp lệ (1–500).';
    if (powerKw != null && (powerKw <= 0 || powerKw > 1000)) return 'Công suất không hợp lệ (0–1000 kW).';
    return null;
  }

  /// Trạm gần nhất trong [stations] (bỏ qua [excludeId]) và khoảng cách mét. null nếu không có.
  static ({ChargingStation station, double meters})? nearest(
    double lat,
    double lng,
    Iterable<ChargingStation> stations, {
    String? excludeId,
  }) {
    ChargingStation? best;
    var bestM = double.infinity;
    for (final s in stations) {
      if (s.id == excludeId) continue;
      final m = StationAnalytics.haversineKm(lat, lng, s.lat, s.lng) * 1000;
      if (m < bestM) {
        bestM = m;
        best = s;
      }
    }
    return best == null ? null : (station: best, meters: bestM);
  }

  /// Các trường khác nhau giữa hai bản ghi: tên trường → [cũ, mới]. Hàm thuần.
  static Map<String, List<String?>> diff(ManagedStation? a, ManagedStation b) {
    final out = <String, List<String?>>{};
    void f(String k, Object? x, Object? y) {
      final xs = x?.toString(), ys = y?.toString();
      if (xs != ys) out[k] = [xs, ys];
    }

    f('name', a?.name, b.name);
    f('address', a?.address, b.address);
    f('province', a?.province, b.province);
    f('district', a?.district, b.district);
    f('lat', a?.lat, b.lat);
    f('lng', a?.lng, b.lng);
    f('category', a?.category.name, b.category.name);
    f('type', a?.stationType, b.stationType);
    f('vehicle', a?.vehicle.name, b.vehicle.name);
    f('ports', a?.ports, b.ports);
    f('powerKw', a?.powerKw, b.powerKw);
    f('note', a?.note, b.note);
    f('status', a?.effectiveStatus.name, b.effectiveStatus.name);
    f('updating', a?.updating, b.updating);
    return out;
  }

  /// CSV chuẩn RFC 4180 (bao nháy kép khi có dấu phẩy/nháy/xuống dòng).
  static String toCsv(List<ManagedStation> list) {
    String q(Object? v) {
      final s = v?.toString() ?? '';
      return (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    const head = [
      'code', 'id', 'name', 'address', 'province', 'district', 'lat', 'lng', 'category', 'type',
      'vehicle', 'ports', 'powerKw', 'status', 'verified', 'verifiedBy', 'verifiedAt', 'hidden',
      'note', 'createdBy', 'createdAt', 'updatedBy', 'updatedAt',
    ];
    final b = StringBuffer()..writeln(head.join(','));
    for (final s in list) {
      b.writeln([
        s.code, s.id, s.name, s.address, s.province, s.district, s.lat, s.lng, s.category.name,
        s.stationType, s.vehicle.name, s.ports, s.powerKw, s.effectiveStatus.name, s.verified,
        s.verifiedBy, s.verifiedAt?.toIso8601String(), s.hidden, s.note, s.createdBy,
        s.createdAt.toIso8601String(), s.updatedBy, s.updatedAt.toIso8601String(),
      ].map(q).join(','));
    }
    return b.toString();
  }

  // ── Lưu trữ ──

  static Future<List<ManagedStation>> all() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return [];
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return [for (final e in l) ?ManagedStation.fromJson(e)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<ManagedStation> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final s in l) s.toJson()]));
  }

  /// Trạm hiển thị cho mọi người dùng (admin đã ẩn thì không có).
  static Future<List<ChargingStation>> visibleStations() async =>
      [for (final s in await all()) if (!s.hidden) s.toStation()];

  /// Trạm KHÔNG do admin tạo (OSM/đóng gói/đề xuất) đã bị ẩn: id → tên.
  static Future<Map<String, String>> hiddenExternal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_hiddenKey);
      if (raw == null) return {};
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {for (final e in m.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  /// Lọc bỏ các trạm đã bị ẩn.
  static Future<List<ChargingStation>> withoutHidden(List<ChargingStation> list) async {
    final h = await hiddenExternal();
    if (h.isEmpty) return list;
    return [for (final s in list) if (!h.containsKey(s.id)) s];
  }

  static Future<String> nextCode() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_seqKey) ?? 0) + 1;
    await p.setInt(_seqKey, n);
    return 'THB-${n.toString().padLeft(6, '0')}';
  }

  // ── Lịch sử ──

  static Future<List<StationChangeLog>> history({String? stationId}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_histKey);
      if (raw == null) return [];
      final l = jsonDecode(raw);
      if (l is! List) return [];
      final out = [for (final e in l) ?StationChangeLog.fromJson(e)];
      final filtered = stationId == null ? out : [for (final h in out) if (h.stationId == stationId) h];
      return filtered.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _log(StationChangeLog c) async {
    final p = await SharedPreferences.getInstance();
    List<dynamic> l = [];
    try {
      final raw = p.getString(_histKey);
      if (raw != null) {
        final d = jsonDecode(raw);
        if (d is List) l = d;
      }
    } catch (_) {}
    l.add(c.toJson());
    if (l.length > maxHistory) l = l.sublist(l.length - maxHistory);
    await p.setString(_histKey, jsonEncode(l));
  }

  // ── Thao tác ghi (chỉ admin) ──

  /// Tạo mới hoặc cập nhật. Cập nhật tự tăng [ManagedStation.rev] và ghi diff.
  static Future<ManagedStation> save(ManagedStation s, {DateTime? now}) async {
    StationAdminAuth.assertAdmin();
    final at = now ?? DateTime.now();
    final actor = StationAdminAuth.actor;
    final list = await all();
    final i = list.indexWhere((e) => e.id == s.id);
    final ManagedStation? before = i < 0 ? null : list[i];
    final ManagedStation saved;
    if (before == null) {
      saved = s.copyWith(updatedBy: actor, updatedAt: at, rev: 1);
      list.add(saved);
    } else {
      saved = s.copyWith(updatedBy: actor, updatedAt: at, rev: before.rev + 1);
      list[i] = saved;
    }
    final ch = diff(before, saved);
    await _write(list);
    await _log(StationChangeLog(
      stationId: saved.id,
      stationName: saved.name,
      action: i < 0 ? ChangeAction.create : ChangeAction.update,
      at: at,
      actor: actor,
      changes: i < 0 ? const {} : ch,
    ));
    return saved;
  }

  static Future<void> delete(String id, {DateTime? now}) async {
    StationAdminAuth.assertAdmin();
    final list = await all();
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final gone = list.removeAt(i);
    await _write(list);
    await _log(StationChangeLog(
      stationId: id,
      stationName: gone.name,
      action: ChangeAction.delete,
      at: now ?? DateTime.now(),
      actor: StationAdminAuth.actor,
    ));
  }

  /// Ẩn/hiện một trạm bất kỳ (của admin hoặc từ nguồn ngoài). Không xóa dữ liệu nguồn.
  static Future<void> setHidden(String id, String name, bool hidden, {DateTime? now}) async {
    StationAdminAuth.assertAdmin();
    final list = await all();
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      list[i] = list[i].copyWith(
        hidden: hidden,
        updatedBy: StationAdminAuth.actor,
        updatedAt: now ?? DateTime.now(),
        rev: list[i].rev + 1,
      );
      await _write(list);
    } else {
      final h = await hiddenExternal();
      if (hidden) {
        h[id] = name;
      } else {
        h.remove(id);
      }
      final p = await SharedPreferences.getInstance();
      await p.setString(_hiddenKey, jsonEncode(h));
    }
    await _log(StationChangeLog(
      stationId: id,
      stationName: name,
      action: hidden ? ChangeAction.hide : ChangeAction.show,
      at: now ?? DateTime.now(),
      actor: StationAdminAuth.actor,
    ));
  }

  /// Xác minh / bỏ xác minh một trạm do admin quản lý.
  static Future<ManagedStation?> setVerified(
    String id,
    bool verified, {
    StationStatus operating = StationStatus.active,
    DateTime? now,
  }) async {
    StationAdminAuth.assertAdmin();
    final at = now ?? DateTime.now();
    final list = await all();
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final cur = list[i];
    final next = cur.copyWith(
      verified: verified,
      clearVerification: !verified,
      verifiedBy: verified ? StationAdminAuth.actor : null,
      verifiedAt: verified ? at : null,
      operating: verified ? operating : cur.operating,
      updating: false,
      updatedBy: StationAdminAuth.actor,
      updatedAt: at,
      rev: cur.rev + 1,
    );
    list[i] = next;
    await _write(list);
    await _log(StationChangeLog(
      stationId: id,
      stationName: cur.name,
      action: verified ? ChangeAction.verify : ChangeAction.unverify,
      at: at,
      actor: StationAdminAuth.actor,
      changes: {
        'status': [cur.effectiveStatus.name, next.effectiveStatus.name],
      },
    ));
    return next;
  }

  /// Duyệt đề xuất của người dùng → tạo trạm CHƯA XÁC MINH trong danh sách admin, bỏ đề xuất khỏi hàng chờ.
  static Future<ManagedStation> approveProposal(StationProposal p, {DateTime? now}) async {
    StationAdminAuth.assertAdmin();
    final at = now ?? DateTime.now();
    final code = await nextCode();
    final s = ManagedStation(
      id: 'thb/${code.toLowerCase()}',
      code: code,
      name: p.name,
      address: p.address,
      lat: p.lat,
      lng: p.lng,
      note: p.note ?? '',
      photoPath: p.photoPath,
      createdBy: StationAdminAuth.actor,
      createdAt: at,
      updatedAt: at,
    );
    final list = await all();
    list.add(s.copyWith(updatedBy: StationAdminAuth.actor, updatedAt: at));
    await _write(list);
    await StationProposalStore.remove(p.id);
    await _log(StationChangeLog(
      stationId: s.id,
      stationName: s.name,
      action: ChangeAction.approve,
      at: at,
      actor: StationAdminAuth.actor,
      changes: {
        'proposal': [p.id, s.id],
      },
      source: 'Đề xuất người dùng → quản trị viên duyệt (cục bộ)',
    ));
    return list.last;
  }

  static Future<void> rejectProposal(StationProposal p, {DateTime? now}) async {
    StationAdminAuth.assertAdmin();
    await StationProposalStore.remove(p.id);
    await _log(StationChangeLog(
      stationId: p.id,
      stationName: p.name,
      action: ChangeAction.reject,
      at: now ?? DateTime.now(),
      actor: StationAdminAuth.actor,
    ));
  }

  // ── Xuất dữ liệu ──

  static Future<String> exportJson() async => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'stations': [for (final s in await all()) s.toJson()],
        'hiddenExternal': await hiddenExternal(),
        'changeLog': [for (final h in await history()) h.toJson()],
      });

  static Future<String> exportCsv() async => toCsv(await all());
}
