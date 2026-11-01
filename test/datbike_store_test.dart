import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/charging/datbike_store.dart';

void main() {
  late List<DatBikeStore> all;

  setUpAll(() {
    all = DatBikeStoreRepository.parse(File(DatBikeStoreRepository.asset).readAsStringSync());
  });

  test('Dữ liệu đóng gói đọc đủ 70 cửa hàng, id duy nhất, có địa chỉ và giờ', () {
    expect(all.length, 70);
    expect(all.map((s) => s.id).toSet().length, all.length);
    for (final s in all) {
      expect(s.address, isNotEmpty);
      expect(s.hours, isNotEmpty);
      expect(s.province, isNotEmpty);
      expect(s.phones, isNotEmpty);
    }
  });

  test('Không có tọa độ / không khẳng định có trạm sạc trong dữ liệu cửa hàng', () {
    final raw = File(DatBikeStoreRepository.asset).readAsStringSync();
    expect(raw.contains('"lat"'), isFalse);
    expect(raw.contains('"lng"'), isFalse);
    expect(raw.contains('chargingConfirmed'), isFalse);
  });

  test('Tỉnh/thành sắp theo số cửa hàng giảm dần', () {
    final p = DatBikeStoreRepository.provinces(all);
    expect(p.first, 'TP. Hồ Chí Minh');
    expect(p[1], 'Hà Nội');
    expect(p.toSet().length, p.length);
  });

  test('Lọc theo tỉnh', () {
    final hn = DatBikeStoreRepository.filter(all, province: 'Hà Nội');
    expect(hn, isNotEmpty);
    expect(hn.every((s) => s.province == 'Hà Nội'), isTrue);
  });

  test('Tìm kiếm không phân biệt dấu/hoa thường, theo tên, địa chỉ và hotline', () {
    expect(DatBikeStoreRepository.filter(all, query: 'lang ha').map((s) => s.name), contains('STORE DAT BIKE LÁNG HẠ'));
    expect(DatBikeStoreRepository.filter(all, query: 'ĐÀ NẴNG'), isNotEmpty);
    expect(DatBikeStoreRepository.filter(all, query: '0795 566 209').length, 1);
    expect(DatBikeStoreRepository.filter(all, query: 'khong-ton-tai-xyz'), isEmpty);
  });

  test('Cửa hàng chỉ bán hàng được đánh dấu', () {
    final only = all.where((s) => s.salesOnly).map((s) => s.id).toSet();
    expect(only, contains('store/store-dat-bike-xuan-cau-ba-trieu-chi-ban-xe'));
    expect(only.length, 4);
  });

  test('Liên kết Google Maps theo tên + địa chỉ', () {
    final u = all.first.mapsSearchUri;
    expect(u.host, 'www.google.com');
    expect(u.path, '/maps/search/');
    expect(u.queryParameters['api'], '1');
    expect(u.queryParameters['query'], contains('68 Đ. Trần Khát Chân'));
  });

  test('parse bỏ qua dữ liệu hỏng', () {
    expect(DatBikeStoreRepository.parse('{"stores": 5}'), isEmpty);
    expect(DatBikeStoreRepository.parse('{"stores":[1,{"id":"x","address":""}]}'), isEmpty);
  });
}
