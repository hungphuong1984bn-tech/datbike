// Cửa hàng & dịch vụ Dat Bike — danh sách theo tỉnh/thành, tìm kiếm, gọi hotline,
// mở Google Maps theo địa chỉ. Không có tọa độ → không sắp xếp theo khoảng cách,
// không khẳng định cửa hàng có trạm sạc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/charging/datbike_store.dart';
import '../../core/charging/external_nav.dart';
import '../../ui/app_theme.dart';

class StoreListScreen extends StatefulWidget {
  const StoreListScreen({super.key});

  @override
  State<StoreListScreen> createState() => _StoreListScreenState();
}

class _StoreListScreenState extends State<StoreListScreen> {
  final TextEditingController _q = TextEditingController();
  List<DatBikeStore> _all = const [];
  bool _loading = true;
  String? _province;

  @override
  void initState() {
    super.initState();
    DatBikeStoreRepository.load().then((v) {
      if (mounted) {
        setState(() {
          _all = v;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openMaps(DatBikeStore s) async {
    final ok = await ExternalNav.openUrl(s.mapsSearchUri.toString());
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: s.address));
      _toast('Không mở được Google Maps. Đã chép địa chỉ.');
    }
  }

  Future<void> _call(String phone) async {
    if (!await ExternalNav.dial(phone) && mounted) _toast('Không mở được trình quay số.');
  }

  @override
  Widget build(BuildContext context) {
    final provinces = DatBikeStoreRepository.provinces(_all);
    final shown = DatBikeStoreRepository.filter(_all, province: _province, query: _q.text);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Cửa hàng & dịch vụ Dat Bike')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Tìm theo tên, địa chỉ, hotline',
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('Tất cả (${_all.length})'),
                          selected: _province == null,
                          onSelected: (_) => setState(() => _province = null),
                        ),
                      ),
                      for (final p in provinces)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(p),
                            selected: _province == p,
                            onSelected: (_) => setState(() => _province = _province == p ? null : p),
                          ),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
                  child: Text(
                    'Danh sách do bạn cung cấp. Chưa có dữ liệu cửa hàng nào có trạm sạc; '
                    'giờ làm việc có thể thay đổi, hãy gọi hotline để xác nhận.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(child: Text('Không có cửa hàng phù hợp.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _card(shown[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _card(DatBikeStore s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(s.address, style: const TextStyle(fontSize: 12.5, height: 1.3)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.schedule_rounded, size: 15),
              const SizedBox(width: 4),
              Expanded(child: Text(s.hours, style: const TextStyle(fontSize: 12))),
            ],
          ),
          if (s.salesOnly)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Chỉ bán xe/bán hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in s.phones)
                OutlinedButton.icon(
                  onPressed: () => _call(p),
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: Text(p),
                ),
              FilledButton.icon(
                onPressed: () => _openMaps(s),
                icon: const Icon(Icons.map_rounded, size: 16),
                label: const Text('Google Maps'),
              ),
              IconButton(
                tooltip: 'Chép địa chỉ',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.address));
                  if (mounted) _toast('Đã chép địa chỉ.');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
