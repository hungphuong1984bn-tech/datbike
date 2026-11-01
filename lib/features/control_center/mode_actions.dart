// Hành động bật/tắt Grab và ECE dùng chung cho Trung tâm điều khiển và tab Tổng quan.
//
// Quy trình an toàn GIỮ NGUYÊN (docs/CONTROL_CENTER.md): kiểm tra điều kiện
// (đã kết nối, xe đứng yên, telemetry mới) → hộp thoại xác nhận → gửi → ĐỌC LẠI
// từ xe → chỉ "đã xác nhận" khi đọc lại khớp. Không tự thử lại.
// Chỉ chạy khi người dùng gạt công tắc; không có đường tự động nào gọi các hàm này.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/control/mode_controller.dart';
import '../../core/regen/regen_controller.dart' show regenLinkReaderProvider;
import '../../core/regen/regen_protocol.dart' show regenBlockReason;

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
            key: const Key('confirm_cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY')),
        FilledButton(
            key: const Key('confirm_ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action)),
      ],
    ),
  );
  return r == true;
}

/// Kiểm tra điều kiện TRƯỚC khi hỏi xác nhận; engine vẫn kiểm lại lúc gửi.
bool _preflight(BuildContext context, WidgetRef ref) {
  final reason = regenBlockReason(
    ref.read(regenLinkReaderProvider)(),
    requiresStandstill: true,
  );
  if (reason != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Không gửi: $reason')));
    return false;
  }
  return true;
}

Future<void> toggleGrabMode(BuildContext context, WidgetRef ref, bool target) async {
  if (!_preflight(context, ref)) return;
  final ok = await _confirm(
    context,
    target ? 'Bật Grab?' : 'Tắt Grab?',
    'App sẽ gửi giá trị ${target ? "1" : "0"} tới kênh Grab (a1d8e7c4) rồi đọc lại từ xe để xác nhận.\n\n'
    '• Chỉ đổi khi xe đứng yên.\n'
    '• Người dùng đã quan sát rằng đổi kênh này làm thay đổi dòng nạp ngược; '
    'chưa đo hướng mạnh/yếu nên app không khẳng định.\n'
    '• Nếu xe không xác nhận, app hiển thị KHÔNG XÁC NHẬN và không tự gửi lại.',
    target ? 'BẬT GRAB' : 'TẮT GRAB',
  );
  if (!ok || !context.mounted) return;
  await ref.read(grabModeProvider.notifier).command(target);
}

Future<void> toggleEceMode(BuildContext context, WidgetRef ref, bool target) async {
  if (!_preflight(context, ref)) return;
  final ok = await _confirm(
    context,
    target ? 'Bật ECE (giới hạn tốc độ)?' : 'Tắt ECE (bỏ giới hạn tốc độ)?',
    target
        ? 'App sẽ ghi cờ SpeedLimit = 1 rồi cờ ECE = 1 và đọc lại cả hai từ xe.\n\n'
            '• Giới hạn chỉ có hiệu lực khi CẢ HAI cờ đọc lại = 1.\n'
            '• Khi ECE bật, xe KHÔNG cho chuyển chế độ lái (Lab 24/10); muốn chuyển phải tắt ECE.\n'
            '• Mức trần 60 km/h theo ghi chú dự án, chưa có số đo độc lập.'
        : 'App sẽ ghi SpeedLimit = 0 rồi ECE = 0 và đọc lại từ xe.\n\n'
            '• Đây là tắt tuỳ chọn giới hạn do firmware cung cấp; xe vẫn chịu các '
            'giới hạn an toàn khác của nhà sản xuất.\n'
            '• Theo ghi chú Lab, nên tắt/mở nguồn xe để bộ điều tốc giải phóng trần cũ.\n'
            '• Chỉ đổi khi xe đứng yên.',
    target ? 'BẬT ECE' : 'TẮT ECE',
  );
  if (!ok || !context.mounted) return;
  await ref.read(eceModeProvider.notifier).command(target);
}
