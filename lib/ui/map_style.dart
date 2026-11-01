// Kiểu bản đồ Google Maps cho Dark Mode (Graphite/Navy, đường Electric Blue).
// Chỉ là cấu hình hiển thị — không đụng dữ liệu, trạm sạc hay luồng GPS.
// Light Mode dùng kiểu mặc định của Google (null).

import 'app_theme.dart';

/// Trả về JSON kiểu bản đồ theo chế độ sáng/tối hiện tại (null = mặc định).
String? currentMapStyle() => AppColors.isDark ? _darkMapStyle : null;

const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d131d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8d9bb2"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#090c12"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1c2431"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#b6c2d4"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0f1f1c"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a2332"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#121a26"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#7f8ea5"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#223048"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1f3a66"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#16294a"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#121a26"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#07182b"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d5a80"}]}
]
''';
