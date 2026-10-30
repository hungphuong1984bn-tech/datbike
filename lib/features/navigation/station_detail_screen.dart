// Chi tiết trạm sạc. Chỉ hiển thị thông tin nguồn dữ liệu CÓ; trường thiếu ghi
// rõ "Chưa có dữ liệu" — không bịa giá, công suất, số cổng hay tình trạng.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/charging/external_nav.dart';
import '../../core/charging/station_search.dart';
import '../../core/charging/station_user_store.dart';
import '../../core/services/charging_station_service.dart';
import '../../core/services/energy_estimator.dart';
import '../../core/services/route_service.dart';
import '../../ui/app_theme.dart';
import 'station_widgets.dart';

enum StationDetailResult { routeInApp }

class StationDetailScreen extends StatefulWidget {
  final ChargingStation station;

  /// Vị trí điện thoại (null nếu chưa có quyền / chưa có GPS).
  final LatLng? me;

  /// % pin trực tiếp từ xe; null nếu không kết nối hoặc dữ liệu cũ.
  final int? livePercent;
  final ConsumptionEstimate? consumption;

  const StationDetailScreen({
    super.key,
    required this.station,
    required this.me,
    required this.livePercent,
    required this.consumption,
  });

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  static const Distance _dist = Distance();

  bool _fav = false;
  bool _routing = false;
  RouteResult? _route;
  String? _routeError;

  ChargingStation get s => widget.station;

  @override
  void initState() {
    super.initState();
    StationUserStore.favorites().then((l) {
      if (mounted) setState(() => _fav = l.any((e) => e.id == s.id));
    });
  }

  double? get _straightKm =>
      widget.me == null ? null : _dist.as(LengthUnit.Kilometer, widget.me!, s.position);

  Future<void> _toggleFav() async {
    final now = await StationUserStore.toggleFavorite(s);
    if (!mounted) return;
    setState(() => _fav = now);
    _snack(now ? 'Đã lưu vào trạm yêu thích' : 'Đã xóa khỏi trạm yêu thích');
  }

