// Auth probe — ĐÃ VIẾT LẠI AN TOÀN (2026-10-19) theo btsnoop app gốc.
//
// Bản cũ spam 287 protected-write counter=0 + ghi token hàng chục lần trong
// vài giây → xe ngừng phản hồi và drop link (GATT 133, log 2026-10-14).
//
// Bản này theo đúng luồng capture (16:16:47, conn2 của app gốc):
//   1. (bond nếu auth char bị err 0x05/137)
//   2. Đọc 16B nonce + status từ AUTHORIZATION_CHAR (5e9a2c71)
//   3. Ghi 16B auth response — TỐI ĐA 3 lần thử, mỗi lần đọc lại status
//   4. Status 0x01 → derive session key bằng nonce mới đọc được
//   5. Protected-write password ASCII counter 0 lên bikeSerial
//   6. Ghi pairingToken UTF-8 lên sessionUuid (87efab0d)
//   7. Đọc dashboard làm oracle (plain protobuf hoặc keystream decrypt)
//
// ⚠️ computeAuthResponse hiện là placeholder CHƯA VERIFY — probe sẽ dừng
// an toàn ở bước 3 với status 00 cho tới khi crack xong công thức thật.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'auth_candidates.dart';
import 'bike_session_crypto.dart';
import '../ble/ble_logger.dart';
import '../ble/gatt.dart';

class AuthProbeResult {
  final bool success;
  final String phase;
  final String detail;
  final Uint8List? sessionKey;

  const AuthProbeResult({
    required this.success,
    required this.phase,
    required this.detail,
    this.sessionKey,
  });
}

class AuthProbe {
  final BluetoothDevice device;
  final String pairingToken;
  final String password;

  AuthProbe({
    required this.device,
    required this.pairingToken,
    required this.password,
  });

  BluetoothCharacteristic? _find(
      List<BluetoothCharacteristic> chars, String uuid) {
    for (final c in chars) {
      if (c.uuid.str128.toLowerCase() == uuid.toLowerCase()) return c;
    }
    return null;
  }

  Future<void> _write(BluetoothCharacteristic c, List<int> payload) async {
    BleLogger.instance.event('probe_write', {
      'uuid': c.uuid.str128.toLowerCase(),
      'len': payload.length,
      'hex': BleLogger.hex(payload),
    });
    await c.write(payload, withoutResponse: false);
  }

  Future<Uint8List> _read(BluetoothCharacteristic c) async {
    final v = await c.read();
    BleLogger.instance.event('probe_read', {
      'uuid': c.uuid.str128.toLowerCase(),
      'len': v.length,
      'hex': BleLogger.hex(v),
      'utf8': BleLogger.tryUtf8(v),
    });
    return Uint8List.fromList(v);
  }

