import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/astronaut.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/maps/mars_projection.dart';
import 'package:sidera_vi/missions/mars_solar_time.dart';
import 'package:sidera_vi/missions/mission.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/missions/mola_elevations.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';
import 'package:sidera_vi/ui/dashboard/mobile_map_controls.dart';
import 'package:sidera_vi/ui/dashboard/mobile_mission_sheets.dart';

void main() {
  test('Mars24 reference clocks match the published local mean times', () {
    expect(
      marsLocalMeanSolarSeconds(DateTime.utc(2000, 1, 6), eastLongitude: 0),
      closeTo(23 * 3600 + 59 * 60 + 39, 1),
    );
    expect(
      marsLocalMeanSolarSeconds(
        DateTime.utc(2004, 1, 3, 13, 46, 31),
        eastLongitude: 175.298,
      ),
      closeTo(51 * 60 + 7, 1),
    );
  });

  test('Mars clock wraps longitude and uses absolute time and a Mars sol', () {
    final utc = DateTime.utc(2026, 11, 15, 11);
    final elsewhere = DateTime.parse('2026-11-15T05:00:00-06:00');
    final a = marsLocalMeanSolarSeconds(utc, eastLongitude: -5.17);
    expect(
      marsLocalMeanSolarSeconds(utc, eastLongitude: 354.83),
      closeTo(a, 1e-6),
    );
    expect(marsLocalMeanSolarSeconds(elsewhere, eastLongitude: -5.17), a);
    expect(
      (marsLocalMeanSolarSeconds(utc, eastLongitude: 9.83) - a) % 86400,
      closeTo(3600, 1e-6),
    );
    expect(
      marsLocalMeanSolarSeconds(
        utc.add(const Duration(seconds: 88775, milliseconds: 244)),
        eastLongitude: -5.17,
      ),
      closeTo(a, .002),
    );
  });

  test(
    'MOLA bytes and maximum cell centers match the documented mission data',
    () {
      // 128-pixel/degree labels and big-endian samples from PDS MEGT/MEGC.
      const observations = {
        'endeavour': (
          baseBytes: 0xf909,
          peakBytes: 0xf914,
          row: 292,
          col: 10857,
          north: 0,
          west: 270,
        ),
        'gale': (
          baseBytes: 0xf5d2,
          peakBytes: 0xf630,
          row: 692,
          col: 6109,
          north: 0,
          west: 90,
        ),
        'columbia-hills': (
          baseBytes: 0xf872,
          peakBytes: 0xf874,
          row: 1862,
          col: 10960,
          north: 0,
          west: 90,
        ),
        'valles-marineris': (
          baseBytes: 0xf0de,
          peakBytes: 0xf159,
          row: 1771,
          col: 3946,
          north: 0,
          west: 270,
        ),
        'jezero': (
          baseBytes: 0xf5a4,
          peakBytes: 0xf5a4,
          row: 3278,
          col: 9939,
          north: 44,
          west: 0,
        ),
      };
      int decodeElevation(int sample) =>
          (ByteData(2)..setUint16(0, sample)).getInt16(0);
      expect(
        marsMissions.map((mission) => mission.id).toSet(),
        observations.keys.toSet(),
      );
      for (final mission in marsMissions) {
        final sample = observations[mission.id]!;
        expect(mission.elevation!.meters, decodeElevation(sample.baseBytes));
        expect(
          missionMaximumGridElevationMeters[mission.id],
          decodeElevation(sample.peakBytes),
        );
        final map = missionMaps[mission.id]!;
        final base = map.coordinates.toMars(map.base);
        final peak = Offset(
          sample.west + (sample.col + .5) / 128,
          sample.north - (sample.row + .5) / 128,
        );
        expect(
          surfaceDistance(base, peak, MarsProjection.radiusMeters),
          lessThanOrEqualTo(mission.radiusMeters),
        );
      }
    },
  );

  testWidgets(
    'The phone updates LMST and shows unavailable temperature in every mission',
    (tester) async {
      var timestamp = DateTime.utc(2026, 11, 15, 11);
      DateTime clock() => timestamp;

      for (final mission in marsMissions) {
        final map = missionMaps[mission.id]!;
        final longitude = map.coordinates.toMars(map.base).dx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MobileMapTelemetry(
                mission: mission,
                eastLongitude: longitude,
                clock: clock,
              ),
            ),
          ),
        );
        final start = formatMarsLocalMeanSolarTime(
          timestamp,
          eastLongitude: longitude,
        );
        expect(find.text(start), findsOneWidget);
        expect(find.text('LMST at Base'), findsOneWidget);
        expect(find.text('No local reading'), findsOneWidget);
        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.textContaining('°C'), findsNothing);
        expect(find.text('Illustrative'), findsNothing);
        expect(find.text('Demo reference'), findsNothing);
        expect(find.text(mission.elevationLabel), findsOneWidget);

        timestamp = timestamp.add(const Duration(seconds: 62));
        await tester.pump(const Duration(seconds: 1));
        final end = formatMarsLocalMeanSolarTime(
          timestamp,
          eastLongitude: longitude,
        );
        expect(end, isNot(start));
        expect(find.text(end), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'The Astronaut sheet exposes the maximum within its mission radius',
    (tester) async {
      for (final mission in marsMissions) {
        final map = missionMaps[mission.id]!;
        final navigation = DemoNavigation(map, startAtBase: true);
        final tracking = AstronautTracking(
          navigation: navigation,
          coordinates: map.coordinates,
          sensors: const NativeSensorService(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MobileAstronautContent(
                  astronaut: DemoCrew.dan,
                  mission: mission,
                  navigation: navigation,
                  tracking: tracking,
                  onSensorTest: () {},
                  onMovementLog: () {},
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(find.text('MOLA TOPOGRAPHY'), 200);
        expect(find.text('Max. gridded elevation'), findsOneWidget);
        expect(
          find.text(
            formatMarsElevation(missionMaximumGridElevationMeters[mission.id]!),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('within ${mission.radiusLabel} of Habitat Base'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        tracking.dispose();
        navigation.dispose();
      }
    },
  );
}
