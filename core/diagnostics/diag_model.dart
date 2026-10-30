// Mô hình Trung tâm chẩn đoán — module THUẦN Dart (không import Flutter) để kiểm thử được.
//
// Quy tắc: chỉ ghi lại những gì ứng dụng thực sự quan sát được (mã lỗi xe báo,
// cảnh báo BMS, đổi trạng thái kết nối, sự kiện vận hành). Không suy diễn nguyên
// nhân ngoài bảng mô tả đã có trong ứng dụng. Không ghi khóa phiên/token.

import 'dart:convert';

/// Nguồn của sự kiện.
enum DiagSource {
  vehicle('Xe'),
  bms('BMS'),
  ble('Bluetooth'),
  activity('Hoạt động');

  final String label;
  const DiagSource(this.label);
}

/// Mức độ nghiêm trọng (tách khỏi widget; UI ánh xạ sang màu).
enum DiagSeverity {
  ok('Bình thường'),
  info('Thông tin'),
  warning('Cảnh báo'),
  critical('Nghiêm trọng');

  final String label;
  const DiagSeverity(this.label);

  /// Dùng để sắp xếp: nặng hơn → lớn hơn.
  int get rank => index;
}

class DiagEvent {
  /// Khóa ổn định của một lỗi/cảnh báo (vd. "vehicle:error:3"). Sự kiện hoạt động
  /// thông thường dùng khóa duy nhất theo thời gian.
  final String id;
  final DateTime at;
  final DiagSource source;
  final DiagSeverity severity;
  final String title;
  final String detail;

  /// true = lỗi/cảnh báo (vào "Lịch sử lỗi"); false = nhật ký thông thường.
  final bool isIssue;

  /// Lúc lỗi hết (null = còn đang xảy ra hoặc không phải lỗi).
  final DateTime? clearedAt;

  /// Gợi ý nguyên nhân / hướng xử lý (nếu ứng dụng có bảng mô tả).
  final String? cause;
  final String? advice;

  const DiagEvent({
    required this.id,
    required this.at,
    required this.source,
    required this.severity,
    required this.title,
    this.detail = '',
    this.isIssue = false,
    this.clearedAt,
    this.cause,
    this.advice,
  });

  bool get isActive => isIssue && clearedAt == null;

  DiagEvent cleared(DateTime when) => DiagEvent(
        id: id,
        at: at,
        source: source,
        severity: severity,
        title: title,
        detail: detail,
        isIssue: isIssue,
        clearedAt: when,
        cause: cause,
        advice: advice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'src': source.name,
        'sev': severity.name,
        'title': title,
        'detail': detail,
        'issue': isIssue,
        if (clearedAt != null) 'clr': clearedAt!.millisecondsSinceEpoch,
        if (cause != null) 'cause': cause,
        if (advice != null) 'advice': advice,
      };

  static DiagEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final src = DiagSource.values.where((e) => e.name == raw['src']);
      final sev = DiagSeverity.values.where((e) => e.name == raw['sev']);
      if (src.isEmpty || sev.isEmpty) return null;
      final clr = raw['clr'];
      return DiagEvent(
        id: raw['id'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num).toInt()),
        source: src.first,
        severity: sev.first,
        title: raw['title'] as String,
        detail: (raw['detail'] as String?) ?? '',
        isIssue: (raw['issue'] as bool?) ?? false,
        clearedAt: clr is num ? DateTime.fromMillisecondsSinceEpoch(clr.toInt()) : null,
        cause: raw['cause'] as String?,
        advice: raw['advice'] as String?,
      );
    } catch (_) {
      return null; // bản ghi hỏng → bỏ qua, không làm hỏng cả nhật ký
    }
  }
}

/// Nhật ký sự kiện: mới nhất đứng đầu, giới hạn dung lượng.
class DiagLog {
  final int capacity;
  final List<DiagEvent> _events = [];

  DiagLog({this.capacity = 300});

  List<DiagEvent> get events => List.unmodifiable(_events);

  /// Lỗi/cảnh báo đang xảy ra, nặng nhất trước, rồi mới nhất trước.
  List<DiagEvent> get activeIssues {
    final l = _events.where((e) => e.isActive).toList();
    l.sort((a, b) {
      final c = b.severity.rank.compareTo(a.severity.rank);
      return c != 0 ? c : b.at.compareTo(a.at);
    });
    return l;
  }

  /// Toàn bộ lỗi/cảnh báo (đã hết + đang có), mới nhất trước.
  List<DiagEvent> get issueHistory => _events.where((e) => e.isIssue).toList();

