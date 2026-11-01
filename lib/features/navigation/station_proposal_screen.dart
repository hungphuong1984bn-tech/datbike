// Đề xuất điểm sạc mới (cộng đồng). Điểm lưu trên máy, trạng thái "Chờ xác minh",
// không bao giờ mang nhãn Dat Bike chính thức. Tọa độ do người dùng nhập hoặc lấy từ GPS thật.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/charging/station_proposal_store.dart';
import '../../core/services/charging_station_service.dart';
import '../../ui/app_theme.dart';

class StationProposalScreen extends StatefulWidget {
  /// Trạm đang có, dùng để chống trùng lặp.
  final List<ChargingStation> existing;
  const StationProposalScreen({super.key, required this.existing});

  @override
  State<StationProposalScreen> createState() => _StationProposalScreenState();
}

class _StationProposalScreenState extends State<StationProposalScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _coords = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _coords, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _error = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Hãy bật dịch vụ vị trí (GPS) trên điện thoại.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = 'Chưa được cấp quyền vị trí. Bạn vẫn có thể nhập tọa độ thủ công.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      setState(() => _coords.text = '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}');
    } catch (_) {
      setState(() => _error = 'Không lấy được vị trí hiện tại. Hãy thử lại hoặc nhập tọa độ thủ công.');
    }
  }

  Future<void> _submit() async {
    final ll = StationProposalStore.parseLatLng(_coords.text);
    final v = StationProposalStore.validate(name: _name.text, address: _address.text, lat: ll?.lat, lng: ll?.lng);
    if (!v.ok) {
      setState(() => _error = v.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await StationProposalStore.submit(
      name: _name.text,
      address: _address.text,
      lat: ll!.lat,
      lng: ll.lng,
      phone: _phone.text,
      note: _note.text,
      existing: widget.existing,
    );
    if (!mounted) return;
    if (r.saved == null) {
      setState(() {
        _busy = false;
        _error = 'Điểm này trùng với "${r.duplicateOf!.name}" đã có trong dữ liệu — không thêm lại.';
      });
      return;
    }
    Navigator.of(context).pop(r.saved);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Đề xuất điểm sạc mới')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Điểm bạn gửi sẽ ở trạng thái "Chờ xác minh" và thuộc nhóm điểm sạc cộng đồng. '
            'Điểm chỉ được coi là Dat Bike chính thức khi có nguồn xác nhận.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: d('Tên điểm sạc *')),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: d('Địa chỉ *')),
          const SizedBox(height: 12),
          TextField(
            controller: _coords,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: d('Tọa độ (vĩ độ, kinh độ) *', hint: '21.04831, 105.881862'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _useGps,
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Dùng vị trí hiện tại (GPS)'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: d('Số điện thoại (nếu có)')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 3, decoration: d('Ghi chú (giờ mở cửa, loại đầu sạc…)')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Gửi đề xuất (chờ xác minh)')),
        ],
      ),
    );
  }
}
