// Cụm "Thông số nhanh" của tab Tổng quan: lưới 2 hoặc 3 cột tuỳ chiều rộng.
//
// Mỗi ô: biểu tượng · tên · giá trị lớn · đơn vị · NGUỒN dữ liệu (Xe / BMS / Tính toán).
// Nguyên tắc dữ liệu: chỉ giá trị xe đã gửi thật; thiếu → "--". Mất kết nối hoặc
// telemetry cũ → ô mờ đi và tiêu đề gắn huy hiệu "Dữ liệu cũ". Không số mẫu.
//
// Chỉ ĐỌC telemetry (bleProvider). Không gửi lệnh, không đổi giao thức.
//
// Các thông số đã có chỗ riêng được cố ý KHÔNG lặp ở đây: SOC, tốc độ, ODO,
// điện áp, dòng điện, công suất, quãng đường còn lại (thẻ Hero).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/components.dart';
import '../../ui/ds/ds.dart';
import '../../ui/widgets.dart';

/// Nguồn của một số liệu — hiển thị cho người dùng biết số này từ đâu ra.
enum MetricSource { vehicle, bms, estimate }

extension MetricSourceX on MetricSource {
  String get label {
    switch (this) {
      case MetricSource.vehicle:
        return 'Xe báo';
      case MetricSource.bms:
        return 'BMS';
      case MetricSource.estimate:
        return 'Tính toán';
    }
  }
}

/// Một ô thông số. [text] != null → hiển thị chữ (vd. chế độ lái); ngược lại
/// hiển thị số [value] (null → "--").
class OverviewMetric {
  final IconData icon;
  final String label;
  final double? value;
  final String? text;
  final String unit;
  final int decimals;
  final MetricSource source;

  const OverviewMetric({
    required this.icon,
    required this.label,
    required this.source,
    this.value,
    this.text,
    this.unit = '',
    this.decimals = 0,
  });
}

/// Bộ đọc: telemetry → danh sách ô → dựng lưới.
class OverviewMetricsSection extends ConsumerWidget {
  const OverviewMetricsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(bleProvider.select((s) => s.phase));
    final t = ref.watch(bleProvider.select((s) => s.lastTelemetry));
    final at = ref.read(bleProvider.notifier).lastTelemetryAt;
    final connected = phase == BlePhase.connected;

    final metrics = <OverviewMetric>[
      OverviewMetric(
        icon: Icons.device_thermostat_rounded,
        label: 'Nhiệt độ BMS',
        value: (t != null && t.bmsTemp > 0) ? t.bmsTemp : null,
        unit: '°C',
        source: MetricSource.bms,
      ),
      OverviewMetric(
        icon: Icons.settings_suggest_rounded,
        label: 'Nhiệt độ động cơ',
        value: (t != null && t.motor > 0) ? t.motor : null,
        unit: '°C',
        source: MetricSource.vehicle,
      ),
      OverviewMetric(
        icon: Icons.memory_rounded,
        label: 'Nhiệt độ ECU',
        value: (t != null && t.ecu > 0) ? t.ecu : null,
        unit: '°C',
        source: MetricSource.vehicle,
      ),
      OverviewMetric(
        icon: Icons.two_wheeler_rounded,
        label: 'Chế độ lái',
        // Chỉ hiện khi xe đang bật và đang kết nối — giống bảng Năng lượng cũ.
        text: (connected && t != null && t.isBikeOn) ? t.drivingModeLabel : null,
        source: MetricSource.vehicle,
      ),
    ];

    return OverviewMetricsGrid(
      metrics: metrics,
      phase: phase,
      lastTelemetryAt: at,
    );
  }
}

/// Lưới thuần (không đọc BLE) — dễ kiểm thử.
class OverviewMetricsGrid extends StatelessWidget {
  final List<OverviewMetric> metrics;
  final BlePhase phase;
  final DateTime? lastTelemetryAt;

  const OverviewMetricsGrid({
    super.key,
    required this.metrics,
    required this.phase,
    required this.lastTelemetryAt,
  });

  @override
  Widget build(BuildContext context) {
    final connected = phase == BlePhase.connected;
    return TickBuilder(
      builder: (context, now) {
        final fresh = connected
            ? freshnessFromTimestamp(lastTelemetryAt, now: now)
            : (lastTelemetryAt == null ? DataFreshness.none : DataFreshness.stale);
        final dim = fresh == DataFreshness.stale;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('Thông số kỹ thuật')),
                if (fresh != DataFreshness.live)
                  Flexible(
                    child: FreshnessBadge(
                      freshness: fresh,
                      detail: lastTelemetryAt == null
                          ? null
                          : formatAge(lastTelemetryAt, now: now),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, c) {
                // 3 cột khi đủ rộng (≥ 340dp) và số ô chia hết cho 3; ngược lại 2 cột (tránh ô lẻ).
                final cols = (c.maxWidth >= 340 && metrics.length % 3 == 0) ? 3 : 2;
                const gap = AppSpacing.sm;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final m in metrics)
                      SizedBox(
                        width: w,
                        child: AnimatedOpacity(
                          duration: AppMotion.normal,
                          opacity: dim ? 0.6 : 1.0,
                          child: _MetricTile(metric: m),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final OverviewMetric metric;
  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    final m = metric;
    final has = m.text != null || m.value != null;
    final spoken = m.text != null
        ? '${m.label}: ${m.text}'
        : (m.value == null
            ? '${m.label}: chưa có dữ liệu'
            : '${m.label}: ${m.value!.toStringAsFixed(m.decimals)} ${m.unit}');

    return Semantics(
      label: '$spoken. Nguồn: ${m.source.label}',
      excludeSemantics: true,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(m.icon, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: m.text != null
                    ? Text(m.text!,
                        style: AppTypography.evWide(fontSize: 18, letterSpacing: -0.2))
                    : AnimatedMetric(
                        value: m.value,
                        decimals: m.decimals,
                        unit: m.unit,
                        valueSize: 24,
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              has ? m.source.label : 'Chưa có dữ liệu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSm(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
