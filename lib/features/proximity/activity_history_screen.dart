// Smart Key — Lịch sử hoạt động (đọc từ kho lưu bền, chỉ sự kiện thật).

import 'package:flutter/material.dart';

import '../../core/proximity/activity_history.dart';
import '../../core/proximity/proximity_engine.dart' show ProximityEvent;
import '../../ui/app_theme.dart';
import '../../ui/ds/ds.dart';

class ActivityHistoryScreen extends StatefulWidget {
  /// Tiêm dữ liệu khi kiểm thử; mặc định đọc kho thật.
  final Future<List<ProximityEvent>> Function()? loader;
  const ActivityHistoryScreen({super.key, this.loader});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  List<ProximityEvent>? _all;
  ActivityKind? _filter; // null = tất cả

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await (widget.loader ?? ActivityHistory.load)();
    if (mounted) setState(() => _all = r);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final list = all == null
        ? const <ProximityEvent>[]
        : (all.where((e) => _filter == null || classifyActivity(e.kind) == _filter).toList()
          ..sort((a, b) => b.at.compareTo(a.at)));

    return DsScaffold(
      title: 'Lịch sử hoạt động',
      subtitle: 'Smart Key · sự kiện đã ghi trên điện thoại này',
      body: all == null
          ? const SkeletonGrid(count: 4)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.huge),
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('Tất cả'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    for (final k in ActivityKind.values)
                      ChoiceChip(
                        label: Text(k.label),
                        selected: _filter == k,
                        onSelected: (_) => setState(() => _filter = k),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
                    child: Text(
                      all.isEmpty
                          ? 'Chưa có hoạt động Smart Key nào được ghi.'
                          : 'Không có sự kiện thuộc nhóm này.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMd(color: AppColors.textSecondary),
                    ),
                  )
                else
                  GlassCard(
                    child: Column(
                      children: [
                        for (final e in list)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 92,
                                  child: Text(
                                    '${_two(e.at.day)}/${_two(e.at.month)} ${_two(e.at.hour)}:${_two(e.at.minute)}',
                                    style: AppTypography.labelSm(color: AppColors.textSecondary),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${classifyActivity(e.kind).label} · ${e.kind}'
                                    '${e.detail.isEmpty ? '' : ' — ${e.detail}'}',
                                    style: AppTypography.bodySm(
                                      color: classifyActivity(e.kind) == ActivityKind.error
                                          ? AppColors.red
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
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
