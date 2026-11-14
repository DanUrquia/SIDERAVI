import 'dart:math' as math;
import 'dart:ui';

import '../missions/mission.dart';
import 'mars_projection.dart';

/// Snapshot of one Mars Trek layer's verified WMTS metadata.
final class TrekLayer {
  /// Defines the layer's raster size, geographic coverage and REST template.
  const TrekLayer({
    required this.id,
    required this.product,
    required this.tilePixels,
    required this.maxMatrix,
    required this.coverage,
    required this.resourceTemplate,
  });

  final String id;
  final String product;
  final int tilePixels;
  final int maxMatrix;
  final Rect coverage;
  final String resourceTemplate;

  static const crs = 'urn:ogc:def:crs:EPSG::104905';
  static const matrixSet = 'default028mm';
  static const style = 'default';
  static const _origin = Offset(-180, 90);
  static const servicePrefix = 'https://trek.nasa.gov/tiles/Mars/EQ/';

  /// Applies the metadata-driven REST template to one valid tile address.
  Uri tileUri(int matrix, int row, int column) {
    RangeError.checkValueInInterval(matrix, 0, maxMatrix, 'matrix');
    RangeError.checkValueInInterval(row, 0, (1 << matrix) - 1, 'row');
    return Uri.parse(
      resourceTemplate
          .replaceAll('{Style}', style)
          .replaceAll('{TileMatrixSet}', matrixSet)
          .replaceAll('{TileMatrix}', '$matrix')
          .replaceAll('{TileRow}', '$row')
          .replaceAll('{TileCol}', '${column % (2 << matrix)}'),
    );
  }

  /// Returns the angular span recorded by this matrix's global tile dimensions.
  double tileDegrees(int matrix) => 180 / (1 << matrix);

  /// Chooses the nearest matrix in resolution, including 512px global tiles.
  int matrixFor(double degreesPerPixel) {
    final level = (math.log(180 / tilePixels / degreesPerPixel) / math.ln2)
        .round();
    return level.clamp(0, maxMatrix);
  }

  /// Reports whether this display scale exceeds the layer's finest raster.
  bool atResolutionLimit(double degreesPerPixel) =>
      degreesPerPixel < tileDegrees(maxMatrix) / tilePixels;

  /// Enumerates viewport tiles clipped to the layer's declared geographic box.
  Iterable<TrekTile> tiles(Rect visible, int matrix) sync* {
    final step = tileDegrees(matrix);
    final firstWorld = ((visible.left + 180) / 360).floor();
    final lastWorld = ((visible.right + 180) / 360).ceil() - 1;
    for (var world = firstWorld; world <= lastWorld; world++) {
      final wrappedCoverage = coverage.shift(Offset(world * 360, 0));
      final area = visible.intersect(wrappedCoverage);
      if (area.isEmpty) continue;
      final firstRow = ((_origin.dy - area.bottom) / step).floor();
      final lastRow = ((_origin.dy - area.top) / step).ceil() - 1;
      final firstCol = ((area.left - _origin.dx) / step).floor();
      final lastCol = ((area.right - _origin.dx) / step).ceil() - 1;
      for (var row = firstRow; row <= lastRow; row++) {
        for (var column = firstCol; column <= lastCol; column++) {
          yield tile(matrix, row, column, wrappedCoverage);
        }
      }
    }
  }

  /// Builds the unwrapped tile geometry separately from its wrapped URL.
  TrekTile tile(int matrix, int row, int column, Rect wrappedCoverage) {
    final step = tileDegrees(matrix);
    final left = _origin.dx + column * step;
    final north = _origin.dy - row * step;
    return TrekTile(
      layer: this,
      matrix: matrix,
      row: row,
      column: column,
      bounds: Rect.fromLTRB(left, north - step, left + step, north),
      coverage: wrappedCoverage,
    );
  }
}