  Future<void> _calcRoute() async {
    final me = widget.me;
    if (me == null) return;
    setState(() {
      _routing = true;
      _routeError = null;
    });
    try {
      final r = await RouteService.fetch([me, s.position]);
      if (mounted) setState(() => _route = r);
    } catch (e) {
      if (mounted) setState(() => _routeError = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _external() async {
    final ok = await ExternalNav.navigateTo(s.position, s.name);
    if (!ok && mounted) {
      _snack('Không mở được ứng dụng bản đồ. Hãy cài Google Maps hoặc một ứng dụng bản đồ khác.');
    }
  }

  Future<void> _markUsed() async {
    await StationUserStore.markUsed(s);
    if (mounted) _snack('Đã đánh dấu bạn từng sạc ở trạm này');
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _report() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _ReportSheet(station: s),
    );
    if (saved == true && mounted) {
      _snack('Đã lưu báo cáo trên máy. Báo cáo chưa được gửi đi và không làm thay đổi dữ liệu trạm.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final km = _straightKm;
    final assess = km == null
        ? null
        : ReachEstimator.assess(
            straightKm: km,
            routeKm: _route?.distanceKm,
            percent: widget.livePercent,
            consumption: widget.consumption,
          );
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Chi tiết trạm sạc'),
        actions: [
          IconButton(
            tooltip: _fav ? 'Bỏ yêu thích' : 'Lưu yêu thích',
            icon: Icon(
              _fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _fav ? AppColors.amber : null,
            ),
            onPressed: _toggleFav,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 8, AppSpacing.pageH, 32),
        children: [
          _header(),
          const SizedBox(height: 12),
          if (s.carOnly) _notice('Trạm này chỉ ghi nhận cho ô tô điện — không dành cho xe máy điện.', AppColors.red),
          if (s.vehicle == VehicleSupport.unknown)
            _notice(
              'Nguồn dữ liệu không nói rõ trạm có sạc được xe máy điện hay không. '
              'Hãy xác nhận với trạm trước khi đến.',
              AppColors.amber,
            ),
          _distanceCard(km),
          if (assess != null) _reachCard(assess),
          _infoCard(),
          const SizedBox(height: 12),
          _actions(),
          const SizedBox(height: 12),
          Text(
            'Nguồn: ${s.source}. Dữ liệu do cộng đồng nhập, có thể sai hoặc thiếu và không được '
            'THBIKE xác minh. Báo cáo của bạn chỉ lưu trên máy này, không tự biến thành dữ liệu đã xác minh.',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: child,
      );

  Widget _notice(String text, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.readable(c)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.readable(c), height: 1.35)),
            ),
          ],
        ),
      );

  Widget _header() {
    final vc = StationUi.vehicleColor(s.vehicle);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [vc.withValues(alpha: 0.22), AppColors.panel],
        ),
        border: Border.all(color: vc.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: vc,
                child: Icon(StationUi.vehicleIcon(s.vehicle), color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StationChip(
                icon: Icons.circle,
                label: StationUi.statusLabel(s.status),
                color: StationUi.statusColor(s.status),
              ),
              StationChip(
                icon: StationUi.vehicleIcon(s.vehicle),
                label: StationUi.vehicleLabel(s.vehicle),
                color: vc,
              ),
            ],
          ),
          if (s.status == StationStatus.unverified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Chưa xác minh: nguồn dữ liệu không cho biết trạm có đang hoạt động hay không.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _distanceCard(double? km) {
    final r = _route;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _metric('Khoảng cách', km == null ? 'Chưa có vị trí' : '${StationUi.km(km)} (chim bay)')),
              Expanded(
                child: _metric(
                  'Thời gian di chuyển',
                  r == null ? 'Chưa tính' : '~${(r.durationS / 60).round()} phút',
                ),
              ),
            ],
          ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Tuyến ${r.distanceKm.toStringAsFixed(1)} km. Thời gian tính theo ô tô trên máy chủ OSRM '
                'công cộng, chỉ để tham khảo cho xe máy.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          if (_routeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_routeError!, style: TextStyle(fontSize: 12, color: AppColors.redText)),
            ),
          if (r == null && widget.me != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _routing ? null : _calcRoute,
                icon: _routing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.route_rounded, size: 18),
                label: const Text('Tính thời gian & quãng đường'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );

  Widget _reachCard(ReachAssessment a) {
    final c = switch (a.level) {
      ReachLevel.likely => AppColors.tertiary,
      ReachLevel.tight => AppColors.amber,
      ReachLevel.risky || ReachLevel.unlikely => AppColors.red,
      ReachLevel.unknown => AppColors.textSecondary,
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_charging_full_rounded, color: AppColors.readable(c)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Khả năng tới trạm: ${a.label}',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.readable(c),
                  ),
                ),
              ),
            ],
          ),
          if (a.batteryAtArrival != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Pin khi tới nơi (ước tính): ${a.batteryAtArrival!.clamp(-99, 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          const SizedBox(height: 4),
          Text(a.basis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final rows = <(IconData, String, String?)>[
      (Icons.place_outlined, 'Địa chỉ', s.address),
      (Icons.business_outlined, 'Nhà vận hành', s.operator),
      (Icons.power_outlined, 'Chuẩn đầu sạc', s.sockets),
      (Icons.bolt_rounded, 'Công suất tối đa', s.powerKw == null ? null : '${s.powerKw!.toStringAsFixed(s.powerKw! % 1 == 0 ? 0 : 1)} kW'),
      (Icons.ev_station_outlined, 'Số cổng sạc', s.ports?.toString() ?? s.capacity),
      (Icons.schedule_rounded, 'Giờ mở cửa', s.openingHours),
      (Icons.payments_outlined, 'Giá sạc', s.fee),
      (Icons.phone_outlined, 'Liên hệ', s.phone ?? s.website),
      (
        Icons.update_rounded,
        'Dữ liệu chỉnh sửa lần cuối',
        s.updatedAt == null ? null : '${StationUi.dateTime(s.updatedAt!)} (tại nguồn, không phải mốc xác minh)',
      ),
    ];
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.panelBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rows[i].$1, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: Text(rows[i].$2, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$3 ?? 'Chưa có dữ liệu',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: rows[i].$3 == null ? FontWeight.w400 : FontWeight.w600,
                        color: rows[i].$3 == null ? AppColors.textMuted : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _external,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Dẫn đường bằng ứng dụng bản đồ'),
          ),
          const SizedBox(height: 8),
          if (widget.me != null)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(StationDetailResult.routeInApp),
              icon: const Icon(Icons.alt_route_rounded),
              label: const Text('Xem tuyến trên bản đồ của app'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _markUsed,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Tôi đã sạc ở đây'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _report,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Báo cáo trạm'),
                ),
              ),
            ],
          ),
        ],
      );
}

class _ReportSheet extends StatefulWidget {
  final ChargingStation station;
  const _ReportSheet({required this.station});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportKind _kind = ReportKind.notWorking;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await StationUserStore.addReport(StationReport(
      stationId: widget.station.id,
      stationName: widget.station.name,
      kind: _kind,
      note: _note.text.trim(),
      at: DateTime.now(),
    ));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Báo cáo trạm',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Báo cáo được lưu trên máy bạn, chưa gửi đi đâu và không được coi là dữ liệu đã xác minh.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in ReportKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Ghi chú thêm (không bắt buộc)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('Lưu báo cáo')),
            ),
          ],
        ),
      ),
    );
  }
}
