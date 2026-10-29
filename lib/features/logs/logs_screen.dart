// Logs — Xem & Export file log BLE (JSONL) (Kinetic Stitch EV).

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ble/ble_logger.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';

enum _LogRange {
  all('Tất cả', null),
  today('Hôm nay', 1),
  week('7 ngày', 7),
  month('30 ngày', 30);

  final String label;
  final int? days;
  const _LogRange(this.label, this.days);
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  static const _exportChannel = MethodChannel('vn.datbike/export');

  List<File> _files = [];
  String? _preview;
  String? _dirPath;
  File? _selected;
  bool _exporting = false;
  int? _sdkInt;

  // Trạng thái tải / lọc
  bool _loading = true;
  String? _loadError;
  bool _opening = false;
  String _query = '';
  _LogRange _range = _LogRange.all;

  List<File> get _visible {
    final q = _query.trim().toLowerCase();
    final now = DateTime.now();
    return _files.where((f) {
      if (q.isNotEmpty && !f.uri.pathSegments.last.toLowerCase().contains(q)) return false;
      final days = _range.days;
      if (days != null) {
        try {
          if (now.difference(f.statSync().modified).inDays >= days) return false;
        } catch (_) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    BleLogger.dirPath().then((p) {
      if (mounted) setState(() => _dirPath = p);
    });
    DeviceInfoPlugin().androidInfo.then((i) {
      if (mounted) setState(() => _sdkInt = i.version.sdkInt);
    }).catchError((_) {});
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final files = await BleLogger.listSessions();
      if (!mounted) return;
      setState(() {
        _files = files.cast<File>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Không đọc được thư mục nhật ký. Kiểm tra quyền lưu trữ rồi thử lại.';
      });
    }
  }

  Future<void> _open(File f) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final len = f.lengthSync();
      final cap = 20 * 1024 * 1024;
      final start = len > cap ? len - cap : 0;
      final content = await File(f.path)
          .openRead(start, len)
          .transform(systemEncoding.decoder)
          .join();
      if (!mounted) return;
      setState(() {
        _selected = f;
        _preview = (start > 0 ? '…(bỏ $start byte đầu)\n' : '') + content;
      });
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Không mở được file nhật ký. File có thể đã bị xóa hoặc hỏng.',
            kind: SnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _share(File f) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], text: 'BLE session log — Dat Bike'),
    );
  }

  Future<void> _exportAll() async {
    if (_files.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final sdk = _sdkInt;
      if (sdk != null && sdk < 29) {
        final storage = await Permission.storage.request();
        if (storage.isPermanentlyDenied) {
          if (!mounted) return;
          _openStorageSettingsDialog();
          return;
        }
        if (!storage.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thiếu quyền lưu trữ — cấp quyền rồi thử lại')),
          );
          return;
        }
      }
      final exported = await _exportChannel.invokeMethod<List<dynamic>>(
        'exportToDownloads',
        {'paths': _files.map((f) => f.path).toList()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã export ${exported?.length ?? 0} file → Downloads/DatBikeLogs'),
          backgroundColor: AppColors.tertiary,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export thất bại: ${e.message}\nDùng nút chia sẻ từng file'),
          backgroundColor: AppColors.errorFill,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openStorageSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Cần quyền lưu trữ', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        content: Text(
          'Quyền bị từ chối vĩnh viễn. Mở Cài đặt → Ứng dụng → Quyền → Bộ nhớ để cấp lại.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('HỦY', style: GoogleFonts.plusJakartaSans(color: AppColors.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryFill,
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

  Future<void> _deleteAll() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa tất cả nhật ký?',
      message: 'Toàn bộ session log BLE sẽ bị xóa khỏi bộ nhớ máy. Không thể hoàn tác.',
      confirmLabel: 'Xóa hết',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok) {
      await BleLogger.deleteAll();
      setState(() {
        _files = [];
        _preview = null;
        _selected = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible; // tính một lần mỗi lần build
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          'NHẬT KÝ BLUETOOTH',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Xóa toàn bộ log',
              onPressed: _deleteAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Panel(
              padding: const EdgeInsets.all(16),
              borderRadius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.description_rounded, size: 20, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'DỮ LIỆU TELEMETRY & GATT',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.05 * 11,
                          color: AppColors.textDim,
                        ),
                      ),
                      const Spacer(),
                      StatusPill(
                        label: '${_files.length} FILES',
                        color: AppColors.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mỗi lần kết nối tạo 1 file JSONL ghi lại bảng GATT, telemetry hex, '
                    'trạng thái handshake và quá trình giữ kết nối để chẩn đoán xe.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AppColors.textDim, height: 1.4),
                  ),
                  if (_dirPath != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Thư mục: $_dirPath',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Export toàn bộ → Downloads/DatBikeLogs',
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    onPressed: _files.isEmpty || _exporting ? null : _exportAll,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên file…',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final r in _LogRange.values) ...[
                        ChoiceChip(
                          label: Text(r.label),
                          selected: _range == r,
                          onSelected: (_) => setState(() => _range = r),
                          showCheckmark: false,
                          selectedColor: AppColors.primarySoft,
                          labelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _range == r ? AppColors.primary : AppColors.textDim,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (_opening) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(minHeight: 3, borderRadius: BorderRadius.circular(2)),
                  const SizedBox(height: 2),
                  Text('Đang đọc file…',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          Expanded(
            flex: _preview == null ? 2 : 1,
            child: _loading
                ? const StateView(kind: StateKind.loading, title: 'Đang tải danh sách nhật ký…')
                : _loadError != null
                    ? StateView(
                        kind: StateKind.error,
                        title: 'Không tải được nhật ký',
                        message: _loadError,
                        actionLabel: 'Thử lại',
                        onAction: _refresh,
                      )
                    : _files.isEmpty
                        ? const StateView(
                            kind: StateKind.empty,
                            icon: Icons.receipt_long_outlined,
                            title: 'Chưa có nhật ký',
                            message: 'Kết nối xe để bắt đầu ghi lại phiên BLE.',
                          )
                        : visible.isEmpty
                            ? StateView(
                                kind: StateKind.empty,
                                icon: Icons.search_off_rounded,
                                title: 'Không có kết quả',
                                message: 'Không có file nào khớp bộ lọc hiện tại.',
                                actionLabel: 'Xóa bộ lọc',
                                onAction: () => setState(() {
                                  _query = '';
                                  _range = _LogRange.all;
                                }),
                              )
                            : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: visible.length,
                    itemBuilder: (ctx, idx) {
                      final f = visible[idx];
                      final isSelected = _selected?.path == f.path;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Panel(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          borderRadius: 14,
                          borderColor: isSelected ? AppColors.secondary : null,
                          hasActiveHalo: isSelected,
                          onTap: () => _open(f),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.article_rounded : Icons.article_outlined,
                                color: isSelected ? AppColors.primary : AppColors.textDim,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.uri.pathSegments.last,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 13.5,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${(f.lengthSync() / 1024).toStringAsFixed(1)} KB · '
                                      '${f.statSync().modified.toLocal().toString().substring(0, 19)}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: AppColors.textDim,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded, size: 18),
                                color: AppColors.primary,
                                onPressed: () => _share(f),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_preview != null)
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  border: Border(top: BorderSide(color: AppColors.panelBorder, width: 1)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.panelSecondary,
                        border: Border(bottom: BorderSide(color: AppColors.panelBorder, width: 1)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'NỘI DUNG LOG CHI TIẾT',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.05 * 11,
                              color: AppColors.textDim,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy toàn bộ',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _preview!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã sao chép log vào clipboard!')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_rounded, size: 18),
                            tooltip: 'Chia sẻ file',
                            onPressed: () => _selected != null ? _share(_selected!) : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Đóng xem trước',
                            onPressed: () => setState(() => _preview = null),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _preview!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
