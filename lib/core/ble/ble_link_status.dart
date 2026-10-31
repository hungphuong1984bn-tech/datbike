// Trạng thái liên kết BLE DẪN XUẤT — module THUẦN Dart (không import Flutter).
//
// Mục tiêu (Giai đoạn 1 / 2.11.0):
//   • Tách rõ "đã kết nối BLE" với "đang đọc được dữ liệu xe". Kết nối GATT
//     thành công KHÔNG đồng nghĩa với việc có dữ liệu.
//   • Không dùng dữ liệu của lần kết nối trước (cache) để giả lập dữ liệu
//     thời gian thực: mốc dữ liệu có trước thời điểm kết nối hiện tại bị bỏ qua.
//
// Đây là hàm thuần suy ra từ các cờ do BleController/hệ điều hành cung cấp; nó
// KHÔNG thay thế BlePhase và không điều khiển luồng kết nối.

import 'connect_diagnostics.dart' show ConnectStage;

enum BleLinkStatus {
  /// Chưa làm gì (chưa quét/kết nối).
  idle,

  /// Bluetooth của điện thoại đang tắt.
  adapterOff,

  /// Thiếu quyền Bluetooth/Vị trí cần thiết.
  permissionMissing,

  /// Đang quét tìm thiết bị.
  scanning,

  /// Đã thấy thiết bị khi quét, chưa mở kết nối.
  deviceFound,

  /// Đang mở kết nối GATT.
  connecting,

  /// Đã mở GATT, đang khám phá service.
  discoveringServices,

  /// Đang xác thực / bắt tay phiên.
  authenticating,

  /// Đã kết nối (và xác thực nếu cần), CHƯA nhận khung dữ liệu nào của kết nối này.
  connected,

  /// Đang nhận dữ liệu mới (trong cửa sổ "mới").
  receivingData,

  /// Đã kết nối nhưng quá thời gian chờ mà không có khung dữ liệu nào.
  connectedNoData,

  /// Đã từng có dữ liệu trong kết nối này nhưng đã quá cửa sổ "mới".
  dataStale,

  /// Mất kết nối (hoặc đã ngắt).
  disconnected,

  /// Đang thử kết nối lại.
  reconnecting,
}

/// Mức nhấn mạnh để UI chọn màu (độc lập với UI để module vẫn thuần Dart).
enum LinkSeverity { neutral, ok, info, warning, error }

extension BleLinkStatusX on BleLinkStatus {
  String get label {
    switch (this) {
      case BleLinkStatus.idle:
        return 'Chưa kết nối';
      case BleLinkStatus.adapterOff:
        return 'Bluetooth đang tắt';
      case BleLinkStatus.permissionMissing:
        return 'Chưa cấp quyền';
      case BleLinkStatus.scanning:
        return 'Đang quét thiết bị';
      case BleLinkStatus.deviceFound:
        return 'Đã tìm thấy thiết bị';
      case BleLinkStatus.connecting:
        return 'Đang kết nối';
      case BleLinkStatus.discoveringServices:
        return 'Đang khám phá dịch vụ';
      case BleLinkStatus.authenticating:
        return 'Đang xác thực';
      case BleLinkStatus.connected:
        return 'Đã kết nối';
      case BleLinkStatus.receivingData:
        return 'Đang nhận dữ liệu';
      case BleLinkStatus.connectedNoData:
        return 'Đã kết nối nhưng không có dữ liệu';
      case BleLinkStatus.dataStale:
        return 'Dữ liệu đã cũ';
      case BleLinkStatus.disconnected:
        return 'Mất kết nối';
      case BleLinkStatus.reconnecting:
        return 'Đang thử kết nối lại';
    }
  }

