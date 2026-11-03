// Quản trị dữ liệu trạm sạc: cổng PIN, danh sách trạm, duyệt đề xuất, lịch sử
// thay đổi, thêm/sửa trạm (nhập tay hoặc chọn trên bản đồ), xuất CSV/JSON.
//
// Quyền quản trị là CỤC BỘ trên thiết bị (xem station_admin_store.dart) — chưa
// phải xác thực máy chủ. Mọi thay đổi đều ghi người thực hiện + thời gian.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/charging/place_search_service.dart';
import '../../core/charging/station_admin_store.dart';
import '../../core/charging/station_log.dart';
import '../../core/charging/station_proposal_store.dart';
import '../../core/services/charging_station_service.dart';
import '../../ui/app_theme.dart';
import 'station_export.dart';
import 'station_picker_screen.dart';
import 'station_widgets.dart';

// ═════════════ Cổng PIN ═════════════

class StationAdminGate {
  StationAdminGate._();

  /// Mở [builder] nếu đã/đang được mở khóa quản trị; ngược lại hỏi PIN (hoặc tạo PIN lần đầu).
  static Future<void> open(BuildContext context, WidgetBuilder builder) async {
    if (!StationAdminAuth.isAdmin) {
      final ok = await showDialog<bool>(context: context, builder: (_) => const _PinDialog());
      if (ok != true || !context.mounted) return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _name = TextEditingController();
  bool? _hasPin;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final has = await StationAdminAuth.hasPin();
    final name = await StationAdminAuth.savedName();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _name.text = name;
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = _hasPin == true
        ? await StationAdminAuth.unlock(_pin.text)
        : await StationAdminAuth.setupPin(_pin.text, _name.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = _hasPin == false;
    return AlertDialog(
      title: Text(first ? 'Tạo mã PIN quản trị' : 'Quản trị trạm sạc'),
      content: _hasPin == null
          ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first
                        ? 'Chưa có mã PIN quản trị trên máy này. Hãy tạo mã PIN và nhập tên của bạn để ghi vào lịch sử thay đổi.'
                        : 'Nhập mã PIN quản trị để thêm, sửa, xóa và xác minh trạm.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (first) ...[
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Tên quản trị viên', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    autofocus: !first,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: first ? 'Mã PIN mới (4–12 ký tự)' : 'Mã PIN',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Lưu ý: đây là khóa cục bộ trên điện thoại, chưa phải đăng nhập máy chủ.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
        FilledButton(onPressed: (_hasPin == null || _busy) ? null : _submit, child: Text(first ? 'Tạo & mở khóa' : 'Mở khóa')),
      ],
    );
  }
}

// ═════════════ Màn quản trị ═════════════

class StationAdminScreen extends StatefulWidget {
  /// Trạm đang tải trên bản đồ (để hiện/ẩn trạm nguồn ngoài và kiểm tra trùng).
  final List<ChargingStation> stations;
  final LatLng? center;
  const StationAdminScreen({super.key, required this.stations, this.center});

  @override
  State<StationAdminScreen> createState() => _StationAdminScreenState();
}

class _StationAdminScreenState extends State<StationAdminScreen> {
  List<ManagedStation> _managed = const [];
  Map<String, String> _hiddenExt = const {};
  List<StationProposal> _proposals = const [];
  List<StationChangeLog> _history = const [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final m = await StationAdminStore.all();
    final h = await StationAdminStore.hiddenExternal();
    final p = await StationProposalStore.all();
    final hist = await StationAdminStore.history();
    if (!mounted) return;
    setState(() {
      _managed = m;
      _hiddenExt = h;
      _proposals = p;
      _history = hist;
      _loading = false;
    });
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _guard(Future<void> Function() job, {String? ok}) async {
    try {
      await job();
      if (ok != null && mounted) _toast(ok);
    } on StateError catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Lỗi: $e');
    }
    await _reload();
  }

  List<ChargingStation> get _allKnown => [
        ...widget.stations,
        for (final m in _managed) m.toStation(),
      ];

