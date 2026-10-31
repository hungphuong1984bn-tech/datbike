// Thẻ REGEN MODE — CHỈ ĐỌC. Không có công tắc, không bộ chọn mức, không nút gửi.
// Lý do: chưa có characteristic Regen độc lập nào được xác minh
// (docs/REGEN_VERIFICATION.md). Thẻ chỉ trình bày telemetry thật của xe.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/control/regen_monitor.dart';
import '../../core/proto/bike_log.dart';
import '../../ui/app_theme.dart';

class RegenMonitorCard extends ConsumerStatefulWidget {
  const RegenMonitorCard({super.key});

  @override
  ConsumerState<RegenMonitorCard> createState() => _RegenMonitorCardState();
}

class _RegenMonitorCardState extends ConsumerState<RegenMonitorCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Làm mới mỗi giây để phát hiện telemetry cũ (không có gói mới → không rebuild).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BikeLogMsg? tele = ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final connected = ref.watch(bleProvider.select((s) => s.phase == BlePhase.connected));
    final fresh = connected && ref.read(bleProvider.notifier).telemetryFresh;
    final reading = fresh ? regenReadingFrom(tele) : null;
    final peaks = ref.watch(regenPeaksProvider);

    String num(double? v, String unit, {int d = 1}) =>
        v == null ? '—' : '${v.toStringAsFixed(d)} $unit';

    return Container(
      key: const Key('regen_monitor_card'),
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
              Icon(Icons.battery_charging_full_rounded, color: AppColors.greenText),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('REGEN MODE',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              _chip('CHƯA HỖ TRỢ ĐIỀU KHIỂN', AppColors.amberText, AppColors.amberSoft,
                  const Key('regen_status_chip')),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('regen_unsupported_banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amberSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.amberSoftBorder),
            ),
            child: Text(
              'Chưa có characteristic Regen độc lập nào được xác minh trên firmware '
              '1.14.0, nên app KHÔNG gửi lệnh Regen và KHÔNG có bộ chọn mức. '
              'Chỉ hiển thị số liệu thật xe gửi về.',
              style: TextStyle(color: AppColors.amberText, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            fresh
                ? 'Số liệu thật từ xe (telemetry < 4 giây)'
                : (connected
                    ? 'Telemetry cũ hoặc chưa có — không hiển thị số liệu'
                    : 'Chưa kết nối xe — không có số liệu'),
            key: const Key('regen_freshness'),
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _row('Dòng pha', num(reading?.phaseCurrentA, 'A'), const Key('regen_phase')),
          _row('Điện áp pack', num(reading?.voltageV, 'V'), const Key('regen_voltage')),
          _row('Công suất (V×I)', num(reading?.powerKw, 'kW', d: 2), const Key('regen_power')),
          _row('Tốc độ', num(reading?.speedKmh, 'km/h'), const Key('regen_speed')),
          const Divider(height: 24),
          _row('Công suất lớn nhất từ lúc reset', num(peaks.maxKw, 'kW', d: 2),
              const Key('regen_peak_max')),
          _row('Công suất nhỏ nhất từ lúc reset', num(peaks.minKw, 'kW', d: 2),
              const Key('regen_peak_min')),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('regen_reset_peak'),
              onPressed: () => ref.read(regenPeaksProvider.notifier).reset(),
              child: const Text('Reset cực trị'),
            ),
          ),
          Text(
            'Lưu ý dấu: tài liệu trong dự án mâu thuẫn về dấu của dòng pha khi tái '
            'sinh (bộ giải mã ghi "dương = tái tạo", tài liệu giao thức ghi "âm"). '
            'App vì thế hiển thị giá trị có dấu và cả hai cực trị, không tự gắn nhãn '
            '"đang nạp ngược". Cần đối chiếu trên xe thật.',
            style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Key key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, key: key, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _chip(String text, Color fg, Color bg, Key key) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}
