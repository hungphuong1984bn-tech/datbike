// OTA — Xem firmware mới nhất + tải board về máy (Kinetic Stitch EV).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ota/ota_service.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets.dart';

class OtaScreen extends ConsumerStatefulWidget {
  const OtaScreen({super.key});

  @override
  ConsumerState<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends ConsumerState<OtaScreen> {
  final _ota = OtaService();
  Future<FirmwareRelease?>? _future;
  final _progress = <String, double>{};
  final _done = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _ota.fetchLatest();
  }

  Future<void> _download(BoardFirmware b) async {
    setState(() => _progress[b.board] = 0.0);
    try {
      final file = await _ota.downloadBoard(b, onProgress: (p) {
        if (mounted) setState(() => _progress[b.board] = p);
      });
      if (!mounted) return;
      setState(() => _done.add(b.board));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã tải ${b.board} → ${file.path}'),
          backgroundColor: AppColors.tertiary,
        ),
      );
    } on OtaException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.errorFill),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        centerTitle: true,
        title: Text(
          'OTA Firmware',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: FutureBuilder<FirmwareRelease?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final fw = snap.data;
          if (fw == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Không thể kết nối máy chủ OTA',
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kiểm tra lại kết nối Internet hoặc thử lại sau.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AppColors.textDim),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryFill,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () => setState(() => _future = _ota.fetchLatest()),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('Thử lại', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // Hero Firmware Version Card
              Panel(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                hasActiveHalo: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.system_update_rounded, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BẢN PHÁT HÀNH MỚI NHẤT',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.06 * 10.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Firmware ${fw.version}',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fw.isBeta)
                          StatusPill(label: 'Bản thử nghiệm', color: AppColors.amber)
                        else
                          StatusPill(label: 'Bản chính thức', color: AppColors.tertiary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: AppColors.panelBorder, height: 1),
                    const SizedBox(height: 14),
                    Text(
                      fw.releaseNote.replaceAll(RegExp(r'<[^>]+>'), ''),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        color: AppColors.textDim,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const SectionTitle('DANH SÁCH BO MẠCH (BOARDS)'),
              const SizedBox(height: 10),

              for (final b in fw.boards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _done.contains(b.board)
                                  ? Icons.check_circle_rounded
                                  : Icons.memory_rounded,
                              color: _done.contains(b.board) ? AppColors.tertiary : AppColors.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.board,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Revision: ${b.revision ?? "Mặc định"}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _done.contains(b.board)
                                ? StatusPill(label: 'ĐÃ TẢI', color: AppColors.tertiary)
                                : IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.panelSecondary,
                                      foregroundColor: AppColors.primary,
                                    ),
                                    icon: const Icon(Icons.download_rounded, size: 20),
                                    tooltip: 'Tải về máy',
                                    onPressed: () => _download(b),
                                  ),
                          ],
                        ),
                        if (_progress.containsKey(b.board) && !_done.contains(b.board)) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9999),
                            child: LinearProgressIndicator(
                              value: _progress[b.board],
                              minHeight: 5,
                              color: AppColors.primary,
                              backgroundColor: AppColors.panelSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 14),
              NoticeBanner(
                color: AppColors.secondary,
                text: 'Lưu ý: Chỉ tải firmware để tham chiếu hoặc cập nhật khi có hướng dẫn kỹ thuật. '
                    'Truyền OTA BLE qua FAST_OTA service sẽ được mở ở Phase tiếp theo.',
              ),
            ],
          );
        },
      ),
    );
  }
}