/// A tile address and its geographic placement in one copy of the Mars globe.
final class TrekTile {
  /// Keeps the published coverage separate from the tile's rectangular raster.
  const TrekTile({
    required this.layer,
    required this.matrix,
    required this.row,
    required this.column,
    required this.bounds,
    required this.coverage,
  });

  final TrekLayer layer;
  final int matrix;
  final int row;
  final int column;
  final Rect bounds;
  final Rect coverage;

  /// Resolves the WMTS or advertised ArcGIS tile resource.
  Uri get uri => layer.tileUri(matrix, row, column);

  /// Finds a lower-resolution tile covering the same location.
  TrekTile ancestor(int level) {
    final shift = matrix - level;
    return layer.tile(level, row >> shift, column >> shift, coverage);
  }
}

const _wmtsPath =
    '/1.0.0//{Style}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png';

/// Global CTX raster advertised by the Mars Trek Capabilities document.
const globalTrekLayer = TrekLayer(
  id: 'CTX_beta01_uncontrolled_5m_Caltech',
  product: 'Global MRO CTX · Caltech Murray Lab / Esri',
  tilePixels: 512,
  maxMatrix: 11,
  coverage: MarsProjection.globalExtent,
  resourceTemplate:
      'https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer/tile/{TileMatrix}/{TileRow}/{TileCol}',
);

const _jezero = TrekLayer(
  id: 'JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0',
  product: 'MRO CTX · Jezero controlled mosaic',
  tilePixels: 256,
  maxMatrix: 13,
  coverage: Rect.fromLTRB(77.1604655, 18.2110274, 77.6991776, 18.7211945),
  resourceTemplate:
      '${TrekLayer.servicePrefix}'
      'JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0$_wmtsPath',
);
const _gale = TrekLayer(
  id: 'Gale_CTX_BlockAdj_dd',
  product: 'MRO CTX · Gale crater mosaic',
  tilePixels: 256,
  maxMatrix: 12,
  coverage: Rect.fromLTRB(135.1842593, -6.5732988, 139.2413012, -2.8077809),
  resourceTemplate: '${TrekLayer.servicePrefix}Gale_CTX_BlockAdj_dd$_wmtsPath',
);
const _endeavour = TrekLayer(
  id: 'HiRISE_Opportunity',
  product: 'MRO HiRISE · Opportunity mosaic',
  tilePixels: 256,
  maxMatrix: 17,
  coverage: Rect.fromLTRB(-5.6179114, -2.8342616, -4.9306494, -1.8895077),
  resourceTemplate: '${TrekLayer.servicePrefix}HiRISE_Opportunity$_wmtsPath',
);
const _columbia = TrekLayer(
  id: 'HiRISE_ColumbiaHills',
  product: 'MRO HiRISE · Columbia Hills mosaic',
  tilePixels: 256,
  maxMatrix: 16,
  coverage: Rect.fromLTRB(175.3183393, -14.847288, 175.7967313, -14.250304),
  resourceTemplate: '${TrekLayer.servicePrefix}HiRISE_ColumbiaHills$_wmtsPath',
);

/// Sets the initial field of view and a verified optional detail layer.
final class MissionTrekMap {
  /// Uses the short viewport dimension to fit the mission region.
  const MissionTrekMap(this.shortSideDegrees, {this.detail});

  final double shortSideDegrees;
  final TrekLayer? detail;

  /// Builds the mission view from the existing catalog reference coordinates.
  MarsScene scene(MarsMission mission, Size viewport) => MarsScene(
    viewport: viewport,
    latitude: mission.coordinates.latitude,
    longitude: mission.coordinates.eastLongitude,
    shortSideDegrees: shortSideDegrees,
  );
}

/// Configures map framing without duplicating catalog coordinates or identities.
const missionTrekMaps = {
  'jezero': MissionTrekMap(.48, detail: _jezero),
  'gale': MissionTrekMap(1.25, detail: _gale),
  'endeavour': MissionTrekMap(.50, detail: _endeavour),
  'columbia-hills': MissionTrekMap(.30, detail: _columbia),
  'valles-marineris': MissionTrekMap(4.5),
};