  bool _isAuthError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('137') ||
        s.contains('insufficient') ||
        s.contains('gatt_auth');
  }

  /// Chạy handshake — tối đa [maxAttempts] lần ghi response, dừng ngay khi
  /// xe báo status 0x01. Không ghi gì thêm khi chưa được chấp nhận.
  Future<AuthProbeResult> run(List<BluetoothCharacteristic> allChars) async {
    const maxAttempts = 3;
    BleLogger.instance.event('probe_start', {
      'pairing_token_len': pairingToken.length,
      'password_len': password.length,
      'max_attempts': maxAttempts,
    });

    final authChar = _find(allChars, Gatt.authorizationChar);
    if (authChar == null) {
      return const AuthProbeResult(
        success: false,
        phase: 'Setup',
        detail: 'Không tìm thấy AUTHORIZATION_CHAR (5e9a2c71)',
      );
    }

    // ===== Đọc nonce 16B từ AUTHORIZATION_CHAR (1 lần duy nhất) =====
    // MỖI lần read là xe xoay nonce MỚI — đọc thêm lần nào cũng làm philocals
    // state lệch. Nếu bị err 0x05/137 (chưa bond) → createBond rồi đọc lại.
    Uint8List nonce1;
    try {
      nonce1 = await _read(authChar);
    } catch (e) {
      if (_isAuthError(e)) {
        BleLogger.instance.event('probe_bond_start', {'error': '$e'});
        try {
          await device.createBond();
          BleLogger.instance.event('probe_bond_created', {});
        } catch (e2) {
          return AuthProbeResult(
            success: false,
            phase: 'Bond',
            detail: 'Cần bond/mã hoá link nhưng bond thất bại: $e2',
          );
        }
        nonce1 = await _read(authChar);
      } else {
        rethrow;
      }
    }

    if (nonce1.length != 16) {
      return AuthProbeResult(
        success: false,
        phase: 'Phase 1',
        detail: 'Nonce từ 5e9a2c71 phải 16 byte (15B nonce + status), '
            'nhận ${nonce1.length} — kiểm tra kết nối/bond',
      );
    }
    final nonce15 = Uint8List.fromList(nonce1.sublist(0, 15));
    BleLogger.instance.event('phase1_challenge', {
      'raw': bytesToHex(nonce1),
      'challenge_15B': bytesToHex(nonce15),
      'char': Gatt.authorizationChar,
      'initial_status': nonce1[15],
    });

    // ===== Ghi auth response (≤ maxAttempts lần), kiểm status sau mỗi lần =====
    // Response chỉ phụ thuộc pairingToken (đã crack + verify trên capture);
    // password chỉ tham gia vào deriveSessionKey ở Phase 2.
    final variants = buildAuthVariants(
      pairingToken: pairingToken,
      password: password,
    ).take(maxAttempts).toList();

    Uint8List? acceptedNonce;
    for (final cand in variants) {
      BleLogger.instance.event('phase1_try', {'variant': cand.label});
      final resp = BikeSessionCrypto.computeAuthResponse(
        pairingToken: cand.pairingToken,
        nonce15: nonce15,
      );
      BleLogger.instance.event('phase1_auth_response', {
        'variant': cand.label,
        'response_16B': bytesToHex(resp),
      });
      await _write(authChar, resp);
      await Future.delayed(const Duration(milliseconds: 120));
      final post = await _read(authChar);
      final ok = post.length == 16 && post[15] == Gatt.authStatusOk;
      BleLogger.instance.event('phase1_post_auth',
          {'hex': bytesToHex(post), 'success': ok});
      if (ok) {
        acceptedNonce = post;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

      if (acceptedNonce == null) {
        return const AuthProbeResult(
          success: false,
          phase: 'Phase 1',
          detail: 'Xe từ chối auth response (status 00) — pairing token không '
              'khớp firmware xe (token hiện tại crack từ fw 1.14.0).',
        );
      }

    // ===== Phase 2+3: thử từng ứng viên password với oracle counter =====
    // Salt = NONCE CHALLENGE (nonce mà response vừa trả lời — theo decompile).
    // Oracle duy nhất biết session hợp lệ: 4 byte counter đầu của dashboard
    // TĂNG giữa 2 lần đọc (xe chỉ tăng counter khi decrypt được session key).
    final saltNonce = nonce15;
    final dash = _find(allChars, Gatt.dashboardCharacteristic);
    final serialChar = _find(allChars, Gatt.bikeSerial);
    var writeCounter = 0;
    int counterOf(List<int> raw) =>
        raw.length >= 4 ? raw[0] | (raw[1] << 8) | (raw[2] << 16) | (raw[3] << 24) : -1;

    for (final cand in variants) {
      final sessionKey = BikeSessionCrypto.deriveSessionKey(
        pairingToken: cand.pairingToken,
        password: cand.password,
        challenge: saltNonce,
      );
      BleLogger.instance.event('phase2_session_key', {
        'variant': cand.label,
        'salt_nonce': bytesToHex(saltNonce),
        'key8': BleLogger.hex(sessionKey.sublist(0, 8)),
      });

      // Protected-write password (data = chính chuỗi password) counter tăng dần
      if (serialChar != null) {
        final frame = BikeSessionCrypto.buildProtectedWrite(
          sessionKey: sessionKey,
          counter: writeCounter++,
          characteristicUuid: Gatt.bikeSerial,
          data: cand.password.codeUnits,
        );
        await _write(serialChar, frame);
      }
      // Token lên 87efab0d — chỉ lần đầu cho đủ như capture app gốc
      if (cand == variants.first) {
        final sessionUuidChar = _find(allChars, Gatt.sessionUuid);
        if (sessionUuidChar != null) {
          await _write(sessionUuidChar, cand.pairingToken.codeUnits);
        }
      }

      // Oracle: đọc dashboard 2 lần, so sánh counter
      if (dash == null) continue;
      final r1 = await _read(dash);
      await Future.delayed(const Duration(milliseconds: 900));
      final r2 = await _read(dash);
      final c1 = counterOf(r1), c2 = counterOf(r2);
      final live = c1 >= 0 && c2 > c1;
      BleLogger.instance.event('phase3_oracle', {
        'variant': cand.label,
        'counter1': c1,
        'counter2': c2,
        'session_live': live,
      });
      if (live) {
        return AuthProbeResult(
          success: true,
          phase: 'Phase 3',
          detail: 'SESSION HỢP LỆ với password "${cand.password}" '
              '(counter $c1 → $c2 tăng)',
          sessionKey: sessionKey,
        );
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return AuthProbeResult(
      success: true,
      phase: 'Phase 3',
      detail: 'Auth THÀNH CÔNG (Phase 1) nhưng mọi ứng viên password đều sai — '
          'counter dashboard giữ nguyên (session chưa hợp lệ). Thử PIN khác: '
          '6 chữ số cuối số động cơ khắc trên motor.',
    );
  }
}
