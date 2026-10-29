// Phòng Kiểm Nghiệm Firmware (LAB) — kiểm chứng dự đoán dịch firmware trên xe thật.
//
// Triết lý: mỗi char đã "dịch" từ Ghidra/btsnoop chỉ là DỰ ĐOÁN. Màn hình này
// cho phép: chọn char → xem dự đoán → gửi payload thật (plain/protected) →
// quan sát phản ứng của XE + dữ liệu trả về → đánh dấu ĐÚNG/SAI + ghi chú
// trải nghiệm thực tế. Kết quả lưu firmware_lab_results.jsonl (cùng thư mục
// ble_logs) + event lab_* trong session log để phân tích lại offline.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/ble/ble_logger.dart';
import '../../ui/app_theme.dart';
import 'lab_catalog.dart';

class _TestUi {
  final input = TextEditingController();
  bool isHex = false;
  LabWriteMode? modeOverride; // null = theo catalog
  int selectedPreset = -1;
  LabIoResult? last;
  bool busy = false;
  String? verdict; // pass | fail | skip
  final note = TextEditingController();
}

class FirmwareLabScreen extends ConsumerStatefulWidget {
  const FirmwareLabScreen({super.key});

  @override
  ConsumerState<FirmwareLabScreen> createState() => _FirmwareLabScreenState();
}

class _FirmwareLabScreenState extends ConsumerState<FirmwareLabScreen> {
  final _ui = <String, _TestUi>{};
  final _verdictCounts = <String, int>{'pass': 0, 'fail': 0, 'skip': 0};
  String _filter = 'all'; // all | pending | pass | fail
  bool _autoReadBack = true;
  File? _resultsFile;

  // Custom char tester
  final _customUuid = TextEditingController();
  final _customInput = TextEditingController();
  bool _customHex = false;
  LabIoResult? _customLast;
  bool _customBusy = false;

  _TestUi _stateOf(String id) => _ui.putIfAbsent(id, _TestUi.new);

