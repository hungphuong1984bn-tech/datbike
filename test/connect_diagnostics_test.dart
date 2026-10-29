import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/connect_diagnostics.dart';

/// Đồng hồ giả: mỗi lần gọi tiến thêm [step] ms — để kiểm tra timestamp/elapsed.
Clock fakeClock({int step = 100}) {
  var t = DateTime.utc(2026, 10, 29, 8, 0, 0);
  return () {
    final now = t;
    t = t.add(Duration(milliseconds: step));
    return now;
  };
}

void main() {
  group('ConnectStateMachine — điểm cuối thành công / đầu thất bại', () {
    test('luồng thành công đầy đủ: không có thất bại, bước cuối = telemetry', () {
      final m = ConnectStateMachine(clock: fakeClock());
      for (final s in ConnectStage.values.where((s) =>
          s != ConnectStage.permissions &&
          s != ConnectStage.adapter &&
          s != ConnectStage.scan &&
          s != ConnectStage.selectDevice)) {
        m.start(s);
        m.ok(s);
      }
      expect(m.firstFailure, isNull);
      expect(m.lastSuccess, equals(ConnectStage.telemetry));
      expect(m.succeeded, isTrue);
    });

    test('thất bại ở authResponse: lastSuccess = authChallenge, firstFailure = authResponse', () {
      final m = ConnectStateMachine(clock: fakeClock());
      for (final s in [
        ConnectStage.gattConnect,
        ConnectStage.mtu,
        ConnectStage.bonding,
        ConnectStage.discoverServices,
        ConnectStage.readFirmware,
        ConnectStage.authChallenge,
      ]) {
        m.start(s);
        m.ok(s);
      }
      m.start(ConnectStage.authResponse);
      m.fail(ConnectFailure(ConnectStage.authResponse,
          ConnectFailureKind.authRejected, 'status 0x00 sau 3 lần ghi'));
      expect(m.lastSuccess, equals(ConnectStage.authChallenge));
      expect(m.firstFailure!.stage, equals(ConnectStage.authResponse));
      expect(m.firstFailure!.kind, equals(ConnectFailureKind.authRejected));
      expect(m.succeeded, isFalse);
    });

    test('chỉ giữ thất bại ĐẦU TIÊN, thất bại sau không ghi đè', () {
      final m = ConnectStateMachine(clock: fakeClock());
      m.start(ConnectStage.gattConnect);
      m.fail(ConnectFailure(ConnectStage.gattConnect,
          ConnectFailureKind.gattConnectFailed, 'a',
          code: 133));
      m.fail(ConnectFailure(ConnectStage.discoverServices,
          ConnectFailureKind.serviceDiscoveryFailed, 'b'));
      expect(m.firstFailure!.stage, equals(ConnectStage.gattConnect));
      expect(m.firstFailure!.code, equals(133));
    });

    test('warn (MTU) KHÔNG làm hỏng kết nối và không đặt firstFailure', () {
      final m = ConnectStateMachine(clock: fakeClock());
      m.start(ConnectStage.mtu);
      m.warn(ConnectStage.mtu, 'requestMtu timeout, dùng MTU hiện tại 23');
      expect(m.firstFailure, isNull);
      expect(m.lastSuccess, isNull);
    });

    test('beginAttempt xóa dấu vết lần trước nhưng GIỮ bằng chứng bond', () {
      final m = ConnectStateMachine(clock: fakeClock());
      m.bondEvidence.recordEncryptionError(bondedAtTime: true);
      m.start(ConnectStage.gattConnect);
      m.fail(ConnectFailure(ConnectStage.gattConnect,
          ConnectFailureKind.gattConnectFailed, 'x'));
      m.beginAttempt();
      expect(m.firstFailure, isNull);
      expect(m.steps, isEmpty);
      expect(m.bondEvidence.encryptionErrorsWhileBonded, equals(1));
    });

    test('elapsed + timestamp được ghi theo đồng hồ', () {
      final m = ConnectStateMachine(clock: fakeClock(step: 250));
      m.start(ConnectStage.gattConnect);
      m.ok(ConnectStage.gattConnect);
      final okStep =
          m.steps.firstWhere((s) => s.outcome == StepOutcome.ok);
      expect(okStep.elapsed.inMilliseconds, greaterThan(0));
      expect(okStep.toJson()['ts'], isNotNull);
    });
  });

  group('Báo cáo chẩn đoán', () {
    test('nêu rõ bước cuối thành công và bước đầu thất bại', () {
      final m = ConnectStateMachine(clock: fakeClock());
      m.start(ConnectStage.gattConnect);
      m.ok(ConnectStage.gattConnect);
      m.start(ConnectStage.discoverServices);
      m.fail(ConnectFailure(ConnectStage.discoverServices,
          ConnectFailureKind.serviceDiscoveryFailed, 'timeout',
          code: 133, timeout: const Duration(seconds: 15)));
      final r = m.buildReport(appBuild: 'testbuild');
      expect(r, contains('Bước cuối cùng thành công: gattConnect'));
      expect(r, contains('Bước đầu tiên thất bại: discoverServices'));
      expect(r, contains('Mã lỗi: 133'));
      expect(r, contains('Timeout áp dụng: 15000 ms'));
      expect(r, contains('Build: testbuild'));
    });

    test('báo cáo KHÔNG chứa bí mật đã đăng ký hay chuỗi hex dài', () {
      Redactor.clearSecretsForTest();
      Redactor.registerSecret('5bMO8m3wF9q3');
      Redactor.registerSecret('c97eb99d-c695-4b5f-8a99-7b24ff2a7980');
      final m = ConnectStateMachine(clock: fakeClock());
      m.start(ConnectStage.authResponse);
      m.fail(ConnectFailure(
          ConnectStage.authResponse,
          ConnectFailureKind.appAuthFailed,
          'lỗi với password=5bMO8m3wF9q3 token c97eb99d-c695-4b5f-8a99-7b24ff2a7980 '
          'resp da18e1345f09f5516e0b800238aef13ca8e1e9825c7dec6d2a7e59d38c901a4b'));
      final r = m.buildReport();
      expect(r.contains('5bMO8m3wF9q3'), isFalse);
      expect(r.contains('c97eb99d-c695-4b5f-8a99-7b24ff2a7980'), isFalse);
      expect(r.contains('da18e1345f09f5516e0b800238aef13c'), isFalse);
      Redactor.clearSecretsForTest();
    });
  });

  group('classifyError — không gộp mọi lỗi thành connect_failed', () {
    test('timeout ở gattConnect → gattConnectTimeout', () {
      final f = classifyError(
          ConnectStage.gattConnect, 'FlutterBluePlusException | connect | fbp-code: 1 | timeout',
          timeout: const Duration(seconds: 10));
      expect(f.kind, equals(ConnectFailureKind.gattConnectTimeout));
      expect(f.timeout!.inSeconds, equals(10));
    });

    test('android-code 133 ở gattConnect → gattConnectFailed, giữ mã', () {
      final f = classifyError(ConnectStage.gattConnect,
          'FlutterBluePlusException | connect | android-code: 133 | GATT_ERROR');
      expect(f.kind, equals(ConnectFailureKind.gattConnectFailed));
      expect(f.code, equals(133));
    });

    test('mã 5 / 15 / 137 → encryptionRequired (theo MÃ SỐ)', () {
      for (final code in [5, 15, 137]) {
        final f = classifyError(ConnectStage.authChallenge,
            'FlutterBluePlusException | readCharacteristic | android-code: $code | x');
        expect(f.kind, equals(ConnectFailureKind.encryptionRequired),
            reason: 'code $code');
      }
    });

    test('chuỗi chứa "137" ngẫu nhiên KHÔNG bị coi là lỗi auth', () {
      final f = classifyError(
          ConnectStage.discoverServices, 'device AA:BB:137:CC rssi -50 lỗi lạ');
      expect(f.kind, isNot(ConnectFailureKind.encryptionRequired));
    });

    test('messageOverride thay thông điệp mặc định', () {
      final f = ConnectFailure(ConnectStage.gattConnect,
          ConnectFailureKind.storageCorrupt, 'x',
          messageOverride: 'Gỡ app và cài lại');
      expect(f.userMessage, equals('Gỡ app và cài lại'));
    });

    test('mã 8/19/22/34 hoặc "device is not connected" → linkLostDuringSetup', () {
      for (final code in [8, 19, 22, 34]) {
        final f = classifyError(ConnectStage.authResponse,
            'FlutterBluePlusException | writeCharacteristic | android-code: $code | x');
        expect(f.kind, equals(ConnectFailureKind.linkLostDuringSetup),
            reason: 'code $code');
      }
      final g = classifyError(ConnectStage.authChallenge,
          'FlutterBluePlusException | readCharacteristic | fbp-code: 6 | device is not connected');
      expect(g.kind, equals(ConnectFailureKind.linkLostDuringSetup));
    });

    test('fbp-code (chỉ số FbpErrorCode) KHÔNG bị coi là mã ATT 5/15', () {
      // fbp-code 5 = removeBondFailed; trùng số với ATT 5 nhưng không liên quan.
      final f = classifyError(ConnectStage.bonding,
          'FlutterBluePlusException | removeBond | fbp-code: 5 | Failed to remove bond');
      expect(f.kind, isNot(ConnectFailureKind.encryptionRequired));
      expect(f.code, isNull);
    });

    test('ConnectFailure có sẵn được giữ nguyên, không bọc lại', () {
      final orig = ConnectFailure(ConnectStage.bonding,
          ConnectFailureKind.bondingRejected, 'user cancel');
      expect(identical(classifyError(ConnectStage.telemetry, orig), orig),
          isTrue);
    });

    test('thông điệp người dùng nêu đúng bước hỏng', () {
      final f = ConnectFailure(ConnectStage.discoverServices,
          ConnectFailureKind.serviceDiscoveryFailed, 'x',
          code: 133);
      expect(f.userMessage, contains('khám phá dịch vụ'));
      expect(f.userMessage, contains('133'));
    });

    test('mọi ConnectFailureKind đều có userMessage không rỗng', () {
      for (final k in ConnectFailureKind.values) {
        final f = ConnectFailure(ConnectStage.gattConnect, k, 'd', code: 133);
        expect(f.userMessage, isNotEmpty, reason: k.name);
      }
    });
  });

  group('BondEvidence — không tự kết luận bond lệch từ số lần thất bại', () {
    test('một lỗi mã hóa đơn lẻ KHÔNG đủ bằng chứng', () {
      final e = BondEvidence()..recordEncryptionError(bondedAtTime: true);
      expect(e.suspected, isFalse);
    });

    test('lỗi mã hóa khi CHƯA bond không tính là bằng chứng mismatch', () {
      final e = BondEvidence();
      for (var i = 0; i < 5; i++) {
        e.recordEncryptionError(bondedAtTime: false);
      }
      expect(e.suspected, isFalse);
    });

    test('lỗi mã hóa lặp lại dù hệ thống báo đã bond → nghi mismatch', () {
      final e = BondEvidence()
        ..recordEncryptionError(bondedAtTime: true)
        ..recordEncryptionError(bondedAtTime: true);
      expect(e.suspected, isTrue);
    });

    test('bond biến mất (người dùng quên trên điện thoại) KHÔNG phải mismatch', () {
      final e = BondEvidence()..recordBondDisappeared();
      expect(e.suspected, isFalse);
      expect(e.toJson()['bond_disappeared_after_connect'], isTrue);
    });

    test('reset xóa toàn bộ bằng chứng', () {
      final e = BondEvidence()
        ..recordEncryptionError(bondedAtTime: true)
        ..recordEncryptionError(bondedAtTime: true)
        ..recordBondDisappeared();
      expect(e.repeatedEncryptionFailure, isTrue);
      e.reset();
      expect(e.repeatedEncryptionFailure, isFalse);
      expect(e.bondDisappearedAfterConnect, isFalse);
    });

    test('thông điệp mismatch không bảo người dùng bị xóa bond tự động', () {
      final f = ConnectFailure(ConnectStage.authChallenge,
          ConnectFailureKind.bondMismatchSuspected, 'x');
      expect(f.userMessage, contains('KHÔNG tự xóa bond'));
    });
  });

  group('Redactor', () {
    test('event xác thực: trường nhạy cảm bị che, trường độ dài/status giữ', () {
      final out = Redactor.sanitizeEvent('auto_handshake_start', {
        'token': 'c97eb99d-c695-4b5f-8a99-7b24ff2a7980',
        'pin': '58607',
        'password': 'abc',
        'session_key': 'deadbeef',
        'respHex': 'aa',
        'pin_len': 5,
        'status': 1,
        'nonce_fp': 'a1b2c3d4',
      });
      expect(out['token'], equals('«redacted»'));
      expect(out['pin'], equals('«redacted»'));
      expect(out['password'], equals('«redacted»'));
      expect(out['session_key'], equals('«redacted»'));
      expect(out['respHex'], equals('«redacted»'));
      expect(out['pin_len'], equals(5));
      expect(out['status'], equals(1));
      expect(out['nonce_fp'], equals('a1b2c3d4'));
    });

    test('event phase1/phase2 của AuthProbe cũng được che (raw, challenge, key8)', () {
      final a = Redactor.sanitizeEvent('phase1_challenge',
          {'raw': 'aa bb', 'challenge_15B': 'cc', 'initial_status': 0});
      expect(a['raw'], equals('«redacted»'));
      expect(a['challenge_15B'], equals('«redacted»'));
      expect(a['initial_status'], equals(0));
      final b = Redactor.sanitizeEvent('phase2_session_key',
          {'salt_nonce': 'dd', 'key8': 'ee'});
      expect(b['salt_nonce'], equals('«redacted»'));
      expect(b['key8'], equals('«redacted»'));
    });

    test('event KHÔNG phải xác thực (Firmware Lab/GATT table) giữ nguyên hex & UUID', () {
      final out = Redactor.sanitizeEvent('char_read', {
        'uuid': 'd1da175e-b1b5-4248-8f36-98c9482b8d24',
        'hex': '31 2e 31 34 2e 30',
        'utf8': '1.14.0',
      });
      expect(out['uuid'], equals('d1da175e-b1b5-4248-8f36-98c9482b8d24'));
      expect(out['hex'], equals('31 2e 31 34 2e 30'));
      expect(out['utf8'], equals('1.14.0'));
    });

    test('bảng GATT (map lồng) giữ nguyên UUID công khai', () {
      final out = Redactor.sanitizeEvent('gatt_table', {
        'services': [
          {
            'service': '10cb0217-ff02-4474-a1ef-6fd88b5bdaea',
            'characteristics': [
              {
                'uuid': '5e9a2c71-0b3d-4f86-a1c2-7d4e8f0b9a63',
                'properties': ['read', 'write']
              }
            ]
          }
        ]
      });
      final svc = (out['services'] as List).first as Map;
      expect(svc['service'], equals('10cb0217-ff02-4474-a1ef-6fd88b5bdaea'));
    });

    test('bí mật đã đăng ký bị che ở MỌI loại event, kể cả không strict', () {
      Redactor.clearSecretsForTest();
      Redactor.registerSecret('SuperSecretPw12');
      final out = Redactor.sanitizeEvent(
          'establish_err', {'error': 'lỗi khi dùng SuperSecretPw12 để ghi'});
      expect((out['error'] as String).contains('SuperSecretPw12'), isFalse);
      Redactor.clearSecretsForTest();
    });

    test('bí mật quá ngắn (<4) không đăng ký để tránh che nhầm hàng loạt', () {
      Redactor.clearSecretsForTest();
      Redactor.registerSecret('12');
      expect(Redactor.scrubText('giá trị 12 và 123'), equals('giá trị 12 và 123'));
    });

    test('scrubText che password=..., hex dài; fingerprint ổn định và ngắn', () {
      expect(Redactor.scrubText('password=hunter2 ok'),
          equals('password=«redacted» ok'));
      expect(Redactor.scrubText('x ${'a' * 64} y'), equals('x «hex» y'));
      final a = Redactor.fingerprint([1, 2, 3]);
      final b = Redactor.fingerprint([1, 2, 3]);
      expect(a, equals(b));
      expect(a.length, equals(8));
    });

    test('nhận diện khóa nhạy cảm', () {
      for (final k in [
        'token',
        'pin',
        'password',
        'candidate_pw',
        'session_key',
        'respHex',
        'new_password',
        'salt',
      ]) {
        expect(Redactor.isSensitiveKey(k), isTrue, reason: k);
      }
      for (final k in ['pin_len', 'status', 'nonce_fp', 'has_stored', 'mtu', 'elapsed_ms']) {
        expect(Redactor.isSensitiveKey(k), isFalse, reason: k);
      }
    });
  });

  group('Chính sách retry theo loại lỗi', () {
    test('lỗi quyền/adapter/busy/dữ liệu hỏng/thiếu dịch vụ KHÔNG retry', () {
      for (final k in [
        ConnectFailureKind.permissionDenied,
        ConnectFailureKind.permissionPermanentlyDenied,
        ConnectFailureKind.adapterOff,
        ConnectFailureKind.busy,
        ConnectFailureKind.storageCorrupt,
        ConnectFailureKind.requiredServiceMissing,
        ConnectFailureKind.bondMismatchSuspected,
        ConnectFailureKind.bondingRejected,
        ConnectFailureKind.sessionKeyInvalid,
      ]) {
        expect(isRetryable(k), isFalse, reason: k.name);
        expect(maxAttemptsFor(k), equals(1), reason: k.name);
      }
    });

    test('lỗi link/GATT/xe từ chối retry; authRejected giữ 5 lần × 3s', () {
      expect(isRetryable(ConnectFailureKind.gattConnectFailed), isTrue);
      expect(isRetryable(ConnectFailureKind.linkLostDuringSetup), isTrue);
      expect(maxAttemptsFor(ConnectFailureKind.gattConnectTimeout), equals(3));
      expect(maxAttemptsFor(ConnectFailureKind.authRejected), equals(5));
      expect(retryDelay(ConnectFailureKind.authRejected).inSeconds, equals(3));
      expect(retryDelay(ConnectFailureKind.gattConnectFailed).inSeconds, equals(2));
    });

    test('isRetryable và maxAttemptsFor nhất quán với mọi loại lỗi', () {
      for (final k in ConnectFailureKind.values) {
        expect(maxAttemptsFor(k) > 1, equals(isRetryable(k)), reason: k.name);
      }
    });
  });

  group('MTU thực tế', () {
    test('payload = MTU − 3, tối thiểu 20', () {
      expect(maxAttPayload(517), equals(514));
      expect(maxAttPayload(247), equals(244));
      expect(maxAttPayload(23), equals(20));
      expect(maxAttPayload(10), equals(20));
    });

    test('khung 64B xác thực c8eaf27b cần MTU ≥ 67 (không giả định 517)', () {
      expect(mtuFitsPayload(23, 64), isFalse);
      expect(mtuFitsPayload(67, 64), isTrue);
      expect(mtuFitsPayload(247, 64), isTrue);
    });
  });

  group('describeGattCode / extractCodeFromText', () {
    test('mô tả mã Android phổ biến', () {
      expect(describeGattCode(133), contains('GATT_ERROR'));
      expect(describeGattCode(137), contains('AUTH'));
      expect(describeGattCode(8), contains('timeout'));
      expect(describeGattCode(999), contains('999'));
    });

    test('rút mã từ chuỗi FlutterBluePlusException', () {
      expect(
          extractCodeFromText(
              'FlutterBluePlusException | connect | android-code: 133 | x'),
          equals(133));
      expect(extractCodeFromText('không có mã'), isNull);
    });
  });
}
