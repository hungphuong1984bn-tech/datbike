// Ứng viên (pairingToken, password) cho handshake — cập nhật 2026-10-19 (tối).
//
// Auth response (Phase 1) chỉ phụ thuộc pairingToken. Password chỉ tham gia
// vào deriveSessionKey (Phase 2) — và hiện là ẩn số duy nhất còn lại.
//
// Quan trọng từ thực nghiệm 2026-10-19 tối: PIN TRỐNG phải được thử THẬT SỰ
// (chuỗi rỗng làm IKM) — giả thuyết của người dùng rằng xe pair mà chưa đặt
// mật khẩu (firmware: nvs_get_blob 'password' thiếu → chuỗi rỗng). Bản cũ tự
// thay '58607' khi ô trống nên chưa bao giờ test được empty.
//
// Mỗi ứng viên password được gửi 1 pin-write + kiểm tra counter dashboard
// (oracle duy nhất: counter TĂNG giữa 2 lần đọc = session hợp lệ).

class AuthVariant {
  final String label;
  final String pairingToken;
  final String password;

  const AuthVariant(this.label, this.pairingToken, this.password);
}

/// Danh sách biến viên password, thứ tự ưu tiên theo input người dùng.
/// [pairingToken] rỗng → dùng token firmware fw 1.14.0 (đã crack).
List<AuthVariant> buildAuthVariants({
  String pairingToken = '',
  String password = '',
}) {
  final token = pairingToken.isNotEmpty
      ? pairingToken
      : 'c97eb99d-c695-4b5f-8a99-7b24ff2a7980';
  final out = <AuthVariant>[];
  void add(String label, String pw) {
    if (out.any((v) => v.password == pw)) return;
    out.add(AuthVariant(label, token, pw));
  }

  if (password.isNotEmpty) {
    add('user-input', password);
  }
  // '5bMO8m3wF9q3' — ĐÃ CRACK + VERIFY bằng tag thật của btsnoop conn1
  // (2026-10-14 16:16): đây là password 12 ký tự app gốc TỰ SINH và ghi lên
  // xe lúc pair (qua c8eaf27b — firmware "Setting new password"). KHÔNG phải
  // số máy — "6 chữ số cuối số động cơ" chỉ là prompt verify UI.
  add('cracked "5bMO8m3wF9q3"', '5bMO8m3wF9q3');
  add('motor "304396"', '304396');
  add('default "58607"', '58607');
  add('empty (không password)', '');
  return out;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
