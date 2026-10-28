// Màn hình Regen (phanh tái sinh) — Portrait.
// Hiển thị: mức hiện tại trên xe, mức đã chọn, trạng thái đồng bộ.
// Khi giao thức chưa xác minh: các điều khiển bị khóa và nói rõ lý do.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/proto/bike_log.dart';
import '../../core/regen/regen_controller.dart';
import '../../core/regen/regen_protocol.dart';

class RegenScreen extends ConsumerStatefulWidget {
  const RegenScreen({super.key});

  @override
  ConsumerState<RegenScreen> createState() => _RegenScreenState();
}

class _RegenScreenState extends ConsumerState<RegenScreen> {
  double _peakKw = 0; // đỉnh công suất nạp ngược từ lần reset (chỉ để so sánh)

  @override
  void initState() {
    super.initState();
    // Chỉ ĐỌC (không ghi) khi mở màn hình; no-op nếu chưa xác minh.
    Future.microtask(() {
      if (mounted) ref.read(regenProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BikeLogMsg?>(bleProvider.select((b) => b.lastTelemetry), (_, m) {
      if (m == null || m.voltage <= 0) return;
      final kw = m.voltage * m.phase / 1000.0;
      if (kw > _peakKw) setState(() => _peakKw = kw);
    });
    final ble = ref.watch(bleProvider);
    final tele = ble.lastTelemetry;
    final liveKw = (tele != null && tele.voltage > 0)
        ? tele.voltage * tele.phase / 1000.0
        : null;
    final spec = ref.watch(regenSpecProvider);
    final st = ref.watch(regenProvider);
    final ctl = ref.read(regenProvider.notifier);
    final busy = st.status == RegenSyncStatus.writing ||
        st.status == RegenSyncStatus.verifying;
    final canApply = spec.verified &&
        !busy &&
        st.selectedIndex != null &&
        st.selectedIndex != st.currentIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('Phanh tái sinh (Regen)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!spec.verified) _unsupportedBanner(context),
            const SizedBox(height: 12),
            _valueRow(
              context,
              label: 'Mức hiện tại trên xe',
              value: _currentText(spec, st),
              key: const Key('regen_current'),
            ),
            const SizedBox(height: 8),
            _valueRow(
              context,
              label: 'Mức đã chọn',
              value: _selectedText(spec, st),
              key: const Key('regen_selected'),
            ),
            const SizedBox(height: 8),
            _syncChip(context, st),
            if (st.message != null) ...[
              const SizedBox(height: 8),
              Text(st.message!, key: const Key('regen_message')),
            ],
            const SizedBox(height: 20),
            _selector(context, spec, st, ctl, busy),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('regen_apply'),
              onPressed: canApply ? ctl.apply : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: const Text('Gửi xuống xe'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('regen_refresh'),
              onPressed: busy ? null : ctl.refresh,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Đọc lại từ xe'),
            ),
            if (spec.verified) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('regen_probe'),
                onPressed: busy ? null : () => _confirmProbe(context, ctl),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Dò thêm mức Regen (có kiểm soát)'),
              ),
            ],
            const SizedBox(height: 16),
            _liveMeter(liveKw, ble.grabMode),
            const SizedBox(height: 20),
            _safetyCard(context, spec),
            const SizedBox(height: 12),
            _howToVerify(context),
          ],
        ),
      ),
    );
  }

  String _currentText(RegenProtocolSpec spec, RegenState st) {
    if (!spec.verified) return 'Không đọc được (chưa xác minh)';
    if (st.currentIndex != null) {
      return spec.levelByIndex(st.currentIndex!)?.label ?? 'Không rõ';
    }
    if (st.currentRaw != null) return 'Giá trị thô ${st.currentRaw} (không khớp mức nào)';
    return 'Chưa đọc được từ xe';
  }

  String _selectedText(RegenProtocolSpec spec, RegenState st) {
    if (!spec.verified || st.selectedIndex == null) return '—';
    return spec.levelByIndex(st.selectedIndex!)?.label ?? '—';
  }

  Widget _unsupportedBanner(BuildContext context) {
    return Container(
      key: const Key('regen_unsupported_banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chưa thể điều khiển Regen thực tế. Firmware 1.14.0 chưa có '
              'characteristic Regen nào được xác minh, nên app KHÔNG gửi bất kỳ '
              'lệnh nào xuống xe. Các nút bên dưới bị khóa cho tới khi giao '
              'thức được xác minh.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueRow(BuildContext context,
      {required String label, required String value, required Key key}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(value,
                key: key,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _syncChip(BuildContext context, RegenState st) {
    late final String text;
    late final Color color;
    switch (st.status) {
      case RegenSyncStatus.unsupported:
        text = 'Không hỗ trợ điều khiển';
        color = const Color(0xFF64748B);
      case RegenSyncStatus.disconnected:
        text = 'Chưa kết nối xe';
        color = const Color(0xFF64748B);
      case RegenSyncStatus.unknown:
        text = 'Chưa biết mức trên xe';
        color = const Color(0xFF64748B);
      case RegenSyncStatus.synced:
        text = 'Đã đồng bộ (đã đọc lại từ xe)';
        color = const Color(0xFF16A34A);
      case RegenSyncStatus.pending:
        text = 'Chưa gửi — mức chọn khác mức trên xe';
        color = const Color(0xFFD97706);
      case RegenSyncStatus.writing:
        text = 'Đang gửi…';
        color = const Color(0xFF2563EB);
      case RegenSyncStatus.verifying:
        text = 'Đang đọc lại để xác nhận…';
        color = const Color(0xFF2563EB);
      case RegenSyncStatus.mismatch:
        text = 'Chưa đồng bộ — xe không ở mức mong muốn';
        color = const Color(0xFFDC2626);
      case RegenSyncStatus.failed:
        text = 'Lỗi / bị chặn — chưa xác nhận';
        color = const Color(0xFFDC2626);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        key: const Key('regen_sync_chip'),
        label: Text(text),
        side: BorderSide(color: color),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _selector(BuildContext context, RegenProtocolSpec spec, RegenState st,
      RegenController ctl, bool busy) {
    if (!spec.verified || spec.levels.isEmpty) {
      return const Opacity(
        opacity: 0.5,
        child: Text(
          'Chưa có mức Regen nào được xác minh để chọn.',
          key: Key('regen_no_levels'),
        ),
      );
    }
    final sel = st.selectedIndex;
    return Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              key: const Key('regen_minus'),
              onPressed: busy ? null : () => ctl.step(-1),
              icon: const Icon(Icons.remove_rounded),
            ),
            Expanded(
              child: Text(
                sel == null ? '—' : (spec.levelByIndex(sel)?.label ?? '—'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              key: const Key('regen_plus'),
              onPressed: busy ? null : () => ctl.step(1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (sel != null && (spec.levelByIndex(sel)?.experimental ?? false))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '⚠ Xe lưu được giá trị này nhưng hiệu ứng Regen của mức này chưa được xác minh. Hãy đo bằng bảng bên dưới.',
              key: Key('regen_experimental_note'),
              style: TextStyle(color: Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final l in spec.levels)
              ChoiceChip(
                label: Text(l.label),
                selected: sel == l.index,
                onSelected: busy ? null : (_) => ctl.select(l.index),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmProbe(BuildContext context, RegenController ctl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dò mức Regen cao hơn?'),
        content: const Text(
          'App sẽ thử ghi các mức Regen 2, 3, 4 xuống xe rồi đọc lại, dừng ở giá trị '
          'đầu tiên xe không đọc lại đúng, và LUÔN khôi phục mức ban đầu.\n\n'
          '• Firmware 1.14.0 có vẻ chỉ parse Regen (GRAB_MODE) dạng 0/1 — mức cao hơn là thử nghiệm.\n'
          '• Chỉ thực hiện khi xe ĐỨNG YÊN (tốt nhất kê chống, bánh không chạm đất).\n'
          '• Kết quả chỉ cho biết xe LƯU được giá trị, không chứng minh hiệu ứng Regen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bắt đầu dò')),
        ],
      ),
    );
    if (ok == true) await ctl.probeHigherLevels();
  }

  Widget _liveMeter(double? liveKw, int grabRaw) {
    final live = liveKw == null
        ? 'Chưa có dữ liệu'
        : (liveKw > 0.05
            ? '+${liveKw.toStringAsFixed(2)} kW (nạp ngược)'
            : '${liveKw.toStringAsFixed(2)} kW');
    return Container(
      key: const Key('regen_live_meter'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Đo hiệu ứng (chỉ đọc)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Mức Regen hiện tại: $grabRaw'),
          Text('Công suất tức thời: $live'),
          Text('Đỉnh nạp ngược từ lúc reset: +${_peakKw.toStringAsFixed(2)} kW'),
          const SizedBox(height: 6),
          const Text(
            'So sánh các mức: cùng tốc độ, cùng đoạn đường, chỉ nhả ga (không bóp phanh), '
            'rồi bấm Reset đỉnh trước mỗi lần thử. Dùng nơi vắng, không nhìn màn hình khi đang chạy.',
            style: TextStyle(fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('regen_reset_peak'),
              onPressed: () => setState(() => _peakKw = 0),
              child: const Text('Reset đỉnh'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _safetyCard(BuildContext context, RegenProtocolSpec spec) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'An toàn: ${spec.requiresStandstill ? "chỉ đổi Regen khi xe đứng yên và có dữ liệu tốc độ mới (< 4 giây). " : ""}'
        'Chức năng này không can thiệp phanh cơ, ga, giới hạn công suất hay '
        'các chức năng an toàn khác. Mọi kết quả chỉ được coi là thành công '
        'khi đọc lại từ xe khớp mức đã chọn.',
      ),
    );
  }

  Widget _howToVerify(BuildContext context) {
    return const ExpansionTile(
      key: Key('regen_how_to_verify'),
      title: Text('Cách xác minh giao thức Regen'),
      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Bật nhật ký HCI Bluetooth trên Android, mở app gốc Dat Bike, đổi Regen '
          'ở từng mức khi xe ĐỨNG YÊN, lấy btsnoop_hci.log.\n'
          '2. Lọc ATT Write Request/Response; tìm characteristic được ghi duy nhất '
          'khi đổi Regen. Ghi lại UUID, payload sau khi giải mã khung protected '
          '[counter][data][tag4].\n'
          '3. Đối chiếu trong firmware (Ghidra): handler ghi, giá trị hợp lệ, vùng NVS '
          'lưu mức, và có điều kiện từ chối khi xe đang chạy hay không.\n'
          '4. Đọc lại char đó trước/sau mỗi lần đổi để chắc chắn đọc được mức hiện tại.\n'
          '5. Chỉ khi đủ cả 4 bước mới điền RegenProtocolSpec.verified và viết '
          'RegenTransport. Chi tiết: docs/REGEN_VERIFICATION.md.',
        ),
      ],
    );
  }
}
