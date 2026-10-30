// Smart Unlock / Auto Lock — bật/tắt, độ nhạy, hiệu chỉnh 1 m, trạng thái và
// nhật ký sự kiện. Mọi nút đều nối với BleController / ProximityController.
//
// LƯU Ý TRUNG THỰC hiển thị cho người dùng:
//  • RSSI chỉ ước lượng khoảng cách, không bảo đảm đúng 1 m.
//  • "Thành công" = xe nhận ghi lệnh. Giao thức không có đọc lại trạng thái
//    khóa nên app chưa thể xác nhận xe đã khóa/mở thật.
//  • Sau khi KHÓA AN TOÀN, xe có thể yêu cầu quẹt NFC để kết nối lại → Smart
//    Unlock qua BLE sau Auto Lock chưa được kiểm chứng trên xe thật.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/proximity/proximity_controller.dart';
import '../../core/proximity/proximity_engine.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';

class ProximityScreen extends ConsumerWidget {
  const ProximityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final prox = ref.watch(proximityProvider);
    final ctl = ref.read(proximityProvider.notifier);
    final bleCtl = ref.read(bleProvider.notifier);
    final connected = ble.phase == BlePhase.connected && ble.isAuthorized;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Mở khóa thông minh / Tự động khóa')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!connected)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoticeBanner(
                  color: Colors.orange,
                  icon: Icons.bluetooth_disabled_rounded,
                  text:
                      'Chưa kết nối/xác thực xe — tính năng chỉ chạy khi có '
                      'kết nối đã xác thực với đúng xe đã ghép đôi.',
                ),
              ),
            _StatusCard(prox: prox, connected: connected),
            const SizedBox(height: 16),
            const SectionTitle('Bật / tắt'),
            const SizedBox(height: 8),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('prox_unlock_switch'),
                    title: const Text('Mở khóa thông minh'),
                    subtitle: const Text(
                      'Tự mở khóa an toàn khi bạn đến gần xe (~1 m đã hiệu chỉnh).',
                    ),
                    value: ble.walkUpUnlock,
                    onChanged: bleCtl.setWalkUpUnlock,
                  ),
                  SwitchListTile(
                    key: const Key('prox_autopower_switch'),
                    title: const Text('Bật xe sẵn sau khi mở khóa'),
                    subtitle: const Text('Tùy chọn của Mở khóa thông minh.'),
                    value: ble.walkUpAutoPowerOn,
                    onChanged: ble.walkUpUnlock
                        ? bleCtl.setWalkUpAutoPowerOn
                        : null,
                  ),
                  SwitchListTile(
                    key: const Key('prox_lock_switch'),
                    title: const Text('Tự động khóa'),
                    subtitle: const Text(
                      'Tự tắt xe và khóa khi bạn rời xa, chỉ khi xe đứng yên ở P/STANDBY.',
                    ),
                    value: ble.autoLockWalkAway,
                    onChanged: bleCtl.setAutoLockWalkAway,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Độ nhạy'),
            const SizedBox(height: 8),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<int>(
                    key: const Key('prox_sensitivity'),
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Thấp')),
                      ButtonSegment(value: 1, label: Text('Vừa')),
                      ButtonSegment(value: 2, label: Text('Cao')),
                    ],
                    selected: {prox.sensitivity},
                    onSelectionChanged: (s) => ctl.setSensitivity(s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Thấp: khó kích hoạt, ít nhầm. Cao: dễ kích hoạt nhưng '
                    'dễ nhầm hơn khi tín hiệu dao động.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Thời gian xác nhận rời xa: ${prox.lockConfirmSeconds} giây',
                  ),
                  Slider(
                    key: const Key('prox_confirm_slider'),
                    min: 3,
                    max: 15,
                    divisions: 12,
                    value: prox.lockConfirmSeconds.toDouble(),
                    label: '${prox.lockConfirmSeconds} s',
                    onChanged: (v) => ctl.setLockConfirmSeconds(v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Hiệu chỉnh khoảng cách 1 m'),
            const SizedBox(height: 8),
            _CalibrationCard(prox: prox, connected: connected, ctl: ctl),
            const SizedBox(height: 16),
            const SectionTitle('Giới hạn cần biết'),
            const SizedBox(height: 8),
            const Panel(
              child: Text(
                '• RSSI chỉ là ước lượng; không bảo đảm đúng 1 m. Hướng cầm máy, '
                'túi quần, người che và nhiễu BLE đều làm đổi giá trị.\n'
                '• "Thành công" nghĩa là xe nhận ghi lệnh. Xe không có đọc lại '
                'trạng thái khóa nên app chưa thể xác nhận đã khóa/mở thật.\n'
                '• Sau khi KHÓA AN TOÀN, xe có thể buộc quẹt thẻ NFC mới kết nối '
                'lại; khả năng tự mở khóa qua BLE sau Tự động khóa CHƯA kiểm chứng '
                'trên xe thật.\n'
                '• Mất kết nối hoặc mất tín hiệu KHÔNG bị coi là bạn đã rời xe.\n'
                '• Tự động không chạy khi bạn vừa thao tác tay, khi xe đang chạy, '
                'ở số lái, chưa có tốc độ mới, hoặc đang ở Firmware Lab.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Nhật ký sự kiện'),
            const SizedBox(height: 8),
            _EventLog(events: prox.events),
          ],
        ),
      ),
    );
  }
}

