/// Điểm tọa độ GPS và vận tốc xe máy điện Dat Bike tại từng mốc thời gian của hành trình.
class TripGpsPoint {
  final double lat;
  final double lng;
  final double speedKmh;
  final DateTime timestamp;
  final double? altitude;
  final double? heading;

  const TripGpsPoint({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.timestamp,
    this.altitude,
    this.heading,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'speedKmh': speedKmh,
    'timestamp': timestamp.toIso8601String(),
    if (altitude != null) 'altitude': altitude,
    if (heading != null) 'heading': heading,
  };

  factory TripGpsPoint.fromJson(Map<String, dynamic> json) => TripGpsPoint(
    lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0.0,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    altitude: (json['altitude'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
  );
}