  /// Giải thích ngắn cho người dùng, nói rõ điều gì ĐÃ và CHƯA xảy ra.
  String get hint {
    switch (this) {
      case BleLinkStatus.idle:
        return 'Chưa có kết nối nào được mở.';
      case BleLinkStatus.adapterOff:
        return 'Hãy bật Bluetooth trên điện thoại.';
      case BleLinkStatus.permissionMissing:
        return 'Cấp quyền "Thiết bị ở gần" (Android 12+) hoặc "Vị trí" (Android 11 trở xuống).';
      case BleLinkStatus.scanning:
        return 'Đang tìm xe ở gần. Bật khóa điện và lại gần xe.';
      case BleLinkStatus.deviceFound:
        return 'Đã thấy thiết bị, chưa mở kết nối.';
      case BleLinkStatus.connecting:
        return 'Đang mở kết nối tới xe.';
      case BleLinkStatus.discoveringServices:
        return 'Đã mở kết nối, đang đọc danh sách dịch vụ của xe.';
      case BleLinkStatus.authenticating:
        return 'Đang bắt tay xác thực với xe. Chưa có dữ liệu xe.';
      case BleLinkStatus.connected:
        return 'Đã kết nối, đang chờ khung dữ liệu đầu tiên từ xe.';
      case BleLinkStatus.receivingData:
        return 'Nhận được dữ liệu mới từ xe.';
      case BleLinkStatus.connectedNoData:
        return 'Kết nối BLE còn, nhưng xe chưa gửi dữ liệu đọc được. '
            'Số liệu hiển thị (nếu có) KHÔNG phải dữ liệu trực tiếp.';
      case BleLinkStatus.dataStale:
        return 'Đã lâu không nhận được khung mới. Số liệu đang hiển thị là số liệu cũ.';
      case BleLinkStatus.disconnected:
        return 'Không còn kết nối với xe. Số liệu hiển thị (nếu có) là số liệu lần cuối.';
      case BleLinkStatus.reconnecting:
        return 'Đang tự kết nối lại với xe.';
    }
  }

  LinkSeverity get severity {
    switch (this) {
      case BleLinkStatus.idle:
        return LinkSeverity.neutral;
      case BleLinkStatus.adapterOff:
      case BleLinkStatus.permissionMissing:
      case BleLinkStatus.disconnected:
        return LinkSeverity.error;
      case BleLinkStatus.connectedNoData:
      case BleLinkStatus.dataStale:
      case BleLinkStatus.reconnecting:
        return LinkSeverity.warning;
      case BleLinkStatus.scanning:
      case BleLinkStatus.deviceFound:
      case BleLinkStatus.connecting:
      case BleLinkStatus.discoveringServices:
      case BleLinkStatus.authenticating:
      case BleLinkStatus.connected:
        return LinkSeverity.info;
      case BleLinkStatus.receivingData:
        return LinkSeverity.ok;
    }
  }

  /// Chỉ true khi đang nhận dữ liệu mới. Mọi trạng thái khác KHÔNG được coi là
  /// dữ liệu thời gian thực.
  bool get hasLiveData => this == BleLinkStatus.receivingData;

  /// Liên kết GATT đang mở (dù có dữ liệu hay chưa).
  bool get isLinkUp {
    switch (this) {
      case BleLinkStatus.discoveringServices:
      case BleLinkStatus.authenticating:
      case BleLinkStatus.connected:
      case BleLinkStatus.receivingData:
      case BleLinkStatus.connectedNoData:
      case BleLinkStatus.dataStale:
        return true;
      default:
        return false;
    }
  }
}

/// Đầu vào để suy ra trạng thái. Tất cả là dữ kiện quan sát được, không suy đoán.
class BleLinkInputs {
  const BleLinkInputs({
    required this.now,
    this.adapterOn,
    this.permissionGranted,
    this.scanning = false,
    this.deviceFound = false,
    this.gattConnecting = false,
    this.gattConnected = false,
    this.servicesDiscovered = false,
    this.authInProgress = false,
    this.authorized = false,
    this.reconnecting = false,
    this.everConnected = false,
    this.connectedAt,
    this.lastDataAt,
    this.freshWindow = const Duration(seconds: 4),
    this.noDataGrace = const Duration(seconds: 8),
  });

  final DateTime now;

  /// null = chưa biết (không coi là tắt).
  final bool? adapterOn;

  /// null = chưa biết (không coi là thiếu quyền).
  final bool? permissionGranted;

  final bool scanning;
  final bool deviceFound;
  final bool gattConnecting;
  final bool gattConnected;
  final bool servicesDiscovered;
  final bool authInProgress;
  final bool authorized;
  final bool reconnecting;

  /// Đã từng mở được kết nối trong phiên chạy này (để phân biệt "mất kết nối" với "chưa làm gì").
  final bool everConnected;

  /// Thời điểm mở kết nối hiện tại. Dữ liệu có mốc trước đó bị coi là của lần
  /// kết nối cũ và bị bỏ qua.
  final DateTime? connectedAt;

  /// Thời điểm nhận khung dữ liệu hợp lệ gần nhất.
  final DateTime? lastDataAt;

  /// Dữ liệu trong khoảng này kể từ lần nhận cuối là "mới".
  final Duration freshWindow;

  /// Sau khi kết nối xong mà quá khoảng này chưa có dữ liệu → "không có dữ liệu".
  final Duration noDataGrace;
}

