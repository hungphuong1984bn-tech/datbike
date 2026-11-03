// Dashboard phân tích dữ liệu trạm sạc (dành cho quản trị viên).
//
// Mọi con số lấy từ log thật trên thiết bị (station_log.dart). Chưa có log →
// hiển thị "Chưa có dữ liệu", KHÔNG dựng số liệu mẫu. Heatmap chỉ vẽ các ô có
// sự kiện kèm tọa độ khu vực mà người dùng đã đồng ý ghi (làm tròn ~1 km).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/charging/station_analytics.dart';
import '../../core/charging/station_log.dart';
import '../../core/charging/station_proposal_store.dart';
import '../../core/charging/station_sync.dart';
import '../../core/services/charging_station_service.dart';
import '../../core/services/map_tile_service.dart';
import '../../ui/app_theme.dart';
import 'station_export.dart';
import 'station_widgets.dart';

class StationDashboardScreen extends StatefulWidget {
  final List<ChargingStation> stations;
  final LatLng? center;
  const StationDashboardScreen({super.key, required this.stations, this.center});

  @override
  State<StationDashboardScreen> createState() => _StationDashboardScreenState();
}

class _StationDashboardScreenState extends State<StationDashboardScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.week;
  List<StationActivityLog> _logs = const [];
  int _pending = 0;
  bool _areaConsent = false;
  SyncStatus? _sync;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await StationLogStore.all();
    final props = await StationProposalStore.all();
    final consent = await StationLogConsent.area();
    final sync = await StationSyncService.status();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _pending = props.length;
      _areaConsent = consent;
      _sync = sync;
      _loading = false;
    });
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await StationSyncService.syncNow();
    if (!mounted) return;
    setState(() => _syncing = false);
    _toast(r.message);
    await _load();
  }

  Future<void> _export() async {
    try {
      await shareTextFile('thbike_station_activity_${DateTime.now().millisecondsSinceEpoch}.json', await StationLogStore.exportJson(),
          caption: 'Nhật ký hoạt động trạm sạc THBIKE (ẩn danh)');
    } catch (e) {
      if (mounted) _toast('Lỗi xuất: $e');
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa toàn bộ nhật ký?'),
        content: const Text('Xóa nhật ký hoạt động trạm sạc trên máy này. Không ảnh hưởng dữ liệu trạm.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await StationLogStore.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final a = StationAnalytics.compute(_logs, widget.stations, now: DateTime.now(), period: _period);
    final counts = StationCounts.from(widget.stations, pendingProposals: _pending);
    final title = GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Phân tích trạm sạc'),
        actions: [
          IconButton(tooltip: 'Làm mới', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'export' ? _export() : _clear(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Xuất nhật ký (JSON)')),
              PopupMenuItem(value: 'clear', child: Text('Xóa nhật ký')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
              children: [
                Text('Mạng lưới trạm (đang tải trên bản đồ)', style: title),
                const SizedBox(height: 8),
                _kpiRow([
                  _Kpi('Tổng số trạm', '${counts.total}', Icons.ev_station_rounded, AppColors.primary),
                  _Kpi('Đã xác minh', '${counts.verified}', Icons.verified_rounded, const Color(0xFF16A34A)),
                  _Kpi('Chưa xác minh', '${counts.unverified}', Icons.help_outline_rounded, const Color(0xFFF59E0B)),
                ]),
                const SizedBox(height: 8),
                _kpiRow([
                  _Kpi('Chờ duyệt', '${counts.pendingProposals}', Icons.pending_actions_rounded, const Color(0xFF2563EB)),
                  _Kpi('Tạm ngừng', '${counts.paused}', Icons.pause_circle_outline_rounded, const Color(0xFF8B95A5)),
                  _Kpi('Người dùng (ẩn danh)', '${a.uniqueUsers}', Icons.people_outline_rounded, AppColors.cyan),
                ]),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Text('Hoạt động người dùng', style: title)),
                    SegmentedButton<AnalyticsPeriod>(
                      showSelectedIcon: false,
                      segments: [for (final p in AnalyticsPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
                      selected: {_period},
                      onSelectionChanged: (s) => setState(() => _period = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kpiRow([
                  _Kpi('Lượt xem trạm', '${a.views}', Icons.visibility_outlined, AppColors.primary),
                  _Kpi('Nhấn Dẫn đường', '${a.navigates}', Icons.navigation_outlined, const Color(0xFF16A34A)),
                  _Kpi('Lỗi bản đồ/GPS', '${a.errors}', Icons.error_outline_rounded, const Color(0xFFDC2626)),
                ]),
                if (a.navigateFailures > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${a.navigateFailures} lần không mở được Google Maps.', style: TextStyle(fontSize: 12, color: AppColors.amberText)),
                  ),
                const SizedBox(height: 10),
                _chart(a),
                const SizedBox(height: 18),
                Text('Trạm được quan tâm nhiều nhất', style: title),
                const SizedBox(height: 6),
                if (a.top.isEmpty) _empty('Chưa có lượt xem/dẫn đường nào trong khoảng này.'),
                for (final r in a.top)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r.views} xem · ${r.details} chi tiết · ${r.navigates} dẫn đường'),
                  ),
                const SizedBox(height: 14),
                Text('Điểm/khu vực được tìm nhiều', style: title),
                const SizedBox(height: 6),
                if (a.searches.isEmpty) _empty('Chưa có lượt tìm kiếm nào trong khoảng này.'),
                for (final s in a.searches)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.search_rounded, size: 18),
                    title: Text(s.term),
                    trailing: Text('${s.count} lần'),
                  ),
                const SizedBox(height: 18),
                Text('Bản đồ nhiệt nhu cầu tìm trạm', style: title),
                const SizedBox(height: 4),
                Text(
                  'Dựa trên tìm kiếm, xem trạm, Dẫn đường và khu vực không có trạm — chỉ từ người dùng đã đồng ý ghi khu vực (làm tròn ~1 km).',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                ),
                const SizedBox(height: 8),
                _heatmap(a),
                const SizedBox(height: 12),
                Text('Khu vực có nhu cầu nhưng chưa có trạm (>3 km)', style: title),
                const SizedBox(height: 6),
                if (a.uncovered.isEmpty) _empty('Chưa có khu vực nào được ghi nhận là thiếu trạm.'),
                for (final c in a.uncovered)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_searching_rounded, size: 18),
                    title: Text('${c.lat.toStringAsFixed(2)}, ${c.lng.toStringAsFixed(2)}'),
                    trailing: Text('mức ${c.weight}'),
                  ),
                const SizedBox(height: 18),
                Text('Thu thập dữ liệu & đồng bộ', style: title),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ghi khu vực tìm trạm (làm tròn ~1 km)'),
                  subtitle: const Text('Cần cho Heatmap. Tắt thì chỉ ghi lượt xem/tìm kiếm, không có tọa độ.'),
                  value: _areaConsent,
                  onChanged: (v) async {
                    await StationLogConsent.setArea(v);
                    await _load();
                  },
                ),
                Text(_sync?.message ?? '', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                    label: const Text('Đồng bộ ngay'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(t, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      );

  Widget _kpiRow(List<_Kpi> items) => Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: items[i]),
          ],
        ],
      );

  Widget _chart(StationAnalytics a) {
    if (a.isEmpty) return _empty('Chưa có hoạt động nào trong khoảng này.');
    final max = a.series.fold<int>(1, (m, v) => v > m ? v : m);
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.panelBorderBright),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < a.series.length; i++)
            Expanded(
              child: Tooltip(
                message: '${StationUi.dateTime(a.bucketStart[i])}: ${a.series[i]} sự kiện',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: FractionallySizedBox(
                    heightFactor: a.series[i] == 0 ? 0.02 : (a.series[i] / max).clamp(0.05, 1.0).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: a.series[i] == 0 ? 0.2 : 0.9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heatmap(StationAnalytics a) {
    if (a.heat.isEmpty) {
      return Container(
        height: 110,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.panelBorderBright),
        ),
        child: Text(
          _areaConsent
              ? 'Chưa có dữ liệu khu vực. Heatmap sẽ xuất hiện khi người dùng tìm trạm hoặc bấm Dẫn đường.'
              : 'Chưa bật ghi khu vực nên chưa có dữ liệu cho Heatmap.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    final maxW = a.heat.first.weight; // đã sắp giảm dần
    final center = LatLng(a.heat.first.lat, a.heat.first.lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 300,
        child: FlutterMap(
          options: MapOptions(initialCenter: widget.center ?? center, initialZoom: 9, minZoom: 3, maxZoom: 16),
          children: [
            MapTileService.buildTileLayer(style: AppColors.isDark ? MapTileStyle.darkEv : MapTileStyle.fastCdn),
            CircleLayer(circles: [
              for (final c in a.heat)
                CircleMarker(
                  point: LatLng(c.lat, c.lng),
                  radius: 1200,
                  useRadiusInMeter: true,
                  color: Color.lerp(const Color(0xFFFACC15), const Color(0xFFDC2626), c.weight / maxW)!
                      .withValues(alpha: 0.25 + 0.45 * (c.weight / maxW)),
                ),
            ]),
            MarkerLayer(markers: [
              for (final s in widget.stations)
                Marker(
                  point: s.position,
                  width: 10,
                  height: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2563EB),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.panelBorderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.textPrimary)),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