  List<DiagEvent> bySource(DiagSource s) => _events.where((e) => e.source == s).toList();

  bool isActive(String id) => _events.any((e) => e.id == id && e.isActive);

  void add(DiagEvent e) {
    _events.insert(0, e);
    if (_events.length > capacity) {
      _events.removeRange(capacity, _events.length);
    }
  }

  /// Bắt đầu một lỗi nếu chưa có lỗi cùng khóa đang hoạt động. Trả về true nếu mới.
  bool raise(DiagEvent e) {
    if (isActive(e.id)) return false;
    add(e);
    return true;
  }

  /// Đánh dấu lỗi cùng khóa đã hết. Trả về true nếu có thay đổi.
  bool clear(String id, DateTime at) {
    final i = _events.indexWhere((e) => e.id == id && e.isActive);
    if (i < 0) return false;
    _events[i] = _events[i].cleared(at);
    return true;
  }

  /// Đóng mọi lỗi đang mở có khóa bắt đầu bằng [prefix] mà KHÔNG nằm trong [keep].
  int clearMissing(String prefix, Set<String> keep, DateTime at) {
    var n = 0;
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      if (e.isActive && e.id.startsWith(prefix) && !keep.contains(e.id)) {
        _events[i] = e.cleared(at);
        n++;
      }
    }
    return n;
  }

  void clearAll() => _events.clear();

  String encode() => jsonEncode(_events.map((e) => e.toJson()).toList());

  void load(String? raw) {
    _events.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final item in list) {
        final e = DiagEvent.fromJson(item);
        if (e != null) _events.add(e);
      }
      if (_events.length > capacity) _events.removeRange(capacity, _events.length);
    } catch (_) {
      _events.clear();
    }
  }

  /// Mở lại ứng dụng: các lỗi còn "đang hoạt động" từ phiên trước không còn đáng tin
  /// (không biết đã hết hay chưa) → đóng lại bằng [at], sẽ được mở lại nếu còn xảy ra.
  void closeStaleOnStartup(DateTime at) {
    for (var i = 0; i < _events.length; i++) {
      if (_events[i].isActive) _events[i] = _events[i].cleared(at);
    }
  }
}

/// Tổng quan sức khỏe xe suy ra từ các lỗi đang hoạt động.
enum VehicleHealthLevel {
  unknown('Chưa có dữ liệu', 'Kết nối xe để đánh giá tình trạng.'),
  good('Tốt', 'Không có lỗi hay cảnh báo đang hoạt động.'),
  watch('Cần theo dõi', 'Có cảnh báo, chưa ảnh hưởng an toàn ngay.'),
  critical('Cần xử lý ngay', 'Có lỗi nghiêm trọng, nên dừng xe ở nơi an toàn.');

  final String label;
  final String hint;
  const VehicleHealthLevel(this.label, this.hint);
}

class VehicleHealth {
  final VehicleHealthLevel level;
  final int critical;
  final int warning;
  final int info;

  const VehicleHealth(this.level, this.critical, this.warning, this.info);

  /// [hasLiveData] = đang có dữ liệu trực tiếp từ xe. Không có dữ liệu → không kết luận "Tốt".
  static VehicleHealth evaluate(Iterable<DiagEvent> active, {required bool hasLiveData}) {
    var c = 0, w = 0, i = 0;
    for (final e in active) {
      if (!e.isActive) continue;
      switch (e.severity) {
        case DiagSeverity.critical:
          c++;
        case DiagSeverity.warning:
          w++;
        case DiagSeverity.info:
          i++;
        case DiagSeverity.ok:
          break;
      }
    }
    final VehicleHealthLevel lvl;
    if (c > 0) {
      lvl = VehicleHealthLevel.critical;
    } else if (w > 0) {
      lvl = VehicleHealthLevel.watch;
    } else if (!hasLiveData) {
      lvl = VehicleHealthLevel.unknown;
    } else {
      lvl = VehicleHealthLevel.good;
    }
    return VehicleHealth(lvl, c, w, i);
  }
}

/// Định dạng thời điểm gọn, tiếng Việt: "14:05 30/10".
String fmtDiagTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
}

/// Khoảng thời gian gọn: "45 giây", "3 phút", "2 giờ 5 phút".
String fmtDiagDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds < 0 ? 0 : d.inSeconds} giây';
  if (d.inMinutes < 60) return '${d.inMinutes} phút';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} giờ' : '${d.inHours} giờ $m phút';
}