/// Suy ra trạng thái liên kết. Hàm thuần, thứ tự ưu tiên cố định:
/// bộ điều hợp tắt → thiếu quyền → kết nối lại → liên kết đang mở → đang kết nối
/// → quét/tìm thấy → đã ngắt / chưa làm gì.
BleLinkStatus deriveBleLinkStatus(BleLinkInputs i) {
  if (i.adapterOn == false) return BleLinkStatus.adapterOff;
  if (i.permissionGranted == false) return BleLinkStatus.permissionMissing;
  if (i.reconnecting) return BleLinkStatus.reconnecting;

  if (i.gattConnected) {
    // Bỏ qua dữ liệu có trước lần kết nối hiện tại (không dùng cache như dữ liệu trực tiếp).
    var dataAt = i.lastDataAt;
    final c = i.connectedAt;
    if (dataAt != null && c != null && dataAt.isBefore(c)) dataAt = null;

    if (dataAt != null) {
      final age = i.now.difference(dataAt);
      return age <= i.freshWindow
          ? BleLinkStatus.receivingData
          : BleLinkStatus.dataStale;
    }
    if (!i.servicesDiscovered) return BleLinkStatus.discoveringServices;
    if (i.authInProgress) return BleLinkStatus.authenticating;
    if (c != null && i.now.difference(c) > i.noDataGrace) {
      return BleLinkStatus.connectedNoData;
    }
    if (!i.authorized) return BleLinkStatus.authenticating;
    return BleLinkStatus.connected;
  }

  if (i.gattConnecting) return BleLinkStatus.connecting;
  if (i.deviceFound) return BleLinkStatus.deviceFound;
  if (i.scanning) return BleLinkStatus.scanning;
  return i.everConnected ? BleLinkStatus.disconnected : BleLinkStatus.idle;
}

/// Chất lượng tín hiệu theo RSSI (dBm). Các mốc là quy ước hiển thị của ứng
/// dụng (cùng mốc với màn quét thiết bị), KHÔNG phải thông số của xe.
enum SignalQuality { unknown, excellent, good, fair, weak }

SignalQuality signalQualityFromRssi(int? rssi) {
  if (rssi == null) return SignalQuality.unknown;
  if (rssi >= -55) return SignalQuality.excellent;
  if (rssi >= -70) return SignalQuality.good;
  if (rssi >= -85) return SignalQuality.fair;
  return SignalQuality.weak;
}

String signalQualityLabel(SignalQuality q) {
  switch (q) {
    case SignalQuality.unknown:
      return 'Chưa có RSSI';
    case SignalQuality.excellent:
      return 'Rất mạnh';
    case SignalQuality.good:
      return 'Tốt';
    case SignalQuality.fair:
      return 'Trung bình';
    case SignalQuality.weak:
      return 'Yếu';
  }
}

/// Suy ra các cờ liên kết từ BƯỚC kết nối đang chạy (ConnectStage) trong lúc
/// BleController còn ở phase "connecting". Chỉ là cách đọc quan sát được:
/// bước đã BẮT ĐẦU thì các bước trước nó đã xong.
class StageFlags {
  const StageFlags({
    required this.gattConnected,
    required this.servicesDiscovered,
    required this.authInProgress,
    required this.authDone,
  });

  final bool gattConnected;
  final bool servicesDiscovered;
  final bool authInProgress;
  final bool authDone;
}

StageFlags stageFlagsFor(ConnectStage? s) {
  switch (s) {
    case null:
    case ConnectStage.permissions:
    case ConnectStage.adapter:
    case ConnectStage.scan:
    case ConnectStage.selectDevice:
    case ConnectStage.gattConnect:
      return const StageFlags(
          gattConnected: false,
          servicesDiscovered: false,
          authInProgress: false,
          authDone: false);
    case ConnectStage.mtu:
    case ConnectStage.bonding:
    case ConnectStage.discoverServices:
      return const StageFlags(
          gattConnected: true,
          servicesDiscovered: false,
          authInProgress: false,
          authDone: false);
    case ConnectStage.readFirmware:
    case ConnectStage.authChallenge:
    case ConnectStage.appAuth:
    case ConnectStage.authResponse:
    case ConnectStage.sessionKey:
    case ConnectStage.sessionRegister:
      return const StageFlags(
          gattConnected: true,
          servicesDiscovered: true,
          authInProgress: true,
          authDone: false);
    case ConnectStage.notifications:
    case ConnectStage.telemetry:
      return const StageFlags(
          gattConnected: true,
          servicesDiscovered: true,
          authInProgress: false,
          authDone: true);
  }
}
