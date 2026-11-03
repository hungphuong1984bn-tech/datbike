import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/proximity/activity_history.dart';
import 'package:mybike_app/core/proximity/proximity_engine.dart' show ProximityEvent;

void main() {
  test('phân loại sự kiện', () {
    expect(classifyActivity('unlock_ok'), ActivityKind.unlock);
    expect(classifyActivity('lock_ok'), ActivityKind.lock);
    expect(classifyActivity('user_lock'), ActivityKind.lock);
    expect(classifyActivity('unlock_fail'), ActivityKind.error);
    expect(classifyActivity('calibrate_start'), ActivityKind.calibration);
    expect(classifyActivity('armed_unlock'), ActivityKind.other);
  });
  test('encode/decode khứ hồi và cắt theo dung lượng', () {
    final ev = [
      for (var i = 0; i < 250; i++)
        ProximityEvent(DateTime.fromMillisecondsSinceEpoch(1000 + i), 'unlock_ok', 'n$i')
    ];
    final back = ActivityHistory.decode(ActivityHistory.encode(ev));
    expect(back.length, ActivityHistory.capacity);
    expect(back.last.detail, 'n249');
    expect(back.first.detail, 'n50');
  });
  test('dữ liệu hỏng → rỗng, mục lỗi bị bỏ qua', () {
    expect(ActivityHistory.decode('không phải json'), isEmpty);
    expect(ActivityHistory.decode(null), isEmpty);
    expect(ActivityHistory.decode('[{"t":1,"k":"lock_ok"},{"x":1},5]').length, 1);
  });
  test('không lưu sự kiện zone', () {
    expect(isPersistable(ProximityEvent(DateTime(2026), 'zone', 'near')), isFalse);
    expect(isPersistable(ProximityEvent(DateTime(2026), 'lock_ok', '')), isTrue);
  });
}
