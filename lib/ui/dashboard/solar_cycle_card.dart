import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../missions/mars_solar_time.dart';
import '../mission_theme.dart';
import 'dashboard_panels.dart';
import 'dashboard_style.dart';

/// Two presentations of the same Habitat Base solar cycle.
class SolarCycleCard extends StatelessWidget {
  const SolarCycleCard({super.key, required this.cycle, this.compact = false});

  final ValueListenable<MarsSolarCycle> cycle;
  final bool compact;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: cycle,
    builder: (context, solar, _) => compact
        ? DecoratedBox(
            key: const ValueKey('map-solar-cycle'),
            decoration: mapHudSurface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Row(
                    spacing: 3,
                    children: [
                      Expanded(
                        child: Text(
                          'SOLAR CYCLE',
                          style: MissionTheme.display(10, tracking: .4),
                        ),
                      ),
                      Icon(
                        solar.isDaylight ? Icons.light_mode : Icons.dark_mode,
                        color: solar.isDaylight
                            ? DashboardStyle.amber
                            : DashboardStyle.muted,
                        size: 17,
                        semanticLabel: solar.skyState,
                      ),
                    ],
                  ),
                  _SolarTrack(solar: solar, compact: true),
                ],
              ),
            ),
          )
        : DashboardPanel(
            title: 'SOLAR CYCLE',
            icon: solar.isDaylight ? Icons.light_mode : Icons.dark_mode,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Column(
                    spacing: 3,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mars time at Base (LMST)',
                        style: TextStyle(
                          fontSize: 12,
                          color: DashboardStyle.muted,
                        ),
                      ),
                      Text(
                        solar.localTime,
                        style: MissionTheme.display(
                          25,
                        ).copyWith(color: DashboardStyle.cyan),
                      ),
                    ],
                  ),
                  Text(
                    solar.skyState,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: solar.isDaylight
                          ? DashboardStyle.amber
                          : DashboardStyle.muted,
                    ),
                  ),
                ],
              ),
              DecoratedBox(
                decoration: DashboardStyle.surface(
                  color: DashboardStyle.inset,
                  radius: 11,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _SolarTrack(solar: solar, compact: false),
                ),
              ),
              DashboardReadout(
                label: 'Daylight duration',
                value: solar.daylight,
              ),
              DashboardReadout(
                label: 'Solar elevation',
                value: '${solar.elevationDegrees.toStringAsFixed(1)}°',
              ),
              const Text(
                'Geometric horizon at Habitat Base. Local terrain may delay sunrise or advance sunset.',
                style: TextStyle(fontSize: 12, color: DashboardStyle.muted),
              ),
            ],
          ),
  );
}

final mapHudSurface = DashboardStyle.surface(
  color: const Color(0xEE0B1320),
  radius: 10,
);

class _SolarTrack extends StatelessWidget {
  const _SolarTrack({required this.solar, required this.compact});

  final MarsSolarCycle solar;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final timeStyle = MissionTheme.display(compact ? 11 : 17);
    final labelStyle = TextStyle(
      fontSize: compact ? 9 : 12,
      color: DashboardStyle.muted,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: compact ? 2 : 5,
      children: [
        SizedBox(
          width: double.infinity,
          height: compact ? 23 : 104,
          child: CustomPaint(
            key: ValueKey(solar.isDaylight ? 'daylight-arc' : 'night-arc'),
            painter: _SolarArc(progress: solar.progress, compact: compact),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(solar.sunrise, style: timeStyle),
                  ),
                  Text('Sunrise', style: labelStyle),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(solar.sunset, style: timeStyle),
                  ),
                  Text('Sunset', style: labelStyle),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SolarArc extends CustomPainter {
  const _SolarArc({required this.progress, required this.compact});

  final double? progress;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final daylight = progress != null;
    final radius = compact ? 4.5 : 8.0;
    final inset = radius + (compact ? 1 : 3);
    final baseline = size.height - (compact ? 1.5 : inset);
    final width = size.width - 2 * inset;
    if (width <= 0) return;
    final height = baseline - inset;
    final curve = Path()
      ..moveTo(inset, baseline)
      ..quadraticBezierTo(
        size.width / 2,
        baseline - 2 * height,
        size.width - inset,
        baseline,
      );
    final area = Path.from(curve)..close();
    if (daylight) {
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, inset), Offset(0, baseline), [
            DashboardStyle.amber.withValues(alpha: .24),
            DashboardStyle.amber.withValues(alpha: .04),
          ]),
      );
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = daylight ? DashboardStyle.amber : DashboardStyle.outline
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = compact ? 1.5 : 2,
    );
    if (progress case final t?) {
      final center = Offset(
        inset + width * t,
        baseline - 4 * height * t * (1 - t),
      );
      canvas.drawCircle(
        center,
        radius + 3,
        Paint()..color = const Color(0x55FFBC22),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFFFFBC22),
      );
    }
  }

  @override
  bool shouldRepaint(_SolarArc oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.compact != compact;
}
