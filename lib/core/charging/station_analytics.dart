// Tổng hợp số liệu từ log hoạt động thật — hàm thuần, không I/O.
//
// KHÔNG tạo dữ liệu giả: không có log → mọi danh sách rỗng, Heatmap rỗng.
// Heatmap/"khu vực chưa có trạm" chỉ dựa trên sự kiện có tọa độ khu vực mà người
// dùng đã đồng ý ghi (đã làm tròn ~1 km).

import 'dart:math' as math;

import '../services/charging_station_service.dart';
import 'station_log.dart';

enum AnalyticsPeriod {
  day('Ngày', Duration(hours: 24), 24, Duration(hours: 1)),
  week('Tuần', Duration(days: 7), 7, Duration(days: 1)),
  month('Tháng', Duration(days: 30), 30, Duration(days: 1));

  final String label;
  final Duration window;
  final int buckets;
  final Duration bucketSize;
  const AnalyticsPeriod(this.label, this.window, this.buckets, this.bucketSize);
}

/// Trọng số nhu cầu của từng loại sự kiện trên Heatmap.
/// Khu vực tìm mà KHÔNG có trạm và lượt bấm Dẫn đường là tín hiệu mạnh nhất.
int demandWeight(StationEvent e) => switch (e) {
      StationEvent.emptyResult => 3,
      StationEvent.navigate => 3,
      StationEvent.detail => 2,
      StationEvent.search => 1,
      StationEvent.view => 1,
      StationEvent.filter => 0,
      _ => 0,
    };

class HeatCell {
  final double lat;
  final double lng;
  final int weight;
  const HeatCell(this.lat, this.lng, this.weight);
}

class RankedStation {
  final String stationId;
  final String name;
  final int views;
  final int details;
  final int navigates;
  const RankedStation(this.stationId, this.name, this.views, this.details, this.navigates);
  int get score => views + details * 2 + navigates * 3;
}

class SearchTerm {
  final String term;
  final int count;
  const SearchTerm(this.term, this.count);
}

class StationCounts {
  final int total;
  final int verified;
  final int unverified;
  final int paused;
  final int pendingProposals;
  const StationCounts(this.total, this.verified, this.unverified, this.paused, this.pendingProposals);

  factory StationCounts.from(Iterable<ChargingStation> stations, {int pendingProposals = 0}) {
    var v = 0, u = 0, p = 0, n = 0;
    for (final s in stations) {
      n++;
      switch (s.status) {
        case StationStatus.active:
          v++;
        case StationStatus.unverified:
          u++;
        case StationStatus.paused:
        case StationStatus.closed:
          p++;
      }
    }
    return StationCounts(n, v, u, p, pendingProposals);
  }
}

class StationAnalytics {
  final AnalyticsPeriod period;
  final int totalEvents;
  final int uniqueUsers;
  final int views;
  final int navigates;
  final int navigateFailures;
  final int errors;
  final List<RankedStation> top;
  final List<SearchTerm> searches;
  final List<HeatCell> heat;
  final List<HeatCell> uncovered;

  /// Số sự kiện theo từng khoảng (cũ → mới); [bucketStart] cùng độ dài.
  final List<int> series;
  final List<DateTime> bucketStart;

  const StationAnalytics({
    required this.period,
    required this.totalEvents,
    required this.uniqueUsers,
    required this.views,
    required this.navigates,
    required this.navigateFailures,
    required this.errors,
    required this.top,
    required this.searches,
    required this.heat,
    required this.uncovered,
    required this.series,
    required this.bucketStart,
  });

  bool get isEmpty => totalEvents == 0;

