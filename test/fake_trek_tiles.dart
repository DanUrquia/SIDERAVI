import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:sidera_vi/maps/trek_tile_source.dart';

/// Records viewport requests and serves fixture tiles without a network.
final class FakeTrekTiles implements TrekTileSource {
  FakeTrekTiles({this.failing = true});

  final requested = <Uri>[];
  bool failing;
  final _fixtures = <int, Future<Uint8List>>{};

  @override
  Future<Uint8List> fetch(Uri uri) async {
    requested.add(uri);
    if (failing) throw StateError('Offline');
    final pixels = uri.host == 'astro.arcgis.com' ? 512 : 256;
    return _fixtures.putIfAbsent(pixels, () => _createTile(pixels));
  }

  /// Builds valid PNG bytes of the dimensions used by the WMTS grids.
  Future<Uint8List> _createTile(int size) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFFA2653C), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  @override
  void close() {}
}
