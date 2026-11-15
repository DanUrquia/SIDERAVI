import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/dashboard/terrain_view_controller.dart';
import 'package:sidera_vi/maps/mars_projection.dart';
import 'package:sidera_vi/maps/mars_trek_layers.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/ui/dashboard/trek_tile_view.dart';

import 'fake_trek_tiles.dart';

/// Checks published tile addresses, mission framing, and network recovery.
void main() {
  test('Normalizes longitude and matches points across the wrap', () {
    expect(MarsProjection.signedLongitude(354.8), closeTo(-5.2, 1e-10));
    expect(MarsProjection.signedLongitude(300.8), closeTo(-59.2, 1e-10));
    expect(MarsProjection.signedLongitude(180), -180);
    expect(MarsProjection.eastLongitude(-59.2), closeTo(300.8, 1e-10));
    final across = globalTrekLayer
        .tiles(const Rect.fromLTRB(179, -1, 181, 1), 7)
        .toList();
    expect(across.map((tile) => tile.column).toSet(), {255, 256});
    expect(
      across.firstWhere((tile) => tile.column == 256).uri.pathSegments.last,
      '0',
    );
    expect(across.where((tile) => tile.column == 256).first.bounds.left, 180);
  });

  test(
    'Uses mission reference points and an invertible north-up projection',
    () {
      expect(
        missionTrekMaps.keys.toSet(),
        marsMissions.map((m) => m.id).toSet(),
      );
      for (final mission in marsMissions) {
        final config = missionTrekMaps[mission.id]!;
        final scene = config.scene(mission, const Size(780, 840));
        const center = Offset(390, 420);
        expect(scene.toGeographic(center), scene.center);
        expect(scene.center.dy, mission.coordinates.latitude);
        expect(
          MarsProjection.eastLongitude(scene.center.dx),
          closeTo(mission.coordinates.eastLongitude, 1e-10),
        );
        expect(
          scene.toGeographic(center - const Offset(0, 20)).dy,
          greaterThan(scene.center.dy),
        );
        final point = const Offset(31, 104);
        expect(
          (scene.toPixel(scene.toGeographic(point)) - point).distance,
          lessThan(.000001),
        );
        final detail = config.detail;
        if (detail != null) {
          expect(detail.coverage.contains(scene.center), isTrue);
        }
      }
      expect(MarsProjection.metersPerLongitudeDegree(0), closeTo(59274.7, 1));
    },
  );

  test('Matches verified WMTS and REST resource templates', () {
    final expected = {
      'jezero': (
        12,
        1629,
        5863,
        'JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0',
      ),
      'gale': (10, 542, 1807, 'Gale_CTX_BlockAdj_dd'),
      'endeavour': (12, 2099, 3977, 'HiRISE_Opportunity'),
      'columbia-hills': (13, 4758, 16184, 'HiRISE_ColumbiaHills'),
    };
    for (final MapEntry(key: missionId, value: (matrix, row, col, id))
        in expected.entries) {
      final mission = marsMissionById[missionId]!;
      final map = missionTrekMaps[mission.id]!;
      final layer = map.detail!;
      final center = map.scene(mission, const Size(800, 700)).center;
      final address = layer
          .tiles(
            Rect.fromCenter(center: center, width: 1e-6, height: 1e-6),
            matrix,
          )
          .single;
      expect((address.matrix, address.row, address.column), (matrix, row, col));
      expect(
        address.uri.toString(),
        '${TrekLayer.servicePrefix}$id/1.0.0//default/default028mm/$matrix/$row/$col.png',
      );
      expect(layer.matrixFor(.0000001), layer.maxMatrix);
      expect(layer.matrixFor(999), 0);
      expect(
        layer.tiles(const Rect.fromLTRB(-12, -12, -11, -11), matrix),
        isEmpty,
      );
    }
    expect(
      globalTrekLayer.tileUri(8, 131, 248).toString(),
      'https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer/tile/8/131/248',
    );
    expect(() => globalTrekLayer.tileUri(12, 0, 0), throwsRangeError);
    expect(() => globalTrekLayer.tileUri(3, 8, 0), throwsRangeError);
    expect(globalTrekLayer.matrixFor(globalTrekLayer.tileDegrees(8) / 512), 8);
  });

  testWidgets('A phone can suppress a raster-limit badge with imagery loaded', (
    tester,
  ) async {
    const size = Size(800, 600);
    final mission = marsMissionById['valles-marineris']!;
    final scene = missionTrekMaps[mission.id]!.scene(mission, size);
    final view = TerrainViewController()
      ..fitArea(size.center(Offset.zero), 1000, size);
    addTearDown(view.dispose);
    final source = FakeTrekTiles(failing: false);
    Widget map({required bool showResolutionLimit}) => MaterialApp(
      home: TrekTileView(
        scene: scene,
        view: view,
        source: source,
        showResolutionLimit: showResolutionLimit,
        child: const SizedBox.expand(),
      ),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(map(showResolutionLimit: false));
      await Future<void>.delayed(const Duration(milliseconds: 160));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-tile-status')), findsNothing);
    expect(source.requested, isNotEmpty);
    expect(
      source.requested
          .map((uri) => uri.pathSegments[uri.pathSegments.length - 3])
          .toSet(),
      {globalTrekLayer.maxMatrix.toString()},
    );
    await tester.pumpWidget(map(showResolutionLimit: true));
    expect(find.text('Raster resolution limit'), findsOneWidget);
  });

  testWidgets(
    'Unavailable tiles show Retry and recover without leaving the map',
    (tester) async {
      final view = TerrainViewController();
      addTearDown(view.dispose);
      final source = FakeTrekTiles();
      final mission = marsMissionById['valles-marineris']!;
      final map = missionTrekMaps[mission.id]!;
      await tester.pumpWidget(
        MaterialApp(
          home: TrekTileView(
            scene: map.scene(mission, const Size(800, 600)),
            view: view,
            source: source,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Map connection unavailable'), findsOneWidget);
      final firstRequests = source.requested.toList();

      source.failing = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry'));
        await Future<void>.delayed(const Duration(milliseconds: 160));
      });
      await tester.pumpAndSettle();
      expect(find.text('Map connection unavailable'), findsNothing);
      expect(source.requested.length, firstRequests.length * 2);
      expect(find.text('Loading Mars Trek tiles'), findsNothing);
    },
  );
}
