// TRUNG TÂM ĐIỀU KHIỂN VẬN HÀNH — ba thẻ riêng: GRAB, ECE, REGEN.
//
// • Grab / ECE: công tắc thủ công. Công tắc luôn phản ánh giá trị ĐỌC TỪ XE;
//   không có giá trị cache, không tự bật khi mở màn hình/kết nối.
// • Mở màn hình chỉ ĐỌC (sync), không bao giờ ghi.
// • Mỗi lần đổi: kiểm tra điều kiện → hộp thoại xác nhận → gửi → đọc lại.
// • Regen: chỉ đọc (chưa có giao thức Regen độc lập được xác minh).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/control/mode_controller.dart';
import '../../core/control/mode_types.dart';
import '../../core/regen/regen_controller.dart' show regenLinkReaderProvider;
import '../../core/regen/regen_protocol.dart' show regenBlockReason;
import '../../ui/app_theme.dart';
import 'regen_monitor_card.dart';

/// Nhãn trạng thái hiển thị — tách riêng để test.
String modeStatusLabel(ModeState s) {
  switch (s.phase) {
    case ModePhase.unsupported:
      return 'KHÔNG HỖ TRỢ';
    case ModePhase.unverified:
      return 'CHƯA XÁC MINH';
    case ModePhase.disconnected:
      return 'CHƯA KẾT NỐI';
    case ModePhase.unread:
      return 'CHƯA ĐỌC TỪ XE';
    case ModePhase.sending:
      return 'ĐANG GỬI LỆNH';
    case ModePhase.verifying:
      return 'ĐANG ĐỌC TỪ XE';
    case ModePhase.blocked:
      return 'BỊ CHẶN (CHƯA GỬI)';
    case ModePhase.notConfirmed:
      return 'KHÔNG XÁC NHẬN';
    case ModePhase.confirmed:
      return s.on == true ? 'ĐÃ XÁC NHẬN · BẬT' : (s.on == false ? 'ĐÃ XÁC NHẬN · TẮT' : 'ĐÃ XÁC NHẬN');
    case ModePhase.ready:
      return s.on == true ? 'ĐANG BẬT' : (s.on == false ? 'ĐANG TẮT' : 'GIÁ TRỊ LẠ');
  }
}

class ControlCenterScreen extends ConsumerStatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  ConsumerState<ControlCenterScreen> createState() => _ControlCenterScreenState();
}

