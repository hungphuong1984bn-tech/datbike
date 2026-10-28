/// Bộ lọc Kalman 1D tối ưu hoá cho tín hiệu RSSI Bluetooth Low Energy.
/// Giúp loại bỏ nhiễu giật cục (noise spikes), hiện tượng đa đường (multipath fading),
/// và suy hao tức thời khi người dùng đút điện thoại vào túi quần.
class KalmanFilter1D {
  /// Nhiễu quá trình (Process noise covariance): mức độ biến thiên tự nhiên của vị trí
  final double processNoise;

  /// Nhiễu đo lường (Measurement noise covariance): mức độ nhiễu loạn của phần cứng BLE
  final double measurementNoise;

  double? _estimate;
  double _errorCovariance = 1.0;

  KalmanFilter1D({
    this.processNoise = 0.008,
    this.measurementNoise = 4.0,
    double? initialEstimate,
  }) : _estimate = initialEstimate;

  /// Giá trị ước tính hiện tại (đã lọc mượt)
  double? get currentEstimate => _estimate;

  /// Cập nhật bộ lọc với giá trị RSSI đo được mới nhất
  double filter(double measurement) {
    if (_estimate == null) {
      _estimate = measurement;
      _errorCovariance = 1.0;
      return measurement;
    }

    // 1. Bước dự đoán (Predict)
    // x_k|k-1 = x_k-1|k-1
    final pPredicted = _errorCovariance + processNoise;

    // 2. Bước hiệu chỉnh (Update / Correct)
    // Kalman Gain: K = P / (P + R)
    final kalmanGain = pPredicted / (pPredicted + measurementNoise);

    // Cập nhật ước lượng trạng thái: x_k|k = x_k|k-1 + K * (z_k - x_k|k-1)
    _estimate = _estimate! + kalmanGain * (measurement - _estimate!);

    // Cập nhật ma trận hiệp phương sai sai số: P_k|k = (1 - K) * P_k|k-1
    _errorCovariance = (1.0 - kalmanGain) * pPredicted;

    return _estimate!;
  }

  /// Đặt lại trạng thái bộ lọc (ví dụ khi kết nối mới hoặc đổi thiết bị)
  void reset([double? initialValue]) {
    _estimate = initialValue;
    _errorCovariance = 1.0;
  }
}
