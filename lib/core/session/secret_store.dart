// SecretStore — nơi DUY NHẤT lưu dữ liệu nhạy cảm (mật khẩu phiên xe).
//
// Trước đây mật khẩu xe nằm trong SharedPreferences (XML thường, dễ bị đọc khi
// root/backup). Nay lưu bằng flutter_secure_storage (Android Keystore / iOS
// Keychain).
//
// TƯƠNG THÍCH NGƯỢC: người dùng cũ còn mật khẩu trong SharedPreferences →
// [readWithMigration] đọc ra, chép sang kho bảo mật rồi xóa bản cũ. Nếu kho
// bảo mật lỗi (thiết bị lạ/Keystore hỏng) thì GIỮ NGUYÊN bản trong
// SharedPreferences để không bao giờ làm mất mật khẩu → không phải ghép đôi lại.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecretStore {
  SecretStore._();
  static final SecretStore instance = SecretStore._();

  static const FlutterSecureStorage _s = FlutterSecureStorage();
  static const Duration _timeout = Duration(seconds: 4);

  /// Đọc từ kho bảo mật. null nếu chưa có hoặc kho lỗi.
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  /// Ghi vào kho bảo mật. true nếu thành công.
  Future<bool> write(String key, String value) async {
    try {
      await _s.write(key: key, value: value).timeout(_timeout);
      // Đọc lại để chắc chắn đã ghi được (một số máy ghi lỗi âm thầm).
      return (await _s.read(key: key).timeout(_timeout)) == value;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _s.delete(key: key).timeout(_timeout);
    } catch (_) {}
  }

  /// Lưu bí mật: ưu tiên kho bảo mật; chỉ khi kho lỗi mới dùng prefs (dự phòng).
  Future<void> save(SharedPreferences prefs, String key, String value) async {
    if (await write(key, value)) {
      if (prefs.containsKey(key)) await prefs.remove(key); // xóa bản thô cũ
    } else {
      await prefs.setString(key, value);
    }
  }

  /// Xóa ở cả hai nơi.
  Future<void> remove(SharedPreferences prefs, String key) async {
    await delete(key);
    await prefs.remove(key);
  }

  /// Đọc: kho bảo mật trước; nếu không có thì lấy bản cũ ở prefs ([legacy] do
  /// caller đọc, giữ nguyên kiểm tra kiểu/lỗi cũ) rồi di chuyển sang kho mới.
  Future<String?> readWithMigration(
    SharedPreferences prefs,
    String key,
    String? Function() legacy,
  ) async {
    final secure = await read(key);
    if (secure != null && secure.isNotEmpty) {
      if (prefs.containsKey(key)) await prefs.remove(key);
      return secure;
    }
    final old = legacy();
    if (old != null && old.isNotEmpty) {
      if (await write(key, old)) await prefs.remove(key);
    }
    return old;
  }
}
