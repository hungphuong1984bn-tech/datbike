// DashboardView — dựng App Dashboard (đồng hồ TRÊN ĐIỆN THOẠI) theo profile.
// Không có logic BLE/GPS: nhận [values] đã phân giải (xem dashboard_model.dart).
// Thiếu dữ liệu → "--". Mỗi ô có nhãn nguồn (XE / GPS ĐT / TÍNH TOÁN / KHÔNG CÓ).
//
// Thiết kế: chữ lớn, tương phản cao, FittedBox chống tràn, bố cục tự đổi theo
// kích thước (ngang/dọc, màn nhỏ/lớn). Không có animation theo khung hình nên
// cập nhật 1–2 Hz của BLE không gây giật.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/dashboard/dashboard_model.dart';

class DashSkin {
  final Color bg1, bg2, fg, dim, accent, card, ok, warn, bad;
  final FontWeight speedWeight;
  final bool glow;
  final bool italic;
  final String? family;
  final double radius;
  final double letterSpacing;
  const DashSkin({
    required this.bg1,
    required this.bg2,
    required this.fg,
    required this.dim,
    required this.accent,
    required this.card,
    this.ok = const Color(0xFF22C55E),
    this.warn = const Color(0xFFF59E0B),
    this.bad = const Color(0xFFEF4444),
    this.speedWeight = FontWeight.w800,
    this.glow = false,
    this.italic = false,
    this.family,
    this.radius = 16,
    this.letterSpacing = 0,
  });
}

DashSkin skinFor(DashTheme t, {int? accentOverride}) {
  final base = switch (t) {
    DashTheme.sport => const DashSkin(
      bg1: Color(0xFF0A0A0F),
      bg2: Color(0xFF220A0A),
      fg: Color(0xFFFFFFFF),
      dim: Color(0xFFB4B8C4),
      accent: Color(0xFFFF4D2E),
      card: Color(0x1FFFFFFF),
      speedWeight: FontWeight.w900,
      italic: true,
      radius: 12,
    ),
    DashTheme.premium => const DashSkin(
      bg1: Color(0xFF0E0E10),
      bg2: Color(0xFF16161A),
      fg: Color(0xFFF5F1E8),
      dim: Color(0xFFB5AE9E),
      accent: Color(0xFFD4AF6A),
      card: Color(0x14FFFFFF),
      speedWeight: FontWeight.w200,
      radius: 4,
      letterSpacing: 1.2,
    ),
    DashTheme.cyber => const DashSkin(
      bg1: Color(0xFF04050F),
      bg2: Color(0xFF0B1030),
      fg: Color(0xFFE8F7FF),
      dim: Color(0xFF8FB4D6),
      accent: Color(0xFF00F0FF),
      card: Color(0x2200F0FF),
      speedWeight: FontWeight.w700,
      glow: true,
      family: 'monospace',
      radius: 6,
    ),
    DashTheme.touring => const DashSkin(
      bg1: Color(0xFF07131F),
      bg2: Color(0xFF0B2233),
      fg: Color(0xFFF1F7FB),
      dim: Color(0xFFA7BFCE),
      accent: Color(0xFF14B8A6),
      card: Color(0x1AFFFFFF),
      speedWeight: FontWeight.w700,
      radius: 18,
    ),
    DashTheme.minimal => const DashSkin(
      bg1: Color(0xFFFAFAFA),
      bg2: Color(0xFFFFFFFF),
      fg: Color(0xFF0B0B0B),
      dim: Color(0xFF4B5563),
      accent: Color(0xFF111111),
      card: Color(0x0F000000),
      ok: Color(0xFF15803D),
      warn: Color(0xFFB45309),
      bad: Color(0xFFB91C1C),
      speedWeight: FontWeight.w600,
      radius: 10,
    ),
    DashTheme.night => const DashSkin(
      bg1: Color(0xFF000000),
      bg2: Color(0xFF000000),
      fg: Color(0xFFE6B450),
      dim: Color(0xFF9A7B35),
      accent: Color(0xFFFFB300),
      card: Color(0x14FFB300),
      ok: Color(0xFF7FB069),
      warn: Color(0xFFFFB300),
      bad: Color(0xFFE05A47),
      speedWeight: FontWeight.w700,
      radius: 12,
    ),
  };
  if (accentOverride == null) return base;
  return DashSkin(
    bg1: base.bg1,
    bg2: base.bg2,
    fg: base.fg,
    dim: base.dim,
    accent: Color(accentOverride),
    card: base.card,
    ok: base.ok,
    warn: base.warn,
    bad: base.bad,
    speedWeight: base.speedWeight,
    glow: base.glow,
    italic: base.italic,
    family: base.family,
    radius: base.radius,
    letterSpacing: base.letterSpacing,
  );
}

class DashboardView extends StatelessWidget {
  final DashProfile profile;
  final Map<DashWidgetId, DashValue> values;

  /// true = vẽ trong khung nhỏ (xem trước): bỏ SafeArea/đệm lớn.
  final bool compact;

