// Scan — Quét BLE tìm xe Dat Bike (Kinetic Stitch EV).
// Xe dùng RPA (MAC xoay vòng) và tên quảng bá thay đổi ('dat.bik3' / 'Dat Bike Quantum S1'),
// giao diện sáng sủa, thẻ trắng viền hairline, chỉ thị RSSI trực quan.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/ble/ble_logger.dart';
import '../../core/ble/ble_permissions.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _results = <ScanResult>[];
  StreamSubscription? _sub;
  bool _scanning = false;
  String? _error;
  bool _showAll = false;
  String? _lastBikeId;
  String? _lastBikeName;
  bool _directConnecting = false;

  @override
  void initState() {
    super.initState();
    ref.read(bleProvider.notifier).lastBikeId().then((id) async {
      if (!mounted) return;
      final name = await ref.read(bleProvider.notifier).lastBikeName();
      setState(() {
        _lastBikeId = id;
        _lastBikeName = name;
      });
    });
    _scan();
  }

  bool _isBike(ScanResult r) {
    final name = '${r.advertisementData.advName} ${r.device.platformName}'
        .toLowerCase()
        .replaceAll('.', ' ');
    return name.contains('dat bik') ||
        name.contains('datbike') ||
        name.contains('quantum') ||
        name.contains('dat.bik');
  }

  Future<void> _scan() async {
    setState(() {
      _error = null;
      _scanning = true;
    });

    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _scanning = false);
      return;
    }

    final ok = await BlePermissions.ensure();
    if (!ok) {
      setState(() {
        _scanning = false;
        _error = 'Thiếu quyền Bluetooth/Vị trí — không thể quét.';
      });
      if (await BlePermissions.permanentlyDenied() && mounted) {
        _openSettingsDialog();
      }
      return;
    }

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      setState(() {
        _scanning = false;
        _error = 'Bluetooth đang tắt — hãy bật Bluetooth rồi quét lại.';
      });
      return;
    }

    if (!BleLogger.instance.active) await BleLogger.instance.startSession();

    _results.clear();
    _sub?.cancel();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    _sub = FlutterBluePlus.scanResults.listen((rs) {
      BleLogger.instance.event('scan_batch', {
        'count': rs.length,
        'devices': [
          for (final r in rs)
            {
              'id': r.device.remoteId.str,
              'adv_name': r.advertisementData.advName,
              'platform_name': r.device.platformName,
              'rssi': r.rssi,
            }
        ],
      });
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(rs);
      });
    });

    try {
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  void _connect(ScanResult r) {
    FlutterBluePlus.stopScan();
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    Navigator.of(context).pushReplacementNamed('/connecting', arguments: {
      'device': r.device,
      'name': name.isEmpty ? 'Dat Bike' : name,
    });
  }

  Future<void> _connectDirect() async {
    if (_lastBikeId == null) return;
    setState(() => _directConnecting = true);
    final dev = BluetoothDevice.fromId(_lastBikeId!);
    Navigator.of(context).pushReplacementNamed('/connecting', arguments: {
      'device': dev,
      'name': _lastBikeName ?? 'Dat Bike',
    });
  }

  void _openSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Cần quyền Bluetooth & Vị trí',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: Text(
          'Quyền bị từ chối vĩnh viễn. Mở Cài đặt hệ thống → Ứng dụng → Quyền để cấp lại.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textDim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('HỦY', style: GoogleFonts.plusJakartaSans(color: AppColors.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: () {
              openAppSettings();
              Navigator.pop(c);
            },
            child: Text('MỞ CÀI ĐẶT', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _rssiBars(int rssi) {
    if (rssi >= -55) return '▂▄▆█';
    if (rssi >= -70) return '▂▄▆_';
    if (rssi >= -85) return '▂▄__';
    return '▂___';
  }

  @override
  Widget build(BuildContext context) {
    final bikes = _results.where(_isBike).toList();
    final others = _results.where((r) => !_isBike(r)).toList();
    others.sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          'TÌM XE BLUETOOTH',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Kết nối lại xe đã nhớ
            if (_lastBikeId != null) ...[
              Panel(
                onTap: _directConnecting ? null : _connectDirect,
                padding: const EdgeInsets.all(16),
                borderRadius: 20,
                hasActiveHalo: true,
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lastBikeName ?? 'Xe đã kết nối gần nhất',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Bấm để kết nối trực tiếp không cần chờ quét',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _directConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_error != null) ...[
              NoticeBanner(color: AppColors.error, text: _error!),
              const SizedBox(height: 14),
            ],

            // Xe tìm thấy
            if (bikes.isNotEmpty) ...[
              const SectionTitle('XE CỦA BẠN PHÁT HIỆN ĐƯỢC'),
              const SizedBox(height: 10),
              for (final r in bikes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    onTap: () => _connect(r),
                    padding: const EdgeInsets.all(16),
                    borderRadius: 20,
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
                          ),
                          child: const Icon(Icons.electric_moped_rounded, color: AppColors.secondary, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (r.advertisementData.advName.isNotEmpty
                                        ? r.advertisementData.advName
                                        : r.device.platformName)
                                    .ifEmpty('(Không tên)'),
                                style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    _rssiBars(r.rssi),
                                    style: const TextStyle(
                                      color: AppColors.tertiary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${r.rssi} dBm · ${r.device.remoteId.str}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
            ],

            // Xe phát hiện trên Web Preview (Mô phỏng quét BLE)
            if (kIsWeb) ...[
              const SectionTitle('XE CỦA BẠN PHÁT HIỆN ĐƯỢC (BLE)'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã xác thực & ghép đôi chìa khóa số BLE xe Dat Bike Quantum S1!',
                          style: GoogleFonts.plusJakartaSans(),
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  padding: const EdgeInsets.all(16),
                  borderRadius: 20,
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.electric_moped_rounded, color: AppColors.secondary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dat Bike Quantum S1',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text(
                                  '▂▄▆█',
                                  style: TextStyle(
                                    color: AppColors.tertiary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '-58 dBm · RL9C4NGSSSCC00187',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Gợi ý khi chưa thấy
            if (bikes.isEmpty && !_scanning && !kIsWeb) ...[
              Panel(
                padding: const EdgeInsets.all(24),
                borderRadius: 20,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bluetooth_searching_rounded, size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Chưa tìm thấy xe gần đây',
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Đảm bảo xe đã bật nguồn hoặc chìa khóa mở\n'
                      '• Đứng gần xe trong bán kính 3-5 mét\n'
                      '• Kiểm tra Bluetooth trên điện thoại đang bật',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textDim,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: const Icon(Icons.radar, size: 18),
                      label: Text('Quét lại', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                      onPressed: _scan,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Thiết bị khác
            const SizedBox(height: 8),
            Row(
              children: [
                const SectionTitle('THIẾT BỊ KHÁC'),
                const Spacer(),
                Text(
                  '${others.length} thiết bị',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textDim),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _showAll,
                  onChanged: (v) => setState(() => _showAll = v),
                ),
              ],
            ),
            if (_showAll)
              for (final r in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    borderRadius: 14,
                    onTap: () => _connect(r),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_rounded, size: 20, color: AppColors.textDim),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (r.advertisementData.advName.isNotEmpty
                                        ? r.advertisementData.advName
                                        : r.device.platformName)
                                    .ifEmpty('(Không tên)'),
                                style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${r.device.remoteId.str} · ${r.rssi} dBm',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AppColors.textDim),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const StadiumBorder(),
        onPressed: _scanning ? null : _scan,
        icon: _scanning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            : const Icon(Icons.radar),
        label: Text(
          _scanning ? 'Đang quét…' : 'Quét xe',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