  /// Tính từ log. [stations] dùng để lấy tên trạm và xác định khu vực chưa có trạm.
  static StationAnalytics compute(
    List<StationActivityLog> logs,
    List<ChargingStation> stations, {
    required DateTime now,
    AnalyticsPeriod period = AnalyticsPeriod.week,
    double coverKm = 3,
    int topN = 10,
  }) {
    final from = now.subtract(period.window);
    final inWin = [for (final l in logs) if (!l.at.isBefore(from) && !l.at.isAfter(now)) l];

    final names = {for (final s in stations) s.id: s.name};
    final views = <String, int>{}, details = <String, int>{}, navs = <String, int>{};
    final terms = <String, int>{};
    final heat = <String, int>{};
    final users = <String>{};
    var nView = 0, nNav = 0, nNavFail = 0, nErr = 0;

    for (final l in inWin) {
      if (l.anonId.isNotEmpty) users.add(l.anonId);
      final sid = l.stationId;
      switch (l.event) {
        case StationEvent.view:
          nView++;
          if (sid != null) views[sid] = (views[sid] ?? 0) + 1;
        case StationEvent.detail:
          if (sid != null) details[sid] = (details[sid] ?? 0) + 1;
        case StationEvent.navigate:
          nNav++;
          if (sid != null) navs[sid] = (navs[sid] ?? 0) + 1;
        case StationEvent.navigateResult:
          if (l.detail == 'fail') nNavFail++;
        case StationEvent.search:
          final t = normalizeTerm(l.query);
          if (t.isNotEmpty) terms[t] = (terms[t] ?? 0) + 1;
        case StationEvent.mapError:
        case StationEvent.gpsError:
          nErr++;
        case StationEvent.filter:
        case StationEvent.emptyResult:
        case StationEvent.propose:
          break;
      }
      final w = demandWeight(l.event);
      if (w > 0 && l.areaLat != null && l.areaLng != null) {
        final k = '${l.areaLat}|${l.areaLng}';
        heat[k] = (heat[k] ?? 0) + w;
      }
    }

    final ids = {...views.keys, ...details.keys, ...navs.keys};
    final top = [
      for (final id in ids)
        RankedStation(id, names[id] ?? id, views[id] ?? 0, details[id] ?? 0, navs[id] ?? 0),
    ]..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    final searches = [for (final e in terms.entries) SearchTerm(e.key, e.value)]
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.term.compareTo(b.term);
      });

    final cells = <HeatCell>[];
    for (final e in heat.entries) {
      final parts = e.key.split('|');
      final la = double.tryParse(parts[0]), ln = double.tryParse(parts[1]);
      if (la != null && ln != null) cells.add(HeatCell(la, ln, e.value));
    }
    cells.sort((a, b) => b.weight.compareTo(a.weight));

    final uncovered = [
      for (final c in cells)
        if (nearestStationKm(c.lat, c.lng, stations) > coverKm) c,
    ];

    final series = List<int>.filled(period.buckets, 0);
    final starts = [
      for (var i = 0; i < period.buckets; i++)
        from.add(period.bucketSize * i),
    ];
    for (final l in inWin) {
      var i = l.at.difference(from).inMicroseconds ~/ period.bucketSize.inMicroseconds;
      if (i >= period.buckets) i = period.buckets - 1;
      if (i < 0) i = 0;
      series[i]++;
    }

    return StationAnalytics(
      period: period,
      totalEvents: inWin.length,
      uniqueUsers: users.length,
      views: nView,
      navigates: nNav,
      navigateFailures: nNavFail,
      errors: nErr,
      top: top.take(topN).toList(),
      searches: searches.take(topN).toList(),
      heat: cells,
      uncovered: uncovered.take(topN).toList(),
      series: series,
      bucketStart: starts,
    );
  }

  static String normalizeTerm(String? q) =>
      (q ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Khoảng cách (km) tới trạm gần nhất; vô cực khi chưa có trạm nào.
  static double nearestStationKm(double lat, double lng, List<ChargingStation> stations) {
    var best = double.infinity;
    for (final s in stations) {
      final d = haversineKm(lat, lng, s.lat, s.lng);
      if (d < best) best = d;
    }
    return best;
  }

  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0088;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }
}