  const DashboardView({
    super.key,
    required this.profile,
    required this.values,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = skinFor(profile.theme, accentOverride: profile.accent);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [skin.bg1, skin.bg2],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            final wide = w > h * 1.15;
            final pad = compact ? 8.0 : 16.0;
            final ids = profile.widgets;
            final hero = ids.contains(DashWidgetId.speed)
                ? DashWidgetId.speed
                : (ids.contains(DashWidgetId.gpsSpeed)
                      ? DashWidgetId.gpsSpeed
                      : null);
            final rest = [
              for (final i in ids)
                if (i != hero) i,
            ];
            final inner = Padding(
              padding: EdgeInsets.all(pad),
              child: _body(skin, hero, rest, wide, w, h),
            );
            return inner;
          },
        ),
      ),
    );
  }

  Widget _body(
    DashSkin s,
    DashWidgetId? hero,
    List<DashWidgetId> rest,
    bool wide,
    double w,
    double h,
  ) {
    final heroW = hero == null
        ? null
        : _Hero(skin: s, id: hero, v: values[hero]!);
    final tiles = profile.layout == DashLayout.focus
        ? [for (final i in rest.take(3)) i]
        : rest;
    final grid = _TileGrid(
      skin: s,
      ids: tiles,
      values: values,
      columns: wide ? (profile.layout == DashLayout.split ? 2 : 3) : 2,
      compact: compact,
    );
    if (heroW == null) return grid;
    if (profile.layout == DashLayout.focus) {
      return Column(
        children: [
          Expanded(flex: 5, child: heroW),
          if (tiles.isNotEmpty) Expanded(flex: 2, child: grid),
        ],
      );
    }
    if (wide) {
      return Row(
        children: [
          Expanded(flex: 5, child: heroW),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: grid),
        ],
      );
    }
    return Column(
      children: [
        Expanded(flex: 4, child: heroW),
        const SizedBox(height: 8),
        Expanded(flex: 5, child: grid),
      ],
    );
  }
}

class _SourceTag extends StatelessWidget {
  final DashSkin skin;
  final DashValue v;
  const _SourceTag(this.skin, this.v);

  @override
  Widget build(BuildContext context) {
    final c = switch (v.source) {
      DashSource.bike => skin.accent,
      DashSource.phone => skin.ok,
      DashSource.derived => skin.warn,
      DashSource.none => skin.dim,
    };
    return Text(
      v.source.label + (v.note != null && v.available ? ' · ${v.note}' : ''),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: c,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final DashSkin skin;
  final DashWidgetId id;
  final DashValue v;
  const _Hero({required this.skin, required this.id, required this.v});

  @override
  Widget build(BuildContext context) {
    final color = v.available ? skin.fg : skin.dim;
    return Container(
      decoration: BoxDecoration(
        color: skin.card,
        borderRadius: BorderRadius.circular(skin.radius),
        border: Border.all(
          color: skin.accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: skin.glow
            ? [
                BoxShadow(
                  color: skin.accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            id.label.toUpperCase(),
            style: TextStyle(
              color: skin.dim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                v.text,
                key: const Key('dash_hero_value'),
                style: TextStyle(
                  color: color,
                  fontSize: 200,
                  height: 1.0,
                  fontWeight: skin.speedWeight,
                  fontStyle: skin.italic ? FontStyle.italic : FontStyle.normal,
                  fontFamily: skin.family,
                  letterSpacing: skin.letterSpacing,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: skin.glow
                      ? [Shadow(color: skin.accent, blurRadius: 18)]
                      : null,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                v.available ? v.unit : '',
                style: TextStyle(
                  color: skin.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Flexible(child: _SourceTag(skin, v)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  final DashSkin skin;
  final List<DashWidgetId> ids;
  final Map<DashWidgetId, DashValue> values;
  final int columns;
  final bool compact;
  const _TileGrid({
    required this.skin,
    required this.ids,
    required this.values,
    required this.columns,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    final rows = (ids.length / columns).ceil();
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : 6),
              child: Row(
                children: [
                  for (var c = 0; c < columns; c++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: c == columns - 1 ? 0 : 6,
                        ),
                        child: (r * columns + c) < ids.length
                            ? _Tile(
                                skin: skin,
                                id: ids[r * columns + c],
                                v: values[ids[r * columns + c]]!,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final DashSkin skin;
  final DashWidgetId id;
  final DashValue v;
  const _Tile({required this.skin, required this.id, required this.v});

  @override
  Widget build(BuildContext context) {
    final color = v.available ? skin.fg : skin.dim;
    Widget value;
    if (id == DashWidgetId.indicators && v.available) {
      value = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.arrow_left_rounded,
            size: 40,
            color: v.flagLeft == true
                ? skin.ok
                : skin.dim.withValues(alpha: 0.35),
          ),
          Icon(
            Icons.arrow_right_rounded,
            size: 40,
            color: v.flagRight == true
                ? skin.ok
                : skin.dim.withValues(alpha: 0.35),
          ),
        ],
      );
    } else {
      value = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: v.text,
                style: TextStyle(
                  color: color,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  fontFamily: skin.family,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (v.available && v.unit.isNotEmpty)
                TextSpan(
                  text: ' ${v.unit}',
                  style: TextStyle(
                    color: skin.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final label = Text(
      id.label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: skin.dim,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: skin.card,
        borderRadius: BorderRadius.circular(skin.radius),
        border: Border.all(color: skin.dim.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Ô thấp (nhiều widget / màn nhỏ): gộp nhãn + giá trị trên một hàng,
          // bỏ nhãn nguồn dài để không tràn.
          if (c.maxHeight < 62) {
            return Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    '${id.label.toUpperCase()}\n${v.source.label}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: skin.dim,
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Align(alignment: Alignment.centerRight, child: value),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              label,
              Expanded(child: Center(child: value)),
              _SourceTag(skin, v),
            ],
          );
        },
      ),
    );
  }
}
