import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/ble_permission_policy.dart';

BlePermissionResult d(
  int sdk, {
  PermState scan = PermState.granted,
  PermState connect = PermState.granted,
  PermState location = PermState.granted,
  bool locService = true,
}) =>
    decideBlePermission(
      sdkInt: sdk,
      scan: scan,
      connect: connect,
      location: location,
      locationServiceEnabled: locService,
    );

void main() {
  group('Android 12+ (API 31+)', () {
    test('scan + connect granted → granted, không cần vị trí', () {
      expect(d(34, location: PermState.denied), equals(BlePermissionResult.granted));
    });
    test('thiếu BLUETOOTH_CONNECT → denied (không đủ dù có scan)', () {
      expect(d(33, connect: PermState.denied), equals(BlePermissionResult.denied));
    });
    test('thiếu BLUETOOTH_SCAN dù có vị trí → denied', () {
      expect(d(31, scan: PermState.denied), equals(BlePermissionResult.denied));
    });
    test('connect bị từ chối vĩnh viễn → permanentlyDenied', () {
      expect(d(34, connect: PermState.permanentlyDenied),
          equals(BlePermissionResult.permanentlyDenied));
    });
    test('scan bị từ chối vĩnh viễn → permanentlyDenied', () {
      expect(d(32, scan: PermState.permanentlyDenied),
          equals(BlePermissionResult.permanentlyDenied));
    });
  });

  group('Android ≤ 11 (API ≤ 30)', () {
    test('vị trí granted + dịch vụ vị trí bật → granted', () {
      expect(d(30), equals(BlePermissionResult.granted));
    });
    test('vị trí granted nhưng dịch vụ vị trí TẮT → locationServiceOff', () {
      expect(d(29, locService: false),
          equals(BlePermissionResult.locationServiceOff));
    });
    test('vị trí denied → denied', () {
      expect(d(28, location: PermState.denied), equals(BlePermissionResult.denied));
    });
    test('vị trí permanentlyDenied → permanentlyDenied', () {
      expect(d(26, location: PermState.permanentlyDenied),
          equals(BlePermissionResult.permanentlyDenied));
    });
    test('quyền scan/connect KHÔNG được xét ở API ≤ 30', () {
      expect(
          d(30,
              scan: PermState.denied,
              connect: PermState.denied),
          equals(BlePermissionResult.granted));
    });
  });
}
