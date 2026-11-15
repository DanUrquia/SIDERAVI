import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/astronaut.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/maps/mars_projection.dart';
import 'package:sidera_vi/missions/mars_solar_time.dart';
import 'package:sidera_vi/missions/mars_climate.dart';
import 'package:sidera_vi/missions/mission.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/missions/mola_elevations.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';
import 'package:sidera_vi/ui/dashboard/dashboard_panels.dart';
import 'package:sidera_vi/ui/dashboard/mobile_map_controls.dart';
import 'package:sidera_vi/ui/dashboard/mobile_astronaut_content.dart';
import 'package:sidera_vi/ui/dashboard/solar_cycle_card.dart';

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
    'NASA Mars24 examples reproduce season, equation of time and Sun altitude',
    () {
      for (final (date, latitude, longitude, ls, eot, elevation) in [
        (DateTime.utc(2000, 1, 6), 0.0, 0.0, 277.18758, -5.18774, -64.26182),
        (
          DateTime.utc(2004, 1, 3, 13, 46, 31),
          -14.4747,
          175.298,
          327.32416,
          -12.77553,
          -61.93895,
        ),
      ]) {
        final solar = MarsSolarCycle.at(
          date,
          planetocentricLatitude: latitude,
          eastLongitude: longitude,
        );
        expect(solar.solarLongitude, closeTo(ls, .002));
        expect(solar.equationOfTimeDegrees, closeTo(eot, .002));
        expect(solar.elevationDegrees, closeTo(elevation, .002));
        expect(solar.isDaylight, isFalse);
      }
    },
  );

  test(
    'All five Habitat Bases have seasonal horizon crossings and daylight duration',
    () {
      const reference = {
        'endeavour': ('06:27', '18:24', 11.949, '05:23', '17:21', -85.0),
        'gale': ('06:29', '18:22', 11.878, '05:24', '17:20', -40.0),
        'columbia-hills': ('06:35', '18:15', 11.667, '05:28', '17:16', -55.0),
        'valles-marineris': ('06:35', '18:16', 11.684, '05:28', '17:16', -80.0),
        'jezero': ('06:13', '18:38', 12.427, '05:14', '17:30', -51.0),
      };
      for (final mission in marsMissions) {
        final (dawn, dusk, daylight, laterDawn, laterDusk, temperature) =
            reference[mission.id]!;
        final first = _atBase(mission, DateTime.utc(2026, 11, 15, 18));
        final second = _atBase(mission, DateTime.utc(2027, 9, 23, 18));
        expect(first.sunrise, dawn, reason: mission.id);
        expect(first.sunset, dusk, reason: mission.id);
        expect(first.daylightHours, closeTo(daylight, .001));
        expect(second.sunrise, laterDawn);
        expect(second.sunset, laterDusk);
        expect(
          (first.daylightHours - second.daylightHours).abs(),
          greaterThan(.01),
        );
        expect(
          marsClimateCelsius(
            mission.id,
            first,
            eastLongitude: mission.elevation!.location.eastLongitude,
          ),
          closeTo(temperature, .5),
        );
      }
    },
  );

  test('The sun marker spans the daylight arc and is absent at night', () {
    final mission = marsMissionById['jezero']!;
    final reference = DateTime.utc(2026, 11, 15, 18);
    final cycle = _atBase(mission, reference);
    MarsSolarCycle at(double logicalHours) => _atBase(
      mission,
      reference.add(
        Duration(
          milliseconds: ((logicalHours - cycle.localMeanHours) * 88775244 / 24)
              .round(),
        ),
      ),
    );
    final dawn = at(cycle.sunriseHours! + .004);
    final noon = at(12 - cycle.equationOfTimeDegrees / 15);
    final dusk = at(cycle.sunsetHours! - .004);
    for (final (solar, progress) in [(dawn, 0.0), (noon, .5), (dusk, 1.0)]) {
      expect(solar.isDaylight, isTrue);
      expect(solar.progress, closeTo(progress, .001));
    }
    expect(dawn.elevationDegrees, closeTo(0, .15));
    expect(noon.elevationDegrees, greaterThan(75));
    expect(dusk.elevationDegrees, closeTo(0, .15));
    for (final night in [
      at(cycle.sunriseHours! - .05),
      at(cycle.sunsetHours! + .05),
    ]) {
      expect(night.progress, isNull);
      expect(night.isDaylight, isFalse);
      expect(night.elevationDegrees, lessThan(0));
    }
    for (final (latitude, hours, state) in [
      (90.0, 24, 'Polar day'),
      (-90.0, 0, 'Polar night'),
    ]) {
      final pole = MarsSolarCycle.at(
        reference,
        planetocentricLatitude: latitude,
        eastLongitude: 0,
      );
      expect(pole.sunriseHours, isNull);
      expect(pole.sunsetHours, isNull);
      expect(pole.daylightHours, hours);
      expect(pole.skyState, state);
    }
  });

  test(
    'MACDA source, interpolation, periodic boundaries and unavailable fallback',
    () {
      expect(marsClimateSource, 'MACDA v2.0 · Mars Year 33');
      expect(marsClimateDatasetDoi, '10.5285/cd037a9ea387438fabf4d674dbe53088');
      double? sample(double ls, double hour) => macdaClimateCelsius(
        'endeavour',
        solarLongitude: ls,
        primeMeridianHours: hour,
      );
      // Derived MY33 mean at Ls bin 0, MTC 00:00 and a midpoint of four bins.
      expect(sample(0, 0), closeTo(202.3 - 273.15, 1e-10));
      expect(
        sample(7.5, 1),
        closeTo((202.3 + 197 + 199.4 + 193.9) / 4 - 273.15, 1e-10),
      );
      expect(sample(367.5, 25), sample(7.5, 1));
      expect(sample(-.01, -.01), closeTo(sample(359.99, 23.99)!, 1e-10));
      expect(sample(0, 24), sample(0, 0));
      expect(sample(double.nan, 0), isNull);
      final unknown = macdaClimateCelsius(
        'unmapped-site',
        solarLongitude: 0,
        primeMeridianHours: 0,
      );
      expect(unknown, isNull);
      expect(formatMarsClimate(unknown), 'Unavailable');
    },
  );

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

  testWidgets('All five phone dashboards display sourced climate telemetry', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 11, 15, 18);
    for (final mission in marsMissions) {
      final cycle = ValueNotifier(_atBase(mission, timestamp));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileMapTelemetry(mission: mission, cycle: cycle),
          ),
        ),
      );
      expect(find.text(cycle.value.localTime), findsOneWidget);
      expect(find.text('LMST at Base'), findsOneWidget);
      expect(find.text('Climate estimate'), findsOneWidget);
      expect(find.textContaining('°C'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
      expect(find.text('Illustrative'), findsNothing);
      expect(find.text('Demo reference'), findsNothing);
      expect(find.text(mission.elevationLabel), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      cycle.dispose();
    }
  });

  testWidgets(
    'Astronaut telemetry and topography use each mission’s verified data',
    (tester) async {
      for (final mission in marsMissions) {
        final map = missionMaps[mission.id]!;
        final navigation = DemoNavigation(map, startAtBase: true);
        final tracking = AstronautTracking(
          navigation: navigation,
          coordinates: map.coordinates,
          sensors: const NativeSensorService(),
        );
        final cycle = ValueNotifier(
          _atBase(mission, DateTime.parse('2026-11-16T01:45:00+05:00')),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MobileAstronautContent(
                  astronaut: const Astronaut(
                    id: 'OVIS-07',
                    fullName: 'Astronaut Test Identity',
                  ),
                  mission: mission,
                  navigation: navigation,
                  tracking: tracking,
                  solarCycle: cycle,
                  onSensorTest: () {},
                  onMovementLog: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('OVIS-07'), findsOneWidget);
        expect(find.text('Astronaut Test Identity'), findsOneWidget);
        final identity = find
            .ancestor(
              of: find.text('Astronaut Test Identity'),
              matching: find.byType(Column),
            )
            .first;
        expect(_inside(identity, mission.title), findsOneWidget);
        expect(find.text(tracking.stepStatus), findsOneWidget);

        final telemetry = _panel('MISSION TELEMETRY');
        for (final heading in [
          'MARS TIME',
          'TEMPERATURE',
          'ELEVATION',
          'EARTH TIME',
        ]) {
          expect(_inside(telemetry, heading), findsOneWidget);
        }
        final solar = cycle.value;
        expect(_inside(telemetry, solar.localTime), findsOneWidget);
        final climate = marsClimateCelsius(
          mission.id,
          solar,
          eastLongitude: mission.elevation!.location.eastLongitude,
        );
        expect(_inside(telemetry, formatMarsClimate(climate)), findsOneWidget);
        expect(_inside(telemetry, 'Climate estimate'), findsOneWidget);
        expect(_inside(telemetry, mission.elevationLabel), findsOneWidget);
        expect(_inside(telemetry, 'Tegucigalpa · UTC−6'), findsOneWidget);
        expect(_inside(telemetry, '14:45'), findsOneWidget);

        final solarCard = find.byType(SolarCycleCard);
        for (final value in {
          solar.localTime,
          solar.sunrise,
          solar.sunset,
          solar.daylight,
          solar.skyState,
        }) {
          expect(_inside(solarCard, value), findsWidgets);
        }
        cycle.value = _atBase(
          mission,
          solar.timestamp.add(const Duration(minutes: 2)),
        );
        await tester.pump();
        expect(_inside(telemetry, '14:47'), findsOneWidget);
        expect(_inside(telemetry, '14:45'), findsNothing);
        expect(_inside(telemetry, cycle.value.localTime), findsOneWidget);

        await tester.scrollUntilVisible(find.text('MARS TOPOGRAPHY'), 200);
        final topography = _panel('MARS TOPOGRAPHY');
        expect(
          _inside(topography, 'Maximum gridded elevation'),
          findsOneWidget,
        );
        expect(_inside(topography, mission.region), findsOneWidget);
        expect(_inside(topography, MarsBaseElevation.source), findsOneWidget);
        expect(_inside(topography, MarsBaseElevation.datum), findsOneWidget);
        expect(_inside(topography, mission.radiusLabel), findsOneWidget);
        final maximum = tester.widget<DashboardReadout>(
          find.descendant(
            of: topography,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DashboardReadout &&
                  widget.label == 'Maximum gridded elevation',
            ),
          ),
        );
        expect(
          maximum.value,
          formatMarsElevation(missionMaximumGridElevationMeters[mission.id]!),
        );
        expect(
          find.textContaining('within ${mission.radiusLabel} of Habitat Base'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        cycle.dispose();
        tracking.dispose();
        navigation.dispose();
      }
    },
  );
}

MarsSolarCycle _atBase(MarsMission mission, DateTime timestamp) {
  final site = mission.elevation!.location;
  return MarsSolarCycle.at(
    timestamp,
    planetocentricLatitude: site.latitude,
    eastLongitude: site.eastLongitude,
  );
}

Finder _panel(String title) => find.byWidgetPredicate(
  (widget) => widget is DashboardPanel && widget.title == title,
);

Finder _inside(Finder scope, String text) =>
    find.descendant(of: scope, matching: find.text(text));
