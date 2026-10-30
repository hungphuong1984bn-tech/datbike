import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/diagnostics/diag_model.dart';

DiagEvent _issue(String id, DiagSeverity s, DateTime at) => DiagEvent(
      id: id,
      at: at,
      source: DiagSource.vehicle,
      severity: s,
      isIssue: true,
      title: id,
    );

void main() {
  final t0 = DateTime(2026, 10, 30, 10, 0);

  test('raise không tạo trùng khi lỗi cùng khóa đang hoạt động', () {
    final log = DiagLog();
    expect(log.raise(_issue('a', DiagSeverity.warning, t0)), isTrue);
    expect(log.raise(_issue('a', DiagSeverity.warning, t0)), isFalse);
    expect(log.activeIssues.length, 1);
  });

  test('clear đóng lỗi, lỗi cùng khóa xuất hiện lại tạo mục mới', () {
    final log = DiagLog();
    log.raise(_issue('a', DiagSeverity.warning, t0));
    expect(log.clear('a', t0.add(const Duration(minutes: 5))), isTrue);
    expect(log.activeIssues, isEmpty);
    expect(log.raise(_issue('a', DiagSeverity.warning, t0.add(const Duration(hours: 1)))), isTrue);
    expect(log.issueHistory.length, 2);
  });

  test('activeIssues: nghiêm trọng đứng trước cảnh báo', () {
    final log = DiagLog();
    log.raise(_issue('w', DiagSeverity.warning, t0));
    log.raise(_issue('c', DiagSeverity.critical, t0.subtract(const Duration(hours: 1))));
    expect(log.activeIssues.first.id, 'c');
  });

  test('clearMissing chỉ đóng lỗi cùng tiền tố và không nằm trong danh sách giữ', () {
    final log = DiagLog();
    log.raise(_issue('vehicle:1', DiagSeverity.warning, t0));
    log.raise(_issue('vehicle:2', DiagSeverity.warning, t0));
    log.raise(_issue('bms:1', DiagSeverity.warning, t0));
    final n = log.clearMissing('vehicle:', {'vehicle:1'}, t0);
    expect(n, 1);
    expect(log.isActive('vehicle:1'), isTrue);
    expect(log.isActive('vehicle:2'), isFalse);
    expect(log.isActive('bms:1'), isTrue);
  });

  test('giới hạn dung lượng giữ các mục mới nhất', () {
    final log = DiagLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add(DiagEvent(
        id: 'e$i',
        at: t0.add(Duration(minutes: i)),
        source: DiagSource.activity,
        severity: DiagSeverity.info,
        title: 'e$i',
      ));
    }
    expect(log.events.map((e) => e.id).toList(), ['e4', 'e3', 'e2']);
  });

  test('mã hóa / giải mã JSON giữ nguyên nội dung; bản ghi hỏng bị bỏ qua', () {
    final log = DiagLog();
    log.raise(DiagEvent(
      id: 'x',
      at: t0,
      source: DiagSource.bms,
      severity: DiagSeverity.critical,
      isIssue: true,
      title: 'Quá áp cell',
      detail: '4,25 V',
      cause: 'nguyên nhân',
      advice: 'xử lý',
    ));
    log.clear('x', t0.add(const Duration(minutes: 2)));
    final copy = DiagLog()..load(log.encode());
    expect(copy.events.length, 1);
    final e = copy.events.first;
    expect(e.title, 'Quá áp cell');
    expect(e.severity, DiagSeverity.critical);
    expect(e.source, DiagSource.bms);
    expect(e.isActive, isFalse);
    expect(e.cause, 'nguyên nhân');

    final broken = DiagLog()..load('[{"id":1},"x",{"id":"a","at":1,"src":"zzz","sev":"info","title":"t"}]');
    expect(broken.events, isEmpty);
    final garbage = DiagLog()..load('không phải json');
    expect(garbage.events, isEmpty);
  });

  test('closeStaleOnStartup đóng lỗi còn mở của phiên trước', () {
    final log = DiagLog();
    log.raise(_issue('a', DiagSeverity.warning, t0));
    log.closeStaleOnStartup(t0.add(const Duration(hours: 1)));
    expect(log.activeIssues, isEmpty);
  });

  test('VehicleHealth: không có dữ liệu thì KHÔNG kết luận Tốt', () {
    expect(VehicleHealth.evaluate(const [], hasLiveData: false).level, VehicleHealthLevel.unknown);
    expect(VehicleHealth.evaluate(const [], hasLiveData: true).level, VehicleHealthLevel.good);
  });

  test('VehicleHealth: mức theo lỗi nặng nhất và đếm đúng', () {
    final list = [
      _issue('a', DiagSeverity.warning, t0),
      _issue('b', DiagSeverity.warning, t0),
      _issue('c', DiagSeverity.info, t0),
    ];
    final h = VehicleHealth.evaluate(list, hasLiveData: true);
    expect(h.level, VehicleHealthLevel.watch);
    expect((h.critical, h.warning, h.info), (0, 2, 1));
    final h2 = VehicleHealth.evaluate([...list, _issue('d', DiagSeverity.critical, t0)], hasLiveData: false);
    expect(h2.level, VehicleHealthLevel.critical);
  });

  test('định dạng thời gian', () {
    expect(fmtDiagTime(DateTime(2026, 10, 3, 4, 5)), '04:05 03/10');
    expect(fmtDiagDuration(const Duration(seconds: 45)), '45 giây');
    expect(fmtDiagDuration(const Duration(minutes: 3)), '3 phút');
    expect(fmtDiagDuration(const Duration(hours: 2, minutes: 5)), '2 giờ 5 phút');
    expect(fmtDiagDuration(const Duration(hours: 2)), '2 giờ');
  });
}
