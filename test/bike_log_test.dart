// Test decode protobuf BikeLogMsg/BatteryLogMsg/ChargerLogMsg.
// 
// Byte được encode tay theo wire-format proto3 — đối chiếu docs/proto/bike.proto.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/proto/bike_log.dart';

Uint8List u8(List<int> xs) => Uint8List.fromList(xs);

// tag = (field << 3) | wire; wire: 0=varint 2=len 5=fixed32
List<int> varint(int v) {
  final out = <int>[];
  while (v > 0x7f) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> tag(int field, int wire) => varint((field << 3) | wire);

void main() {
  test('BikeLogMsg: speed/state/kmLeft/charging', () {
    // field 16 (speed) float 25.5: tag 0xCD 0x01, 4 byte LE
    final speed = <int>[...tag(16, 5), 0x00, 0x00, 0xCC, 0x41]; // 25.5f
    // field 13 (state) varint 3 = DRIVE
    final state = <int>[...tag(13, 0), 3];
    // field 21 (kmLeft) float 42.0
    final km = <int>[...tag(21, 5), 0x00, 0x00, 0x28, 0x42];
    // field 1 (name) string "Xe nha"
    final nameBytes = utf8.encode('Xe nha');
    final name = <int>[...tag(1, 2), ...varint(nameBytes.length), ...nameBytes];
    // ChargerLogMsg { power(5) = 1500 } lồng vào field 22
    final charger = <int>[...tag(5, 0), ...varint(1500)];
    final charging = <int>[...tag(22, 2), ...varint(charger.length), ...charger];

    final msg = decodeBikeLogMsg(u8([...name, ...state, ...speed, ...km, ...charging]));

    expect(msg.name, 'Xe nha');
    expect(msg.state, BikeState.drive);
    expect(msg.speed, closeTo(25.5, 0.001));
    expect(msg.kmLeft, closeTo(42.0, 0.001));
    expect(msg.charging, isNotNull);
    expect(msg.charging!.power, 1500);
  });

  test('BikeLogMsg: unknown field được bỏ qua', () {
    // field 99 wire 0 varint 5 — firmware mới thêm field lạ
    final unknown = <int>[...tag(99, 0), 5];
    final speed = <int>[...tag(16, 5), 0x00, 0x00, 0xCC, 0x41];
    final msg = decodeBikeLogMsg(u8([...unknown, ...speed]));
    expect(msg.speed, closeTo(25.5, 0.001));
  });

  test('BatteryLogMsg: cellVols packed + voltage', () {
    // field 12 (cellVols) packed float [3.85, 3.86]
    final f1 = ByteData(4)..setFloat32(0, 3.85, Endian.little);
    final f2 = ByteData(4)..setFloat32(0, 3.86, Endian.little);
    final body = [...f1.buffer.asUint8List(), ...f2.buffer.asUint8List()];
    final cells = <int>[...tag(12, 2), ...varint(body.length), ...body];
    // field 1 (voltage) float 58.4 = 0x4269999A
    final volt = <int>[...tag(1, 5), 0x9A, 0x99, 0x69, 0x42];
    // field 17 (socSoc) float 76.5 = 0x42990000
    final soc = <int>[...tag(17, 5), 0x00, 0x00, 0x99, 0x42];

    final m = decodeBatteryLogMsg(u8([...volt, ...cells, ...soc]));
    expect(m.voltage, closeTo(58.4, 0.001));
    expect(m.cellVols, hasLength(2));
    expect(m.cellVols[0], closeTo(3.85, 0.001));
    expect(m.cellVols[1], closeTo(3.86, 0.001));
    expect(m.socSoc, closeTo(76.5, 0.01));
  });

  test('decodeBikeLogMsg trên buffer rỗng trả về message rỗng', () {
    final m = decodeBikeLogMsg(u8([]));
    expect(m.state, BikeState.off);
    expect(m.name, '');
    expect(m.charging, isNull);
  });

  test('field với wire-type sai không làm desync phần sau', () {
    // field 16 (speed) nhưng wire 0 (varint) — sai kiểu; theo sau là field 21
    // (kmLeft float 42.0) viết đúng chuẩn — phải parse được kmLeft.
    final wrongWire = <int>[...tag(16, 0), 5]; // varint 5
    final km = <int>[...tag(21, 5), 0x00, 0x00, 0x28, 0x42];
    final m = decodeBikeLogMsg(u8([...wrongWire, ...km]));
    expect(m.speed, 0.0); // không decode được speed
    expect(m.kmLeft, closeTo(42.0, 0.001)); // nhưng kmLeft vẫn đúng
  });

  test('BatteryLogMsg: decode từ JSON UTF-8 payload (hỗ trợ 23 cell)', () {
    final cell23 = List.generate(23, (i) => 3.70 + (i * 0.005));
    final jsonString = jsonEncode({
      'voltage': 85.1,
      'current': 2.4,
      'balancing': 1,
      'protection': 0,
      'charge': true,
      'discharge': false,
      'cellVols': cell23,
      'NTCs': [31.5, 32.0, 31.8],
      'soc': {
        'V': 85.1,
        'I': 2.4,
        'soc': 82.5,
        'cycles': 145.0,
      },
    });

    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    final m = decodeBatteryLogMsg(bytes);

    expect(m.voltage, closeTo(85.1, 0.001));
    expect(m.current, closeTo(2.4, 0.001));
    expect(m.cellVols, hasLength(23));
    expect(m.cellVols.first, closeTo(3.70, 0.001));
    expect(m.cellVols.last, closeTo(3.81, 0.001));
    expect(m.socSoc, closeTo(82.5, 0.01));
    expect(m.socCycles, closeTo(145.0, 0.01));
  });
}