  Future<void> _add({bool pickOnMap = false}) async {
    PickedPlace? pre;
    if (pickOnMap) {
      pre = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
        builder: (_) => StationPickerScreen(initial: widget.center, existing: _allKnown, title: 'Chạm giữ để chọn vị trí trạm'),
      ));
      if (pre == null || !mounted) return;
    }
    await _openEdit(null, pre);
  }

  Future<void> _openEdit(ManagedStation? s, PickedPlace? pre) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => StationEditScreen(editing: s, picked: pre, existing: _allKnown, center: widget.center),
    ));
    if (ok == true) await _reload();
  }

  Future<void> _export(bool csv) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (csv) {
        await shareTextFile('thbike_stations_$stamp.csv', await StationAdminStore.exportCsv(), caption: 'Danh sách trạm sạc THBIKE (CSV)');
      } else {
        await shareTextFile('thbike_stations_$stamp.json', await StationAdminStore.exportJson(), caption: 'Dữ liệu trạm sạc THBIKE (JSON)');
      }
    } catch (e) {
      if (mounted) _toast('Lỗi xuất: $e');
    }
  }

  Future<bool> _confirm(String title, String msg, {String yes = 'Đồng ý'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(yes)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _verify(ManagedStation s) async {
    if (s.verified) {
      await _guard(() async => StationAdminStore.setVerified(s.id, false), ok: 'Đã bỏ xác minh.');
      return;
    }
    final status = await showDialog<StationStatus>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Xác minh trạm — tình trạng thực tế'),
        children: [
          for (final st in const [StationStatus.active, StationStatus.paused, StationStatus.closed])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(st),
              child: Text(StationUi.statusLabel(st)),
            ),
        ],
      ),
    );
    if (status == null) return;
    await _guard(() async => StationAdminStore.setVerified(s.id, true, operating: status), ok: 'Đã xác minh trạm.');
  }

  Future<void> _delete(ManagedStation s) async {
    if (!await _confirm('Xóa trạm?', 'Xóa "${s.name}" (${s.code}). Hành động này được ghi vào lịch sử và không hoàn tác được.', yes: 'Xóa')) return;
    await _guard(() => StationAdminStore.delete(s.id), ok: 'Đã xóa trạm.');
  }

  Future<void> _showHistory(String id, String name) async {
    final h = await StationAdminStore.history(stationId: id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Lịch sử: $name', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
              ),
              Flexible(child: _HistoryList(items: h)),
            ],
          ),
        ),
      ),
    );
  }

  bool _matches(String text) => _q.isEmpty || text.toLowerCase().contains(_q.toLowerCase());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Quản trị trạm sạc'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'csv':
                    _export(true);
                  case 'json':
                    _export(false);
                  case 'lock':
                    StationAdminAuth.lock();
                    Navigator.of(context).pop();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'csv', child: Text('Xuất CSV')),
                PopupMenuItem(value: 'json', child: Text('Xuất JSON')),
                PopupMenuItem(value: 'lock', child: Text('Khóa quản trị')),
              ],
            ),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Trạm'),
            Tab(text: 'Đề xuất (${_proposals.length})'),
            const Tab(text: 'Lịch sử'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final how = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: AppColors.panel,
              builder: (_) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    leading: const Icon(Icons.edit_location_alt_outlined),
                    title: const Text('Nhập thủ công'),
                    subtitle: const Text('Nhập tên, địa chỉ, tọa độ'),
                    onTap: () => Navigator.of(context).pop('manual'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.touch_app_rounded),
                    title: const Text('Chọn trên bản đồ'),
                    subtitle: const Text('Chạm giữ vị trí, tự lấy tọa độ và địa chỉ'),
                    onTap: () => Navigator.of(context).pop('map'),
                  ),
                ]),
              ),
            );
            if (how == 'manual') await _add();
            if (how == 'map') await _add(pickOnMap: true);
          },
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Thêm trạm'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_stationsTab(), _proposalsTab(), _HistoryList(items: _history)]),
      ),
    );
  }

  Widget _stationsTab() {
    final managed = [for (final m in _managed) if (_matches('${m.name} ${m.address} ${m.code}')) m];
    final managedIds = {for (final m in _managed) m.id};
    final external = [
      for (final s in widget.stations)
        if (!managedIds.contains(s.id) && _matches('${s.name} ${s.address ?? ''}')) s,
    ];
    final hidden = [for (final e in _hiddenExt.entries) if (_matches(e.value)) e];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Tìm theo tên, địa chỉ, mã trạm…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _section('Trạm do quản trị viên quản lý (${managed.length})'),
        if (managed.isEmpty)
          _empty('Chưa có trạm nào. Bấm "Thêm trạm" để nhập thủ công hoặc chọn trên bản đồ.'),
        for (final m in managed) _managedTile(m),
        const SizedBox(height: 16),
        _section('Trạm từ nguồn khác đang tải (${external.length})'),
        if (external.isEmpty) _empty('Không có trạm nguồn ngoài trong vùng bản đồ đang tải.'),
        for (final s in external.take(60))
          ListTile(
            dense: true,
            leading: Icon(Icons.ev_station_outlined, color: AppColors.textSecondary),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${s.source} · ${StationUi.statusLabel(s.status)}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: () => _guard(() => StationAdminStore.setHidden(s.id, s.name, true), ok: 'Đã ẩn khỏi bản đồ.'),
              child: const Text('Ẩn'),
            ),
          ),
        if (external.length > 60)
          Padding(padding: const EdgeInsets.all(8), child: Text('… và ${external.length - 60} trạm khác (dùng ô tìm kiếm để lọc).', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section('Đang bị ẩn (${hidden.length})'),
          for (final e in hidden)
            ListTile(
              dense: true,
              leading: Icon(Icons.visibility_off_outlined, color: AppColors.textSecondary),
              title: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: () => _guard(() => StationAdminStore.setHidden(e.key, e.value, false), ok: 'Đã hiện lại.'),
                child: const Text('Hiện lại'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _managedTile(ManagedStation m) {
    final st = m.effectiveStatus;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openEdit(m, null),
        leading: CircleAvatar(
          backgroundColor: m.hidden ? AppColors.textSecondary : StationUi.statusColor(st),
          child: Icon(m.hidden ? Icons.visibility_off_rounded : (m.verified ? Icons.verified_rounded : Icons.help_outline_rounded), color: Colors.white, size: 20),
        ),
        title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${m.code} · ${m.verified ? StationUi.statusLabel(st) : 'Chưa xác minh'}${m.updating ? ' · đang cập nhật' : ''}${m.hidden ? ' · đang ẩn' : ''} · v${m.rev}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _openEdit(m, null);
              case 'verify':
                _verify(m);
              case 'hide':
                _guard(() => StationAdminStore.setHidden(m.id, m.name, !m.hidden), ok: m.hidden ? 'Đã hiện trạm.' : 'Đã ẩn trạm.');
              case 'history':
                _showHistory(m.id, m.name);
              case 'delete':
                _delete(m);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Sửa')),
            PopupMenuItem(value: 'verify', child: Text(m.verified ? 'Bỏ xác minh' : 'Xác minh')),
            PopupMenuItem(value: 'hide', child: Text(m.hidden ? 'Hiện trên bản đồ' : 'Ẩn khỏi bản đồ')),
            const PopupMenuItem(value: 'history', child: Text('Lịch sử thay đổi')),
            const PopupMenuItem(value: 'delete', child: Text('Xóa')),
          ],
        ),
      ),
    );
  }

  Widget _proposalsTab() {
    if (_proposals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Chưa có đề xuất nào đang chờ duyệt.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Đề xuất lưu trên máy này. "Duyệt" đưa vào danh sách quản lý ở trạng thái CHƯA XÁC MINH — hãy đối chiếu thực tế rồi bấm Xác minh.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final p in _proposals)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(p.address, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  Text('${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)} · ${StationUi.dateTime(p.createdAt)}',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (p.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ghi chú: ${p.note}', style: const TextStyle(fontSize: 12.5))),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          if (await _confirm('Từ chối đề xuất?', 'Xóa đề xuất "${p.name}" khỏi hàng chờ.', yes: 'Từ chối')) {
                            await _guard(() => StationAdminStore.rejectProposal(p), ok: 'Đã từ chối đề xuất.');
                          }
                        },
                        child: const Text('Từ chối'),
                      ),
                      FilledButton(
                        onPressed: () => _guard(() async => StationAdminStore.approveProposal(p), ok: 'Đã duyệt — trạm ở trạng thái chưa xác minh.'),
                        child: const Text('Duyệt'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary)),
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      );
}

