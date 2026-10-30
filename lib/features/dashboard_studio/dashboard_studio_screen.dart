// Dashboard Studio — tùy biến App Dashboard (đồng hồ TRÊN ĐIỆN THOẠI) và hiển
// thị trạng thái trung thực của Dashboard Sync (đồng bộ lên đồng hồ xe).
//
// Hai chế độ tách bạch:
//  • App Dashboard  : chạy trên điện thoại — hoàn chỉnh, độc lập.
//  • On-Bike Display Sync : CHƯA hỗ trợ (không có bằng chứng giao thức). Không
//    có nút "Đồng bộ lên xe" cho tới khi DisplaySyncSpec được xác minh.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../core/dashboard/dashboard_model.dart';
import '../../core/dashboard/dashboard_store.dart';
import '../../core/dashboard/dashboard_sync.dart';
import '../../core/regen/regen_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/widgets.dart';
import 'dashboard_live_screen.dart';
import 'dashboard_view.dart';

const List<int> _accentChoices = [
  0xFFFF4D2E, // đỏ cam
  0xFFD4AF6A, // vàng đồng
  0xFF00F0FF, // cyan
  0xFF14B8A6, // teal
  0xFF22C55E, // xanh lá
  0xFF3B82F6, // xanh dương
  0xFFA855F7, // tím
  0xFFFFB300, // hổ phách
];

class DashboardStudioScreen extends ConsumerWidget {
  const DashboardStudioScreen({super.key});

  Future<String?> _askName(BuildContext context, String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('studio_name_field'),
          controller: c,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'Tên cấu hình'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardStoreProvider);
    final store = ref.read(dashboardStoreProvider.notifier);
    final p = data.active;
    final ble = ref.watch(bleProvider);
    final regen = ref.watch(regenProvider);
    final sync = ref.watch(dashboardSyncProvider);

    final input = buildDashInput(
      ble: ble,
      lastTelemetryAt: ref.read(bleProvider.notifier).lastTelemetryAt,
      now: DateTime.now(),
      regenLevel: regen.currentIndex,
    );
    final values = resolveDash(input);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Xưởng Đồng hồ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle('Xem trước (dữ liệu thật, thiếu thì "--")'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 11,
                child: DashboardView(profile: p, values: values, compact: true),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('studio_open_live'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardLiveScreen()),
              ),
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Mở đồng hồ phụ toàn màn hình'),
            ),
            const SizedBox(height: 4),
            Text(
              'Đồng hồ phụ chạy trên điện thoại, tách biệt với đồng hồ nguyên bản của xe.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Cấu hình đã lưu'),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final q in data.profiles)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('studio_profile_${q.id}'),
                        label: Text(q.name),
                        selected: q.id == data.activeId,
                        onSelected: (_) => store.setActive(q.id),
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('studio_add'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Lưu thành cấu hình mới'),
                  onPressed: () async {
                    final n = await _askName(
                      context,
                      'Tên cấu hình mới',
                      'Cấu hình ${data.profiles.length + 1}',
                    );
                    if (n != null) store.addFromActive(n);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Đổi tên'),
                  onPressed: () async {
                    final n = await _askName(context, 'Đổi tên', p.name);
                    if (n != null) store.rename(n);
                  },
                ),
                OutlinedButton.icon(
                  key: const Key('studio_delete'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Xóa'),
                  onPressed: data.profiles.length <= 1
                      ? null
                      : () async {
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Xóa cấu hình?',
                            message: 'Xóa "${p.name}"?',
                          );
                          if (ok) store.deleteActive();
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionTitle('Giao diện'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in DashTheme.values)
                  ChoiceChip(
                    key: Key('studio_theme_${t.name}'),
                    label: Text(t.label),
                    selected: p.theme == t,
                    onSelected: (_) =>
                        store.updateActive((x) => x.copyWith(theme: t)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.theme.blurb,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            const Text(
              'Màu nhấn',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Theo giao diện'),
                  selected: p.accent == null,
                  onSelected: (_) =>
                      store.updateActive((x) => x.copyWith(accent: null)),
                ),
                for (final c in _accentChoices)
                  InkWell(
                    key: Key('studio_accent_${c.toRadixString(16)}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () =>
                        store.updateActive((x) => x.copyWith(accent: c)),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: p.accent == c
                              ? AppColors.textPrimary
                              : AppColors.panelBorderBright,
                          width: p.accent == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Bố cục', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<DashLayout>(
              key: const Key('studio_layout'),
              segments: const [
                ButtonSegment(
                  value: DashLayout.classic,
                  label: Text('Cổ điển'),
                ),
                ButtonSegment(
                  value: DashLayout.focus,
                  label: Text('Tập trung'),
                ),
                ButtonSegment(value: DashLayout.split, label: Text('Chia đôi')),
              ],
              selected: {p.layout},
              onSelectionChanged: (s) =>
                  store.updateActive((x) => x.copyWith(layout: s.first)),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Widget hiển thị'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final w in DashWidgetId.values)
                  FilterChip(
                    key: Key('studio_widget_${w.name}'),
                    label: Text(
                      w == DashWidgetId.headlight
                          ? '${w.label} (xe không cung cấp)'
                          : w.label,
                    ),
                    selected: p.widgets.contains(w),
                    onSelected: (on) {
                      final cur = List<DashWidgetId>.of(p.widgets);
                      if (on) {
                        cur.add(w);
                      } else if (cur.length > 1) {
                        cur.remove(w);
                      } else {
                        showAppSnack(
                          context,
                          'Cần giữ ít nhất 1 widget.',
                          kind: SnackKind.warning,
                        );
                        return;
                      }
                      // Giữ thứ tự theo enum cho bố cục ổn định.
                      cur.sort((a, b) => a.index.compareTo(b.index));
                      store.updateActive((x) => x.copyWith(widgets: cur));
                    },
                  ),
              ],
            ),
            SwitchListTile(
              key: const Key('studio_always_on'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Always-On: giữ sáng màn hình khi mở đồng hồ'),
              value: p.alwaysOn,
              onChanged: (v) =>
                  store.updateActive((x) => x.copyWith(alwaysOn: v)),
            ),
            const SizedBox(height: 12),
            const SectionTitle('Đồng bộ lên đồng hồ xe (Dashboard Sync)'),
            const SizedBox(height: 8),
            _SyncCard(engine: sync),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  final DashboardSyncEngine engine;
  const _SyncCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final st = engine.state;
    final supported = engine.canOfferSync;
    return Panel(
      key: const Key('studio_sync_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                supported ? Icons.sync_rounded : Icons.block_rounded,
                color: supported ? AppColors.greenText : AppColors.amberText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  supported
                      ? 'Sẵn sàng đồng bộ'
                      : 'Chưa thể đồng bộ giao diện lên màn hình xe',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Trạng thái: ${st.status.name}. ${st.message}',
            key: const Key('studio_sync_status'),
          ),
          const SizedBox(height: 8),
          Text(
            'Bằng chứng đã kiểm tra:',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          for (final e in engine.spec.evidence)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• $e',
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Vì vậy việc đổi giao diện ở đây CHỈ ảnh hưởng đồng hồ trên điện thoại. '
            'App không ghi gì lên màn hình xe và không báo "đã đồng bộ". Lớp '
            'Dashboard Sync đã sẵn kiến trúc (trạng thái, tiến trình, ACK, thử lại) '
            'để dùng khi có bằng chứng giao thức.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