class _ControlCenterScreenState extends ConsumerState<ControlCenterScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Chỉ ĐỌC khi mở màn hình. Không có lệnh ghi nào ở đây.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(grabModeProvider.notifier).sync();
      ref.read(eceModeProvider.notifier).sync();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<bool> _confirm(String title, String body, String action) async {
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
  bool _preflight() {
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

  Future<void> _toggleGrab(bool target) async {
    if (!_preflight()) return;
    final ok = await _confirm(
      target ? 'Bật Grab?' : 'Tắt Grab?',
      'App sẽ gửi giá trị ${target ? "1" : "0"} tới kênh Grab (a1d8e7c4) rồi đọc lại từ xe để xác nhận.\n\n'
      '• Chỉ đổi khi xe đứng yên.\n'
      '• Người dùng đã quan sát rằng đổi kênh này làm thay đổi dòng nạp ngược; '
      'chưa đo hướng mạnh/yếu nên app không khẳng định.\n'
      '• Nếu xe không xác nhận, app hiển thị KHÔNG XÁC NHẬN và không tự gửi lại.',
      target ? 'BẬT GRAB' : 'TẮT GRAB',
    );
    if (!ok || !mounted) return;
    await ref.read(grabModeProvider.notifier).command(target);
  }

  Future<void> _toggleEce(bool target) async {
    if (!_preflight()) return;
    final ok = await _confirm(
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
    if (!ok || !mounted) return;
    await ref.read(eceModeProvider.notifier).command(target);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bleProvider); // làm mới theo kết nối/telemetry
    final grab = ref.watch(grabModeProvider);
    final ece = ref.watch(eceModeProvider);
    final link = ref.read(regenLinkReaderProvider)();
    final block = regenBlockReason(link, requiresStandstill: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Trung tâm điều khiển vận hành')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _linkBanner(link.speedKmh, block),
            const SizedBox(height: 14),
            _ModeCard(
              keyPrefix: 'grab',
              icon: Icons.inventory_2_rounded,
              title: 'GRAB MODE',
              description:
                  'Mục đích theo yêu cầu dự án: vận hành êm, hỗ trợ chở tải nặng. '
                  'Hiệu ứng cụ thể do firmware quyết định, app chưa đo. '
                  'Kênh a1d8e7c4 chỉ xác minh được hai giá trị 0/1.',
              state: grab,
              connected: link.connected,
              onSync: () => ref.read(grabModeProvider.notifier).sync(),
              onToggle: _toggleGrab,
            ),
            const SizedBox(height: 14),
            _ModeCard(
              keyPrefix: 'ece',
              icon: Icons.speed_rounded,
              title: 'ECE MODE',
              description:
                  'ECE OFF: tắt giới hạn tốc độ tuỳ chọn. ECE ON: giới hạn tốc độ '
                  'tối đa 60 km/h theo cấu hình firmware cung cấp (cần cả cờ ECE và SpeedLimit).',
              state: ece,
              connected: link.connected,
              onSync: () => ref.read(eceModeProvider.notifier).sync(),
              onToggle: _toggleEce,
              extra: _eceLimitNote(ece),
            ),
            const SizedBox(height: 14),
            const RegenMonitorCard(),
            const SizedBox(height: 14),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _eceLimitNote(ModeState s) {
    final snap = s.snapshot;
    String text;
    Color color = AppColors.textSecondary;
    if (snap == null) {
      text = 'Giới hạn 60 km/h: chưa đọc được từ xe.';
    } else {
      final eff = const EceModeSpec().limitEffective(snap);
      if (eff == true) {
        text = 'Giới hạn 60 km/h: ĐÃ XÁC NHẬN từ xe (ECE = 1 và SpeedLimit = 1). '
            'Con số 60 theo ghi chú dự án, chưa có số đo độc lập.';
        color = AppColors.greenText;
      } else if (snap.primaryRaw == 1 && snap.secondaryRaw == 0) {
        text = 'ECE đang bật nhưng cờ SpeedLimit = 0 → giới hạn tốc độ CHƯA có hiệu lực.';
        color = AppColors.amberText;
      } else if (snap.primaryRaw == 0) {
        text = 'ECE tắt → không áp giới hạn tốc độ ECE.';
      } else {
        text = 'Không xác định được hiệu lực giới hạn từ giá trị đọc được '
            '(ECE=${snap.primaryRaw}, SpeedLimit=${snap.secondaryRaw}).';
        color = AppColors.amberText;
      }
    }
    return Text(text,
        key: const Key('ece_limit_note'),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, height: 1.35));
  }

  Widget _linkBanner(double? speed, String? block) {
    final ok = block == null;
    final bg = ok ? AppColors.greenSoft : AppColors.amberSoft;
    final fg = ok ? AppColors.greenText : AppColors.amberText;
    return Container(
      key: const Key('cc_link_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? AppColors.greenSoftBorder : AppColors.amberSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? 'Đủ điều kiện gửi lệnh: đã kết nối, xe đứng yên'
                      '${speed == null ? "" : " (${speed.toStringAsFixed(1)} km/h)"}, telemetry mới.'
                  : 'Chưa thể gửi lệnh: $block',
              style: TextStyle(color: fg, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Text(
      'Mọi chế độ chỉ đổi khi bạn bấm. App không tự bật khi mở ứng dụng, khi kết nối '
      'Bluetooth hay khi kết nối lại, và không tự chuyển giữa các chế độ. Mỗi lệnh '
      'có mã truy vết trong nhật ký BLE (mode_cmd_*).',
      style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.keyPrefix,
    required this.icon,
    required this.title,
    required this.description,
    required this.state,
    required this.connected,
    required this.onSync,
    required this.onToggle,
    this.extra,
  });

  final String keyPrefix;
  final IconData icon;
  final String title;
  final String description;
  final ModeState state;
  final bool connected;
  final VoidCallback onSync;
  final Future<void> Function(bool target) onToggle;
  final Widget? extra;

  Color _statusFg() {
    switch (state.phase) {
      case ModePhase.confirmed:
        return AppColors.greenText;
      case ModePhase.ready:
        return state.on == null ? AppColors.amberText : AppColors.primary;
      case ModePhase.notConfirmed:
        return AppColors.redText;
      case ModePhase.blocked:
      case ModePhase.unverified:
      case ModePhase.unsupported:
        return AppColors.amberText;
      case ModePhase.sending:
      case ModePhase.verifying:
        return AppColors.primary;
      case ModePhase.disconnected:
      case ModePhase.unread:
        return AppColors.textSecondary;
    }
  }

  String _outcomeLabel(String o) {
    switch (o) {
      case 'confirmed':
        return 'đã xác nhận';
      case 'not_confirmed':
        return 'KHÔNG xác nhận';
      case 'rejected':
        return 'xe không nhận lệnh';
      case 'pending':
        return 'đang chờ';
      default:
        return o;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _statusFg();
    final unavailable =
        state.phase == ModePhase.unverified || state.phase == ModePhase.unsupported;
    // Chỉ cho gạt khi ĐÃ biết trạng thái thật từ xe (không gạt "mù").
    final canToggle = connected && !unavailable && !state.busy && state.on != null;
    final t = state.lastCommand;

    return Container(
      key: Key('${keyPrefix}_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              Switch.adaptive(
                key: Key('${keyPrefix}_switch'),
                value: state.on == true,
                onChanged: canToggle ? (v) => onToggle(v) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            key: Key('${keyPrefix}_status'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: fg.withValues(alpha: 0.5)),
            ),
            child: Text(modeStatusLabel(state),
                style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          Text(description,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
          if (extra != null) ...[const SizedBox(height: 8), extra!],
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Text(state.message!,
                key: Key('${keyPrefix}_message'),
                style: TextStyle(color: fg, height: 1.35, fontWeight: FontWeight.w600)),
          ],
          if (!unavailable && connected && state.on == null && !state.busy) ...[
            const SizedBox(height: 6),
            Text('Bấm "Đồng bộ" để đọc trạng thái thật từ xe trước khi gạt công tắc.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (t != null) ...[
            const SizedBox(height: 6),
            Text(
              'Lệnh ${t.id}: ${t.targetOn ? "BẬT" : "TẮT"} → ${_outcomeLabel(t.outcome)}',
              key: Key('${keyPrefix}_trace'),
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: Key('${keyPrefix}_sync'),
              onPressed: (!connected || unavailable || state.busy) ? null : onSync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Đồng bộ (đọc từ xe)'),
            ),
          ),
        ],
      ),
    );
  }
}