class _HistoryList extends StatelessWidget {
  final List<StationChangeLog> items;
  const _HistoryList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Chưa có thay đổi nào được ghi.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final h = items[i];
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('${h.action.label}: ${h.stationName}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${h.actor} · ${StationUi.dateTime(h.at)}', style: const TextStyle(fontSize: 12)),
          children: [
            if (h.changes.isEmpty)
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(h.source, style: const TextStyle(fontSize: 12))))
            else
              for (final e in h.changes.entries)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${e.key}: ${e.value[0] ?? '—'}  →  ${e.value[1] ?? '—'}', style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Nguồn: ${h.source}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)))),
          ],
        );
      },
    );
  }
}

// ═════════════ Biểu mẫu thêm / sửa trạm ═════════════

class StationEditScreen extends StatefulWidget {
  final ManagedStation? editing;
  final PickedPlace? picked;
  final List<ChargingStation> existing;
  final LatLng? center;
  const StationEditScreen({super.key, this.editing, this.picked, required this.existing, this.center});

  @override
  State<StationEditScreen> createState() => _StationEditScreenState();
}

class _StationEditScreenState extends State<StationEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _province;
  late final TextEditingController _district;
  late final TextEditingController _coords;
  late final TextEditingController _ports;
  late final TextEditingController _power;
  late final TextEditingController _note;
  late StationCategory _category;
  late String _type;
  late VehicleSupport _vehicle;
  late bool _updating;
  String? _error;
  bool _busy = false;

  ManagedStation? get _e => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _e;
    final p = widget.picked;
    _name = TextEditingController(text: e?.name ?? '');
    _address = TextEditingController(text: e?.address ?? p?.address ?? '');
    _province = TextEditingController(text: e?.province ?? p?.province ?? '');
    _district = TextEditingController(text: e?.district ?? p?.district ?? '');
    final ll = e != null ? LatLng(e.lat, e.lng) : p?.position;
    _coords = TextEditingController(text: ll == null ? '' : '${ll.latitude.toStringAsFixed(6)}, ${ll.longitude.toStringAsFixed(6)}');
    _ports = TextEditingController(text: e?.ports?.toString() ?? '');
    _power = TextEditingController(text: e?.powerKw == null ? '' : '${e!.powerKw}');
    _note = TextEditingController(text: e?.note ?? '');
    _category = (e?.category == StationCategory.partner) ? StationCategory.partner : StationCategory.community;
    _type = e?.stationType ?? kStationTypes.first;
    _vehicle = e?.vehicle ?? VehicleSupport.unknown;
    _updating = e?.updating ?? false;
    if (e == null && p != null && (p.address ?? '').isEmpty) _autofill(p.position);
  }

  /// Chạm giữ trên bản đồ → điền địa chỉ/tỉnh/huyện nếu có mạng; admin vẫn sửa được trước khi lưu.
  Future<void> _autofill(LatLng pos) async {
    final r = await PlaceReverseService.lookup(pos.latitude, pos.longitude);
    if (!mounted || r == null) return;
    setState(() {
      if (_address.text.trim().isEmpty) _address.text = r.address;
      if (_province.text.trim().isEmpty) _province.text = r.province;
      if (_district.text.trim().isEmpty) _district.text = r.district;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _province, _district, _coords, _ports, _power, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final cur = StationProposalStore.parseLatLng(_coords.text);
    final r = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
      builder: (_) => StationPickerScreen(
        initial: cur == null ? widget.center : LatLng(cur.lat, cur.lng),
        existing: widget.existing,
        title: 'Chạm giữ để chọn vị trí trạm',
      ),
    ));
    if (r == null || !mounted) return;
    setState(() {
      _coords.text = '${r.position.latitude.toStringAsFixed(6)}, ${r.position.longitude.toStringAsFixed(6)}';
      if (r.address != null && _address.text.trim().isEmpty) _address.text = r.address!;
      if (r.province.isNotEmpty && _province.text.trim().isEmpty) _province.text = r.province;
      if (r.district.isNotEmpty && _district.text.trim().isEmpty) _district.text = r.district;
    });
  }

  Future<void> _save() async {
    final ll = StationProposalStore.parseLatLng(_coords.text);
    final portsTxt = _ports.text.trim();
    final powerTxt = _power.text.trim().replaceAll(',', '.');
    final ports = portsTxt.isEmpty ? null : int.tryParse(portsTxt);
    final power = powerTxt.isEmpty ? null : double.tryParse(powerTxt);
    String? err;
    if (portsTxt.isNotEmpty && ports == null) err = 'Số cổng sạc phải là số nguyên.';
    if (err == null && powerTxt.isNotEmpty && power == null) err = 'Công suất phải là số (kW).';
    err ??= StationAdminStore.validate(
      name: _name.text,
      address: _address.text,
      lat: ll?.lat,
      lng: ll?.lng,
      ports: ports,
      powerKw: power,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final lat = ll!.lat, lng = ll.lng;

    final near = StationAdminStore.nearest(lat, lng, widget.existing, excludeId: _e?.id);
    if (near != null && near.meters <= StationAdminStore.duplicateMeters) {
      setState(() => _error = 'Vị trí này trùng với "${near.station.name}" (cách ${near.meters.round()} m) — không thêm lại. Hãy sửa trạm đó hoặc chọn vị trí khác.');
      return;
    }
    if (near != null && near.meters <= StationAdminStore.nearMeters) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vị trí rất gần một trạm khác'),
          content: Text('Gần "${near.station.name}" chỉ ${near.meters.round()} m. Đây có phải là một trạm riêng biệt không?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Kiểm tra lại')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Vẫn lưu')),
          ],
        ),
      );
      if (go != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final e = _e;
      final code = e?.code ?? await StationAdminStore.nextCode();
      final base = ManagedStation(
        id: e?.id ?? 'thb/${code.toLowerCase()}',
        code: code,
        name: _name.text.trim(),
        address: _address.text.trim(),
        province: _province.text.trim(),
        district: _district.text.trim(),
        lat: lat,
        lng: lng,
        category: _category,
        stationType: _type,
        vehicle: _vehicle,
        ports: ports,
        powerKw: power,
        note: _note.text.trim(),
        photoPath: e?.photoPath,
        verified: e?.verified ?? false,
        verifiedBy: e?.verifiedBy,
        verifiedAt: e?.verifiedAt,
        operating: e?.operating ?? StationStatus.active,
        updating: _updating,
        hidden: e?.hidden ?? false,
        createdBy: e?.createdBy ?? StationAdminAuth.actor,
        createdAt: e?.createdAt ?? now,
        updatedAt: now,
        rev: e?.rev ?? 1,
      );
      await StationAdminStore.save(base, now: now);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StateError catch (er) {
      if (mounted) setState(() => _error = er.message);
    } catch (er) {
      if (mounted) setState(() => _error = 'Không lưu được: $er');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String l, {String? hint}) => InputDecoration(labelText: l, hintText: hint, border: const OutlineInputBorder());
    final e = _e;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(e == null ? 'Thêm trạm sạc' : 'Sửa trạm sạc')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            e == null ? 'Mã trạm: tự động tạo khi lưu' : 'Mã trạm: ${e.code} · phiên bản ${e.rev}',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          Text(
            e == null
                ? 'Người tạo: ${StationAdminAuth.actor} (ghi nhận khi lưu)'
                : 'Tạo bởi ${e.createdBy} lúc ${StationUi.dateTime(e.createdAt)}',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: d('Tên trạm sạc *')),
          const SizedBox(height: 12),
          TextField(controller: _address, maxLines: 2, decoration: d('Địa chỉ *')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _province, decoration: d('Tỉnh/Thành phố'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _district, decoration: d('Quận/Huyện'))),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _coords,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: d('Tọa độ (vĩ độ, kinh độ) *', hint: '21.04831, 105.881862'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Chọn / chỉnh trên bản đồ'),
            ),
          ),
          const SizedBox(height: 4),
          Text('Loại điểm sạc', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Wrap(spacing: 8, children: [
            for (final c in const [StationCategory.partner, StationCategory.community])
              ChoiceChip(
                label: Text(StationUi.categoryLabel(c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ]),
          const SizedBox(height: 10),
          Text('Loại trạm', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Wrap(spacing: 8, children: [
            for (final t in kStationTypes) ChoiceChip(label: Text(t), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
          ]),
          const SizedBox(height: 10),
          Text('Phương tiện hỗ trợ', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Wrap(spacing: 8, children: [
            for (final v in VehicleSupport.values)
              ChoiceChip(label: Text(StationUi.vehicleLabel(v)), selected: _vehicle == v, onSelected: (_) => setState(() => _vehicle = v)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _ports, keyboardType: TextInputType.number, decoration: d('Số cổng sạc'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _power, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: d('Công suất (kW)'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 3, decoration: d('Ghi chú')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dữ liệu đang được cập nhật'),
            subtitle: const Text('Marker hiện màu xanh dương cho đến khi xác minh lại'),
            value: _updating,
            onChanged: (v) => setState(() => _updating = v),
          ),
          Text(
            e?.verified == true
                ? 'Trạng thái: đã xác minh bởi ${e!.verifiedBy ?? '—'}${e.verifiedAt == null ? '' : ' lúc ${StationUi.dateTime(e.verifiedAt!)}'}. Sửa thông tin KHÔNG tự bỏ xác minh — hãy bỏ xác minh thủ công nếu dữ liệu thay đổi thực tế.'
                : 'Trạm mới luôn ở trạng thái CHƯA XÁC MINH cho đến khi bạn bấm Xác minh ở danh sách.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
          ),
          Text(
            'Ảnh trạm: chưa hỗ trợ chọn ảnh trong app (cần thêm gói chọn ảnh).',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(e == null ? 'Lưu trạm mới' : 'Lưu thay đổi')),
        ],
      ),
    );
  }
}