  // Notifier giữ từ initState — dispose KHÔNG được dùng ref (riverpod 3).
  late final BleController _ble;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleProvider.notifier);
    // Ngừng auto-lock/anti-forget trong lúc kiểm nghiệm — không để lệnh tự
    // động chen vào giữa chuỗi test (bài học log 17:45 23/10).
    _ble.setLabMode(true);
    _loadHistory();
  }

  @override
  void dispose() {
    _ble.setLabMode(false);
    for (final u in _ui.values) {
      u.input.dispose();
      u.note.dispose();
    }
    _customUuid.dispose();
    _customInput.dispose();
    super.dispose();
  }

  Future<File> _file() async {
    if (_resultsFile != null) return _resultsFile!;
    final dir = await BleLogger.dirPath();
    return _resultsFile = File('$dir/firmware_lab_results.jsonl');
  }

  Future<void> _loadHistory() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final lastPerTest = <String, Map<String, dynamic>>{};
      final counts = <String, int>{'pass': 0, 'fail': 0, 'skip': 0};
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final rec = jsonDecode(line) as Map<String, dynamic>;
          final id = rec['test_id'] as String?;
          if (id == null) continue;
          lastPerTest[id] = rec;
        } catch (_) {}
      }
      // Đếm theo verdict CUỐI CÙNG mỗi test
      for (final rec in lastPerTest.values) {
        final v = rec['verdict'] as String?;
        if (v != null && counts.containsKey(v)) counts[v] = counts[v]! + 1;
      }
      if (!mounted) return;
      setState(() {
        _verdictCounts
          ..['pass'] = counts['pass']!
          ..['fail'] = counts['fail']!
          ..['skip'] = counts['skip']!;
        for (final e in lastPerTest.entries) {
          final s = _stateOf(e.key);
          s.verdict = e.value['verdict'] as String?;
          if (e.value['note'] is String &&
              (e.value['note'] as String).isNotEmpty) {
            s.note.text = e.value['note'] as String;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _saveVerdict(LabCharTest t, LabIoResult? r) async {
    final s = _stateOf(t.id);
    final v = s.verdict;
    if (v == null) return;
    final dec = r?.decrypted;
    final rec = {
      'ts': DateTime.now().toIso8601String(),
      'test_id': t.id,
      'name': t.name,
      'uuid': t.uuid,
      'op': r?.op ?? '',
      'input': s.input.text,
      'input_hex': s.isHex,
      'verdict': v,
      'note': s.note.text.trim(),
      'last_raw': r != null && r.payload.isNotEmpty
          ? BleLogger.hex(r.payload, maxBytes: 48)
          : '',
      'last_dec': dec != null && dec.isNotEmpty
          ? BleLogger.hex(dec, maxBytes: 48)
          : '',
      'last_error': r?.error ?? '',
      'prediction': s.selectedPreset >= 0 &&
              s.selectedPreset < t.presets.length
          ? t.presets[s.selectedPreset].prediction
          : t.readExpect,
    };
    BleLogger.instance.event('lab_verdict', Map<String, dynamic>.from(rec));
    try {
      final f = await _file();
      await f.create(recursive: true);
      await f.writeAsString('${jsonEncode(rec)}\n', mode: FileMode.append);
    } catch (_) {}
    // Đếm lại từ đầu cho chính xác (file là nguồn chuẩn)
    _verdictCounts.update(v, (x) => x + 1, ifAbsent: () => 1);
    if (mounted) setState(() {});
  }

  Future<void> _shareResults() async {
    try {
      final f = await _file();
      if (!await f.exists() || await f.length() == 0) {
        _toast('Chưa có kết quả nào để xuất.');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path)],
          text: 'Kết quả kiểm nghiệm firmware Dat Bike (LAB)',
        ),
      );
    } catch (e) {
      _toast('Lỗi chia sẻ: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.amber));
  }

  /// Parse ô input → bytes. hex=true: "31 0a" / "310a" / "0x31"; ngược lại ASCII.
  List<int>? _parseInput(String raw, bool hex) {
    var s = raw.trim();
    if (s == '__NOW__') {
      // Time-sync = GIÂY TRONG NGÀY local (0-86399, như '58607' của app gốc),
      // KHÔNG phải epoch — bản cũ gửi epoch khiến taplo hiển thị giờ UTC+0
      // (phát hiện LAB 23/10 đêm).
      final n = DateTime.now();
      s = '${n.hour * 3600 + n.minute * 60 + n.second}';
    }
    if (s.isEmpty) return hex ? <int>[] : <int>[];
    if (!hex) return s.codeUnits;
    s = s.replaceAll(' ', '').replaceAll('0x', '').toLowerCase();
    if (s.length % 2 != 0 || !RegExp(r'^[0-9a-f]*$').hasMatch(s)) return null;
    return [
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
    ];
  }

  Future<bool> _confirmRisk(LabCharTest t, String op) async {
    if (t.risk == LabRisk.safe || op == 'read') return true;
    final danger = t.risk == LabRisk.danger;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        title: Text(danger ? '⚠️ THAO TÁC NGUY HIỂM' : 'Cẩn thận',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700,
                color: danger ? Colors.redAccent : AppColors.amber)),
        content: Text(
          '${t.name}\n\nChar ${t.shortId} · $op\n\n'
          '${danger ? 'Thao tác này có thể tắt hẳn xe / mất cài đặt / mất bond. Chỉ tiếp tục khi đang đứng cạnh xe và sẵn sàng xử lý hậu quả.' : 'Thao tác ảnh hưởng trạng thái xe (settings/khóa/nguồn). Xe cần đang đứng yên, không đang chạy.'}',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger ? Colors.redAccent : AppColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('VẪN TIẾN HÀNH'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _runOp(LabCharTest t, String op) async {
    final s = _stateOf(t.id);
    if (s.busy) return;
    final ble = ref.read(bleProvider.notifier);
    final st = ref.read(bleProvider);

    List<int>? data;
    if (op != 'read') {
      data = _parseInput(s.input.text, s.isHex);
      if (data == null) {
        _toast('Ô nhập HEX không hợp lệ cho ${t.shortId}');
        return;
      }
      if (!await _confirmRisk(t, op == 'read' ? 'đọc' : 'ghi')) return;
    }
    if (st.phase != BlePhase.connected) {
      _toast('Xe chưa kết nối — không test được.');
      return;
    }

    setState(() => s.busy = true);
    try {
      LabIoResult r;
      if (op == 'read') {
        r = await ble.labRead(t.uuid, testId: t.id);
      } else {
        final plain = (s.modeOverride ?? t.writeMode) == LabWriteMode.plain;
        r = plain
            ? await ble.labWritePlain(t.uuid, data!, testId: t.id)
            : await ble.labWriteProtected(t.uuid, data!, testId: t.id);
        // Tự đọc lại sau ghi — settings cần ~150ms firmware parse xong
        if (_autoReadBack && r.ok && t.canRead) {
          await Future.delayed(const Duration(milliseconds: 200));
          s.last = await ble.labRead(t.uuid, testId: t.id);
          if (mounted) setState(() {});
          return;
        }
      }
      s.last = r;
    } finally {
      s.busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _runCustom(String op) async {
    if (_customBusy) return;
    final uuid = _customUuid.text.trim().toLowerCase();
    if (uuid.isEmpty) {
      _toast('Nhập UUID char cần test.');
      return;
    }
    final ble = ref.read(bleProvider.notifier);
    final st = ref.read(bleProvider);
    if (st.phase != BlePhase.connected) {
      _toast('Xe chưa kết nối.');
      return;
    }
    List<int>? data;
    if (op != 'read') {
      data = _parseInput(_customInput.text, _customHex);
      if (data == null) {
        _toast('Ô nhập HEX không hợp lệ.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bg,
          title: Text('Ghi char tuỳ chỉnh?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          content: Text('Ghi $op lên char không có trong catalog — hiệu ứng KHÔNG DỰ ĐOÁN ĐƯỢC. Tiếp tục?',
              style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GHI')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _customBusy = true);
    try {
      _customLast = op == 'read'
          ? await ble.labRead(uuid, testId: 'custom')
          : (op == 'write_plain'
              ? await ble.labWritePlain(uuid, data!, testId: 'custom')
              : await ble.labWriteProtected(uuid, data!, testId: 'custom'));
    } finally {
      _customBusy = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final connected = ble.phase == BlePhase.connected;

    final shown = labCatalog.where((t) {
      final v = _stateOf(t.id).verdict;
      return _filter == 'all' ||
          (_filter == 'pending' && v == null) ||
          (_filter == 'pass' && v == 'pass') ||
          (_filter == 'fail' && v == 'fail');
    }).toList();

    final grouped = <String, List<LabCharTest>>{};
    for (final t in shown) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          '🧪 KIỂM NGHIỆM FIRMWARE',
          style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: 'Xuất kết quả (JSONL)',
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: _shareResults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
        children: [
          _buildStatusCard(ble, connected),
          const SizedBox(height: 12),
          _buildCustomCard(connected),
          const SizedBox(height: 18),
          _buildFilterRow(),
          const SizedBox(height: 8),
          for (final cat in labCategories)
            if (grouped.containsKey(cat)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Text(
                  cat,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textDim),
                ),
              ),
              for (final t in grouped[cat]!) ...[
                _buildTestCard(t, connected),
                const SizedBox(height: 10),
              ],
            ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(BleState ble, bool connected) {
    final tested = _verdictCounts['pass']! + _verdictCounts['fail']! + _verdictCounts['skip']!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  size: 16, color: connected ? AppColors.tertiary : AppColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  connected
                      ? 'Đã kết nối ${ble.bikeName ?? ''} · ${ble.isAuthorized ? "đã xác thực ✓" : "CHƯA xác thực"} · session key ${ble.sessionKey != null ? "✓" : "✗"}'
                      : 'Xe chưa kết nối — chỉ xem được dự đoán, không test được.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Cách dùng: mở 1 char → đọc DỰ ĐOÁN → gửi → quan sát XE + dữ liệu trả về → bấm ✅ĐÚNG hoặc ❌SAI (kèm ghi chú thực tế). Kết quả: $tested/${labCatalog.length} đã kiểm · ✅${_verdictCounts['pass']} ❌${_verdictCounts['fail']} ⏭${_verdictCounts['skip']}',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AppColors.textDim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.4)),
                  ),
                  onPressed: connected
                      ? () async {
                          _toast('Đang quét toàn bộ char đọc được (xem log sniff_*)…');
                          await ref.read(bleProvider.notifier).sniffAllCharacteristics();
                        }
                      : null,
                  icon: const Icon(Icons.radar_rounded, size: 16),
                  label: Text('QUÉT TẤT CẢ CHAR', style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _autoReadBack = !_autoReadBack),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.textDim.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 18, width: 18,
                          child: Checkbox(
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            value: _autoReadBack,
                            onChanged: (v) => setState(() => _autoReadBack = v ?? true),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Tự đọc lại sau ghi', style: GoogleFonts.plusJakartaSans(fontSize: 10.5))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCard(bool connected) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textDim.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHAR TÙY CHỈNH (không trong danh sách)',
              style: GoogleFonts.spaceGrotesk(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customUuid,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'UUID đầy đủ hoặc 8 hex đầu', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              _hexToggle(() => setState(() => _customHex = !_customHex), _customHex),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _customInput,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'Payload (text/HEX)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: FilledButton.tonal(
                onPressed: connected && !_customBusy ? () => _runCustom('read') : null,
                child: const Text('ĐỌC', style: TextStyle(fontSize: 11)),
              )),
              const SizedBox(width: 6),
              Expanded(child: FilledButton.tonal(
                onPressed: connected && !_customBusy ? () => _runCustom('write_plain') : null,
                child: const Text('GHI PLAIN', style: TextStyle(fontSize: 11)),
              )),
              const SizedBox(width: 6),
              Expanded(child: FilledButton(
                onPressed: connected && !_customBusy ? () => _runCustom('write_protected') : null,
                child: const Text('GHI PROTECTED', style: TextStyle(fontSize: 11)),
              )),
            ],
          ),
          if (_customLast != null) ...[
            const SizedBox(height: 8),
            _resultView(_customLast!),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    Widget chip(String id, String label) {
      final sel = _filter == id;
      return ChoiceChip(
        label: Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 11)),
        selected: sel,
        onSelected: (_) => setState(() => _filter = id),
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        chip('all', 'TẤT CẢ (${labCatalog.length})'),
        chip('pending', 'CHƯA KIỂM'),
        chip('pass', '✅ ĐÚNG (${_verdictCounts['pass']})'),
        chip('fail', '❌ SAI (${_verdictCounts['fail']})'),
      ],
    );
  }

  Widget _hexToggle(VoidCallback onTap, bool active) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.secondary.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.textDim.withValues(alpha: 0.4)),
        ),
        child: Text(active ? 'HEX' : 'TXT', style: GoogleFonts.spaceGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildTestCard(LabCharTest t, bool connected) {
    final s = _stateOf(t.id);
    final canWrite = t.writeMode != LabWriteMode.none;
    final defaultPlain = (s.modeOverride ?? t.writeMode) == LabWriteMode.plain;
    final preset = s.selectedPreset >= 0 && s.selectedPreset < t.presets.length
        ? t.presets[s.selectedPreset]
        : null;
    final riskColor = t.risk == LabRisk.danger
        ? Colors.redAccent
        : t.risk == LabRisk.caution
            ? AppColors.amber
            : AppColors.tertiary;
    final riskLabel = t.risk == LabRisk.danger ? 'NGUY HIỂM' : t.risk == LabRisk.caution ? 'CẨN TRỌNG' : 'AN TOÀN';
    final verdictIcon = s.verdict == 'pass'
        ? const Icon(Icons.check_circle_rounded, color: AppColors.tertiary, size: 18)
        : s.verdict == 'fail'
            ? const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 18)
            : s.verdict == 'skip'
                ? Icon(Icons.skip_next_rounded, color: AppColors.textDim, size: 18)
                : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: s.verdict == 'fail'
              ? Colors.redAccent.withValues(alpha: 0.5)
              : s.verdict == 'pass'
                  ? AppColors.tertiary.withValues(alpha: 0.4)
                  : AppColors.textDim.withValues(alpha: 0.25),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              if (t.name.contains('⭐')) const Text('⭐', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  t.name,
                  style: GoogleFonts.spaceGrotesk(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              if (verdictIcon != null) verdictIcon, // ignore: use_null_aware_elements
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('${t.shortId} · $riskLabel',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5, color: riskColor, fontWeight: FontWeight.w600)),
          ),
          children: [
            // Bằng chứng + dự đoán + quan sát
            Align(
              alignment: Alignment.centerLeft,
              child: Text('📎 ${t.evidence}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textDim)),
            ),
            const SizedBox(height: 6),
            if (t.readExpect.isNotEmpty)
              _infoBox('DỰ ĐOÁN KHI ĐỌC', t.readExpect, AppColors.amber, Icons.visibility_rounded),
            if (preset != null) ...[
              const SizedBox(height: 6),
              _infoBox('DỰ ĐOÁN: ${preset.label}', preset.prediction, AppColors.amber, Icons.science_rounded),
            ],
            if (t.observed != null) ...[
              const SizedBox(height: 6),
              _infoBox('ĐÃ QUAN SÁT', t.observed!, AppColors.tertiary, Icons.history_rounded),
            ],
            if (t.verifyHint.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoBox('CÁCH KIỂM', t.verifyHint, AppColors.secondary, Icons.checklist_rounded),
            ],
            const SizedBox(height: 10),

            // Presets
            if (t.presets.any((p) => p.data.isNotEmpty))
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < t.presets.length; i++)
                    if (t.presets[i].data.isNotEmpty)
                      ChoiceChip(
                        label: Text(t.presets[i].label, style: GoogleFonts.plusJakartaSans(fontSize: 10.5)),
                        selected: s.selectedPreset == i,
                        onSelected: (_) => setState(() {
                          s.selectedPreset = i;
                          s.input.text = t.presets[i].data;
                          s.isHex = t.presets[i].hex;
                        }),
                      ),
                ],
              ),
            const SizedBox(height: 8),

            // Input + nút
            if (canWrite)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: s.input,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5),
                      decoration: const InputDecoration(
                          isDense: true, hintText: 'Payload gửi (text/HEX)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _hexToggle(() => setState(() => s.isHex = !s.isHex), s.isHex),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            labelPadding: EdgeInsets.zero,
                            label: Center(child: Text('PROT', style: GoogleFonts.spaceGrotesk(fontSize: 9.5))),
                            selected: !defaultPlain,
                            onSelected: (_) => setState(() => s.modeOverride = LabWriteMode.protected),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ChoiceChip(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            labelPadding: EdgeInsets.zero,
                            label: Center(child: Text('PLAIN', style: GoogleFonts.spaceGrotesk(fontSize: 9.5))),
                            selected: defaultPlain,
                            onSelected: (_) => setState(() => s.modeOverride = LabWriteMode.plain),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (t.canRead)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connected && !s.busy ? () => _runOp(t, 'read') : null,
                      icon: s.busy
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 15),
                      label: Text('ĐỌC', style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                    ),
                  ),
                if (t.canRead && canWrite) const SizedBox(width: 8),
                if (canWrite)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: t.risk == LabRisk.danger ? Colors.redAccent : null),
                      onPressed: connected && !s.busy ? () => _runOp(t, 'write') : null,
                      icon: s.busy
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_rounded, size: 15),
                      label: Text('GHI', style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                    ),
                  ),
              ],
            ),

            // Kết quả gần nhất
            if (s.last != null) ...[
              const SizedBox(height: 8),
              _resultView(s.last!),
            ],

            // Verdict
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _verdictBtn(t, s, 'pass', '✅ ĐÚNG', AppColors.tertiary)),
                const SizedBox(width: 6),
                Expanded(child: _verdictBtn(t, s, 'fail', '❌ SAI', Colors.redAccent)),
                const SizedBox(width: 6),
                Expanded(child: _verdictBtn(t, s, 'skip', '⏭ BỎ', AppColors.textDim)),
              ],
            ),
            if (s.verdict == 'pass' || s.verdict == 'fail') ...[
              const SizedBox(height: 8),
              TextField(
                controller: s.note,
                style: GoogleFonts.plusJakartaSans(fontSize: 11.5),
                maxLines: 2,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: s.verdict == 'fail'
                      ? 'Thực tế xe phản ứng thế nào? (bắt buộc — đây là dữ liệu sửa dự đoán)'
                      : 'Ghi chú thêm (không bắt buộc)',
                ),
                onChanged: (_) => _saveVerdictDebounced(t),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  // Ghi verdict khi bấm nút; note thay đổi thì ghi lại sau 1.2s ngừng gõ
  Timer? _noteDebounce;

  void _saveVerdictDebounced(LabCharTest t) {
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 1200), () {
      _saveVerdict(t, _stateOf(t.id).last);
    });
  }

  Widget _verdictBtn(LabCharTest t, _TestUi s, String v, String label, Color color) {
    final sel = s.verdict == v;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: sel ? color.withValues(alpha: 0.18) : null,
        side: BorderSide(color: color.withValues(alpha: sel ? 0.8 : 0.35)),
        padding: const EdgeInsets.symmetric(vertical: 6),
      ),
      onPressed: () {
        setState(() => s.verdict = v);
        _saveVerdict(t, s.last);
      },
      child: Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10.5, color: color)),
    );
  }

  Widget _infoBox(String title, String body, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$title\n',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, fontWeight: FontWeight.w700, color: color),
                  ),
                  TextSpan(
                    text: body,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: AppColors.textPrimary, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView(LabIoResult r) {
    final color = r.ok ? AppColors.tertiary : Colors.redAccent;
    final lines = <String>[
      '[${r.op}] ${r.ok ? 'OK' : 'LỖI'} · ${r.elapsedMs}ms',
      if (r.error != null) 'error: ${r.error}',
      if (r.payload.isNotEmpty) 'raw (${r.payload.length}B): ${BleLogger.hex(r.payload, maxBytes: 64)}',
      if (r.decrypted != null && r.decrypted!.isNotEmpty)
        'dec (${r.decrypted!.length}B): ${BleLogger.hex(r.decrypted!, maxBytes: 64)}',
      if (r.decrypted != null && r.decrypted!.isNotEmpty && BleLogger.tryUtf8(r.decrypted!) != null)
        'text: "${BleLogger.tryUtf8(r.decrypted!)}"',
      if (r.decrypted == null && r.text != null && r.text!.isNotEmpty && r.op == 'read')
        'text: "${r.text}"',
      if (r.parsed != null && r.parsed!.isNotEmpty)
        'parsed: ${r.parsed}',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        lines.join('\n'),
        style: GoogleFonts.jetBrainsMono(fontSize: 10.5, height: 1.5, color: AppColors.textPrimary),
      ),
    );
  }
}