String _statusText(ProximityStatus s) => switch (s) {
  ProximityStatus.off => 'Đang tắt',
  ProximityStatus.searching => 'Đang tìm xe',
  ProximityStatus.idle => 'Đang theo dõi',
  ProximityStatus.detected => 'Đã phát hiện',
  ProximityStatus.verifying => 'Đang xác thực',
  ProximityStatus.running => 'Đang thực hiện',
  ProximityStatus.success => 'Đã gửi lệnh',
  ProximityStatus.failed => 'Thất bại',
  ProximityStatus.blocked => 'Bị chặn',
};

Color _statusColor(ProximityStatus s) => switch (s) {
  ProximityStatus.success => AppColors.greenText,
  ProximityStatus.failed || ProximityStatus.blocked => AppColors.redText,
  ProximityStatus.detected ||
  ProximityStatus.verifying ||
  ProximityStatus.running => AppColors.amberText,
  _ => AppColors.textSecondary,
};

String _zoneText(ProximityZone z) => switch (z) {
  ProximityZone.near => 'Gần',
  ProximityZone.middle => 'Trung gian',
  ProximityZone.far => 'Xa',
  ProximityZone.unknown => '—',
};

class _StatusCard extends StatelessWidget {
  final ProximitySnapshot prox;
  final bool connected;
  const _StatusCard({required this.prox, required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(prox.status);
    final f = prox.filteredRssi;
    return Panel(
      key: const Key('prox_status_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors_rounded, color: color),
              const SizedBox(width: 8),
              Text(
                _statusText(prox.status),
                key: const Key('prox_status_text'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                'Vùng: ${_zoneText(prox.zone)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(prox.message, key: const Key('prox_message')),
          const SizedBox(height: 14),
          _RssiBar(prox: prox),
          const SizedBox(height: 8),
          Text(
            f == null
                ? 'RSSI: -- (chưa có mẫu)'
                : 'RSSI lọc: ${f.toStringAsFixed(1)} dBm'
                      '${prox.rawRssi != null ? '  (thô ${prox.rawRssi!.toStringAsFixed(0)})' : ''}',
            key: const Key('prox_rssi_text'),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          Text(
            'Ngưỡng mở ≥ ${prox.unlockThreshold.toStringAsFixed(1)} dBm · '
            'ngưỡng khóa ≤ ${prox.lockThreshold.toStringAsFixed(1)} dBm · '
            '${prox.calibrated ? 'đã hiệu chỉnh' : 'CHƯA hiệu chỉnh (ngưỡng cũ)'}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Thanh RSSI từ -100 đến -30 dBm với vạch ngưỡng mở/khóa.
class _RssiBar extends StatelessWidget {
  final ProximitySnapshot prox;
  const _RssiBar({required this.prox});

  static const double _lo = -100, _hi = -30;
  double _pos(double v) => ((v - _lo) / (_hi - _lo)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          Widget mark(double v, Color col) => Positioned(
            left: w * _pos(v) - 1,
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: col),
          );
          return Stack(
            children: [
              Positioned.fill(
                top: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.panelSecondary,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.panelBorderBright),
                  ),
                ),
              ),
              if (prox.filteredRssi != null)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  width: w * _pos(prox.filteredRssi!),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              mark(prox.unlockThreshold, AppColors.greenText),
              mark(prox.lockThreshold, AppColors.redText),
            ],
          );
        },
      ),
    );
  }
}

class _CalibrationCard extends StatelessWidget {
  final ProximitySnapshot prox;
  final bool connected;
  final ProximityController ctl;
  const _CalibrationCard({
    required this.prox,
    required this.connected,
    required this.ctl,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prox.calibrated
                ? 'Đã hiệu chỉnh: ${prox.calibratedRssi1m!.toStringAsFixed(1)} dBm tại ~1 m.'
                : 'Chưa hiệu chỉnh — đang dùng ngưỡng cũ (kém chính xác).',
            key: const Key('prox_cal_text'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cách làm: đứng cách xe khoảng 1 m, cầm điện thoại như khi đi bộ '
            '(hoặc để trong túi như bình thường), giữ yên rồi bấm "Bắt đầu". '
            'App lấy trung vị RSSI trong ${ProximityEngine.calibrationDuration.inSeconds} giây.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          if (prox.calibrating) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: prox.calibrationProgress),
          ],
          if (prox.calibrationMessage != null) ...[
            const SizedBox(height: 8),
            Text(prox.calibrationMessage!, key: const Key('prox_cal_message')),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('prox_cal_start'),
                onPressed: (!connected || prox.calibrating)
                    ? null
                    : ctl.startCalibration,
                icon: const Icon(Icons.straighten_rounded),
                label: const Text('Bắt đầu hiệu chỉnh'),
              ),
              if (prox.calibrating)
                OutlinedButton(
                  onPressed: ctl.cancelCalibration,
                  child: const Text('Hủy'),
                ),
              if (prox.calibrated && !prox.calibrating)
                OutlinedButton(
                  key: const Key('prox_cal_clear'),
                  onPressed: ctl.clearCalibration,
                  child: const Text('Xóa hiệu chỉnh'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  final List<ProximityEvent> events;
  const _EventLog({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Panel(
        child: Text(
          'Chưa có sự kiện.',
          key: const Key('prox_events_empty'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    String hms(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Panel(
      child: Column(
        children: [
          for (final e in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hms(e.at),
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${e.kind}${e.detail.isEmpty ? '' : ' — ${e.detail}'}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
