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
import '../../core/proximity/smart_key_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';
import '../home/overview_collapsible.dart';
import 'activity_history_screen.dart';
import 'smart_key_radar.dart';

class ProximityScreen extends ConsumerStatefulWidget {
  const ProximityScreen({super.key});

  @override
  ConsumerState<ProximityScreen> createState() => _ProximityScreenState();
}

class _ProximityScreenState extends ConsumerState<ProximityScreen> {
  // Khối thu gọn: mặc định đóng. Hiệu chỉnh tự mở khi đang đo (null = tự động).
  bool _rangeOpen = false;
  bool _sensOpen = false;
  bool? _calOpenByUser;
  bool _limitsOpen = false;
  bool _logOpen = false;

  @override
  Widget build(BuildContext context) {
    // select + record: chỉ rebuild khi 6 trường này đổi, KHÔNG rebuild theo
    // mỗi khung telemetry/RSSI của BleState.
    final ble = ref.watch(bleProvider.select((s) => (
          phase: s.phase,
          isAuthorized: s.isAuthorized,
          walkUpUnlock: s.walkUpUnlock,
          walkUpAutoPowerOn: s.walkUpAutoPowerOn,
          autoLockWalkAway: s.autoLockWalkAway,
          autoLockMode: s.autoLockMode,
          isLocked: s.isLocked,
          bikeOn: s.lastTelemetry?.isBikeOn ?? false,
          speedKmh: s.lastTelemetry?.speed,
        )));
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
                  color: AppColors.amber,
                  icon: Icons.bluetooth_disabled_rounded,
                  text:
                      'Chưa kết nối/xác thực xe — tính năng chỉ chạy khi có '
                      'kết nối đã xác thực với đúng xe đã ghép đôi.',
                ),
              ),
            SmartKeyRadarCard(prox: prox, connected: connected),
            const SizedBox(height: 16),
            _StatusCard(
              prox: prox,
              connected: connected,
              smartKey: deriveSmartKey(SmartKeyInput(
                // CHƯA nối trạng thái quyền/Bluetooth hệ điều hành thật (xem
                // BlePermissions.check) — màn này giả định đã cấp quyền và
                // Bluetooth đang bật, vì ble_controller không expose 2 cờ đó
                // ra state hiện tại. TODO: nối thật khi có provider quyền.
                bluetoothOn: true,
                permissionGranted: true,
                connected: ble.phase == BlePhase.connected,
                connecting: ble.phase == BlePhase.scanning ||
                    ble.phase == BlePhase.connecting ||
                    ble.phase == BlePhase.reconnecting,
                everConnected: ble.phase != BlePhase.idle,
                authorized: ble.isAuthorized,
                // Không có tín hiệu "nghi phát lại / xác thực bất thường"
                // riêng trong BleState hiện tại — để false, không bịa.
                securityFault: false,
                bikeLocked: ble.isLocked,
                bikeOn: ble.bikeOn,
                zone: prox.zone,
                speedKmh: ble.speedKmh,
                telemetryFresh: ref.read(bleProvider.notifier).telemetryFresh,
              )),
            ),
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
                      'Tự mở khóa an toàn khi bạn vào trong bán kính Smart Key (mặc định 2 m).',
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
                      'Tự tắt xe khi bạn ra ngoài bán kính Smart Key (mặc định 2 m), chỉ khi xe đứng yên.',
                    ),
                    value: ble.autoLockWalkAway,
                    onChanged: bleCtl.setAutoLockWalkAway,
                  ),
                  if (ble.autoLockWalkAway)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Khi rời xa'),
                          const SizedBox(height: 6),
                          SegmentedButton<int>(
                            key: const Key('prox_lock_mode'),
                            segments: const [
                              ButtonSegment(value: 0, label: Text('Chỉ tắt xe')),
                              ButtonSegment(
                                  value: 1, label: Text('Tắt + khóa an toàn')),
                            ],
                            selected: {ble.autoLockMode},
                            onSelectionChanged: (s) =>
                                bleCtl.setAutoLockMode(s.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ble.autoLockMode == 0
                                ? 'Chỉ tắt nguồn: xe vẫn nhận kết nối nên khi bạn '
                                    'quay lại, app tự nối lại và tự mở/bật xe được.'
                                : 'Khóa an toàn: xe sẽ BẮT BUỘC quẹt thẻ NFC mới nối '
                                    'lại được → Mở khóa thông minh KHÔNG thể tự chạy '
                                    'sau khi đã khóa kiểu này.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OverviewCollapsible(
              icon: Icons.social_distance_rounded,
              title: 'Giới hạn khoảng cách',
              hint: 'Giới hạn ${prox.rangeLimitM.toStringAsFixed(prox.rangeLimitM == prox.rangeLimitM.roundToDouble() ? 0 : 1)} m · bật nhanh Smart Key',
              open: _rangeOpen,
              onToggle: () => setState(() { _rangeOpen = !_rangeOpen; }),
              child: _RangeCard(
              prox: prox,
              ctl: ctl,
              unlockOn: ble.walkUpUnlock,
              lockOn: ble.autoLockWalkAway,
              onEnableAll: () async {
                await bleCtl.setWalkUpUnlock(true);
                await bleCtl.setAutoLockWalkAway(true);
                // Chỉ tắt nguồn (không ARM) để quay lại trong 2 m là mở lại được.
                await bleCtl.setAutoLockMode(0);
                await ctl.setRangeStrict(true);
              },
            ),
            ),
            const SizedBox(height: 16),
            OverviewCollapsible(
              icon: Icons.tune_rounded,
              title: 'Độ nhạy & xác nhận rời xa',
              hint: 'Độ nhạy · ${prox.lockConfirmSeconds} giây xác nhận',
              open: _sensOpen,
              onToggle: () => setState(() { _sensOpen = !_sensOpen; }),
              child: Panel(
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
            ),
            const SizedBox(height: 16),
            OverviewCollapsible(
              icon: Icons.straighten_rounded,
              title: 'Hiệu chỉnh khoảng cách (1 m + 2 m)',
              hint: prox.calibrated ? 'Đã hiệu chỉnh 1 m' : 'Chưa hiệu chỉnh — nên đo mốc 1 m và 2 m',
              open: _calOpenByUser ?? prox.calibrating,
              onToggle: () => setState(() { _calOpenByUser = !(_calOpenByUser ?? prox.calibrating); }),
              child: _CalibrationCard(prox: prox, connected: connected, ctl: ctl),
            ),
            const SizedBox(height: 16),
            OverviewCollapsible(
              icon: Icons.info_outline_rounded,
              title: 'Giới hạn cần biết',
              hint: 'RSSI chỉ là ước lượng · hạn chế của khóa/mở',
              open: _limitsOpen,
              onToggle: () => setState(() { _limitsOpen = !_limitsOpen; }),
              child: const Panel(
              child: Text(
                '• Smart Key 2 m: trong bán kính → mở được xe; ngoài bán kính → nút '
                'Mở khóa/Bật xe bị chặn và (nếu bật Tự động khóa) xe tự tắt sau thời '
                'gian xác nhận khi đứng yên. Xe đang chạy KHÔNG bao giờ bị tự tắt.\n'
                '• RSSI chỉ là ước lượng; sai số khoảng cách có thể ±30–50%. Không bảo đảm đúng 2 m. Hướng cầm máy, '
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
            ),
            const SizedBox(height: 16),
            OverviewCollapsible(
              icon: Icons.history_rounded,
              title: 'Nhật ký sự kiện',
              hint: prox.events.isEmpty ? 'Chưa có sự kiện' : '${prox.events.length} sự kiện gần đây',
              open: _logOpen,
              onToggle: () => setState(() { _logOpen = !_logOpen; }),
              child: Column(
                children: [
                  _EventLog(events: prox.events),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('prox_open_activity_history'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const ActivityHistoryScreen())),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Xem toàn bộ lịch sử hoạt động'),
                    ),
                  ),
                ],
              ),
            ),
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
  final SmartKeyView smartKey;
  const _StatusCard({
    required this.prox,
    required this.connected,
    required this.smartKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(prox.status);
    final f = prox.filteredRssi;
    return Panel(
      key: const Key('prox_status_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmartKeyBadge(view: smartKey),
          const SizedBox(height: 10),
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
          if (prox.rangeStrict && prox.distanceM != null)
            Text(
              'Khoảng cách ước lượng: ≈ ${prox.distanceM!.toStringAsFixed(1)} m '
              '(giới hạn ${prox.rangeLimitM.toStringAsFixed(prox.rangeLimitM == prox.rangeLimitM.roundToDouble() ? 0 : 1)} m)'
              ' · độ tin cậy ${(prox.distanceConfidence * 100).round()}%',
              key: const Key('prox_distance_text'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: (prox.withinRange ?? true)
                    ? AppColors.greenText
                    : AppColors.redText,
              ),
            ),
          Text(
            'Ngưỡng mở ≥ ${prox.unlockThreshold.toStringAsFixed(1)} dBm · '
            'ngưỡng khóa ≤ ${prox.lockThreshold.toStringAsFixed(1)} dBm · '
            '${prox.calibrated ? 'đã hiệu chỉnh 1 m' : (prox.rangeStrict ? 'MẶC ĐỊNH tạm thời (chưa hiệu chỉnh 1 m)' : 'CHƯA hiệu chỉnh (ngưỡng cũ)')}'
            '${prox.calibratedRssi2m != null ? ' + mốc 2 m' : ''}'
            '${prox.rangeStrict ? ' · vùng gần ≤ ${prox.nearZoneM.toStringAsFixed(1)} m, vùng xa ≥ ${prox.farZoneM.toStringAsFixed(1)} m' : ''}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Dải trạng thái Smart Key 7 bước (LOCKED…SECURITY_LOCK) + cảnh báo an toàn
/// (ví dụ mất BLE khi xe có thể đang chạy). Suy ra từ [deriveSmartKey] —
/// KHÔNG tự quyết định khóa/mở, chỉ hiển thị.
class _SmartKeyBadge extends StatelessWidget {
  final SmartKeyView view;
  const _SmartKeyBadge({required this.view});

  Color _tone(SmartKeyTone t) => switch (t) {
    SmartKeyTone.green => AppColors.greenText,
    SmartKeyTone.yellow => AppColors.amberText,
    SmartKeyTone.red => AppColors.redText,
    SmartKeyTone.grey => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final c = _tone(view.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              key: const Key('smart_key_dot'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'Smart Key: ${view.title}',
              key: const Key('smart_key_title'),
              style: TextStyle(fontWeight: FontWeight.w700, color: c),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          view.detail,
          key: const Key('smart_key_detail'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        if (view.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: NoticeBanner(
              color: AppColors.amber,
              icon: Icons.warning_amber_rounded,
              text: view.warning!,
            ),
          ),
      ],
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
                : 'Chưa hiệu chỉnh — đang dùng giá trị mặc định tạm thời (kém chính xác).',
            key: const Key('prox_cal_text'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cách làm: đứng cách xe đúng 1 m (rồi đúng 2 m), cầm điện thoại như '
            'khi đi bộ (hoặc để trong túi như bình thường), giữ yên rồi bấm nút '
            'đo. App lấy trung vị RSSI trong ${ProximityEngine.calibrationDuration.inSeconds} giây. '
            'Đo cả hai mốc để Smart Key biết chính xác đâu là ranh giới 2 m '
            'trong môi trường của bạn.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          if (prox.calibratedRssi2m != null) ...[
            const SizedBox(height: 6),
            Text(
              'Mốc 2 m: ${prox.calibratedRssi2m!.toStringAsFixed(1)} dBm · '
              'hệ số suy hao n ≈ ${prox.pathLossN.toStringAsFixed(2)}',
              key: const Key('prox_cal2_text'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
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
                label: const Text('Đo mốc 1 m'),
              ),
              FilledButton.tonalIcon(
                key: const Key('prox_cal_start_2m'),
                onPressed: (!connected || prox.calibrating || !prox.calibrated)
                    ? null
                    : () => ctl.startCalibration(targetM: 2),
                icon: const Icon(Icons.social_distance_rounded),
                label: const Text('Đo mốc 2 m'),
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


/// Thẻ Smart Key: công tắc giới hạn 2 m, thanh khoảng cách trực tiếp, nút bật nhanh.
class _RangeCard extends StatelessWidget {
  final ProximitySnapshot prox;
  final ProximityController ctl;
  final bool unlockOn;
  final bool lockOn;
  final Future<void> Function() onEnableAll;
  const _RangeCard({
    required this.prox,
    required this.ctl,
    required this.unlockOn,
    required this.lockOn,
    required this.onEnableAll,
  });

  static String _m(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final limit = prox.rangeLimitM;
    final d = prox.distanceM;
    final inside = d != null && d <= limit;
    final allOn = unlockOn && lockOn && prox.rangeStrict;
    return Panel(
      key: const Key('prox_range_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('prox_range_switch'),
            contentPadding: EdgeInsets.zero,
            title: Text('Chỉ mở được xe trong ${_m(limit)} m'),
            subtitle: const Text(
              'Quá bán kính: nút Mở khóa / Bật xe bị chặn, xe tự tắt khi bạn đi xa '
              '(nếu bật Tự động khóa). Đến gần trong bán kính mới mở được.',
            ),
            value: prox.rangeStrict,
            onChanged: ctl.setRangeStrict,
          ),
          if (prox.rangeStrict) ...[
            const SizedBox(height: 4),
            Text('Bán kính Smart Key: ${_m(limit)} m'),
            Slider(
              key: const Key('prox_range_slider'),
              min: 1.0,
              max: 3.0,
              divisions: 4,
              value: limit.clamp(1.0, 3.0),
              label: '${_m(limit)} m',
              onChanged: ctl.setRangeLimitM,
            ),
            const SizedBox(height: 4),
            _DistanceGauge(distanceM: d, limitM: limit),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  d == null
                      ? Icons.sensors_off_rounded
                      : (inside ? Icons.lock_open_rounded : Icons.lock_rounded),
                  color: d == null
                      ? AppColors.textSecondary
                      : (inside ? AppColors.greenText : AppColors.redText),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d == null
                        ? 'Chưa đo được khoảng cách tới xe.'
                        : (inside
                            ? 'Trong ${_m(limit)} m (≈ ${d.toStringAsFixed(1)} m) — có thể mở xe.'
                            : 'Ngoài ${_m(limit)} m (≈ ${d.toStringAsFixed(1)} m) — xe không mở được.'),
                    key: const Key('prox_range_state'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (prox.provisional) ...[
              const SizedBox(height: 8),
              NoticeBanner(
                color: AppColors.amber,
                icon: Icons.tune_rounded,
                text:
                    'Chưa hiệu chỉnh nên đang dùng mốc 1 m mặc định (${ProximityEngine.defaultRssi1m.toStringAsFixed(0)} dBm). '
                    'Hãy đo mốc 1 m rồi 2 m ở phần Hiệu chỉnh bên dưới để ranh giới 2 m chính xác.',
              ),
            ],
          ],
          const SizedBox(height: 8),
          if (!allOn)
            FilledButton.icon(
              key: const Key('prox_enable_all'),
              onPressed: onEnableAll,
              icon: const Icon(Icons.key_rounded),
              label: Text('Bật Smart Key ${_m(limit)} m (mở + tự tắt)'),
            )
          else
            Text(
              'Smart Key đang bật: tự mở khi vào ${_m(limit)} m, tự tắt xe khi ra ngoài.',
              key: const Key('prox_range_active'),
              style: TextStyle(color: AppColors.greenText, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// Thanh khoảng cách 0–5 m với vạch giới hạn.
class _DistanceGauge extends StatelessWidget {
  final double? distanceM;
  final double limitM;
  const _DistanceGauge({required this.distanceM, required this.limitM});

  static const double _max = 5.0;

  @override
  Widget build(BuildContext context) {
    final d = distanceM;
    final inside = d != null && d <= limitM;
    return SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          double pos(double v) => (v / _max).clamp(0.0, 1.0) * w;
          return Stack(
            children: [
              Positioned.fill(
                top: 11,
                bottom: 11,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.panelSecondary,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.panelBorderBright),
                  ),
                ),
              ),
              // Vùng cho phép (0 → giới hạn).
              Positioned(
                left: 0,
                top: 11,
                bottom: 11,
                width: pos(limitM),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.greenText.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              if (d != null)
                Positioned(
                  left: pos(d) - 5,
                  top: 6,
                  child: Container(
                    width: 10,
                    height: 18,
                    decoration: BoxDecoration(
                      color: inside ? AppColors.greenText : AppColors.redText,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              Positioned(
                left: pos(limitM) - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: AppColors.amberText),
              ),
            ],
          );
        },
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
