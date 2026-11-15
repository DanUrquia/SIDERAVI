import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../dashboard/terrain_view_controller.dart';
import '../../maps/mars_projection.dart';
import '../../maps/mars_trek_layers.dart';
import '../../maps/trek_tile_source.dart';
import 'dashboard_style.dart';

/// Paints the visible global and regional Mars Trek tiles below demo overlays.
class TrekTileView extends StatefulWidget {
  /// Uses the same scene transform as the interactive demo marker layer.
  const TrekTileView({
    super.key,
    required this.scene,
    required this.view,
    required this.source,
    required this.child,
    this.detail,
    this.statusBottom = 79,
    this.statusLeft = 15,
    this.statusRight = 15,
    this.statusFooter,
    this.layoutHud,
    this.showStatus = true,
    this.showResolutionLimit = true,
  });

  final MarsScene scene;
  final TerrainViewController view;
  final TrekTileSource source;
  final TrekLayer? detail;
  final double statusBottom;
  final double statusLeft;
  final double statusRight;
  final Widget? statusFooter;
  final Widget Function(Widget? status, Widget? footer)? layoutHud;
  final bool showStatus;
  final bool showResolutionLimit;
  final Widget child;

  @override
  State<TrekTileView> createState() => _TrekTileViewState();
}

/// Queues viewport-only work and bounds the decoded cache to a single dashboard.
class _TrekTileViewState extends State<TrekTileView> {
  static const _maxRequests = 6;
  static const _maxImages = 96;
  final _images = <Uri, ui.Image>{};
  final _failed = <Uri>{};
  final _running = <Uri>{};
  Map<Uri, TrekTile> _wanted = {};
  List<TrekTile> _base = [];
  List<TrekTile> _detail = [];
  List<TrekTile> _previousBase = [];
  List<TrekTile> _previousDetail = [];
  Timer? _update;
  bool _resolutionLimit = false;

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_scheduleUpdate);
    _updateViewport();
  }

  @override
  void didUpdateWidget(TrekTileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      oldWidget.view.removeListener(_scheduleUpdate);
      widget.view.addListener(_scheduleUpdate);
    }
    if (oldWidget.scene.viewport != widget.scene.viewport ||
        oldWidget.scene.center != widget.scene.center ||
        oldWidget.detail != widget.detail ||
        oldWidget.view != widget.view) {
      _updateViewport();
    }
  }

  /// Coalesces pan and pinch frames so intermediate tiles are not queued.
  void _scheduleUpdate() {
    _update ??= Timer(const Duration(milliseconds: 65), () {
      _update = null;
      if (!mounted) return;
      setState(_updateViewport);
    });
  }

  /// Selects each layer's matrix independently for the current scene scale.
  void _updateViewport() {
    final scene = widget.scene;
    final visible = scene.geographicBounds(
      widget.view.visibleScene(scene.viewport),
    );
    final degrees =
        scene.degreesPerPixel / widget.view.value.getMaxScaleOnAxis();
    final detail = widget.detail;
    final baseLevel = globalTrekLayer.matrixFor(degrees);
    final detailLevel = detail?.matrixFor(degrees);

    if (_base.isNotEmpty && _base.first.matrix != baseLevel) {
      final cached = _base
          .where((tile) => _images.containsKey(tile.uri))
          .toList();
      if (cached.isNotEmpty) _previousBase = cached;
    }
    if (_detail.isNotEmpty && _detail.first.matrix != detailLevel) {
      final cached = _detail
          .where((tile) => _images.containsKey(tile.uri))
          .toList();
      if (cached.isNotEmpty) _previousDetail = cached;
    }
    _base = globalTrekLayer.tiles(visible, baseLevel).toList();
    _detail = detail?.tiles(visible, detailLevel!).toList() ?? [];
    _resolutionLimit =
        globalTrekLayer.atResolutionLimit(degrees) ||
        (_detail.isNotEmpty && detail!.atResolutionLimit(degrees));

    final candidates = [..._base, ..._detail];
    final center = visible.center;
    // The center base tile gets priority, then nearby tiles from either layer.
    candidates.sort((a, b) {
      final aDistance = (a.bounds.center - center).distanceSquared;
      final bDistance = (b.bounds.center - center).distanceSquared;
      return aDistance.compareTo(bDistance);
    });
    _wanted = {for (final tile in candidates) tile.uri: tile};
    _failed.retainAll(_wanted.keys.toSet());

    _startRequests();
  }

  /// Starts only current viewport requests, leaving obsolete work to finish.
  void _startRequests() {
    for (final entry in _wanted.entries) {
      if (_running.length >= _maxRequests) break;
      final uri = entry.key;
      if (_images.containsKey(uri) ||
          _failed.contains(uri) ||
          !_running.add(uri)) {
        continue;
      }
      unawaited(_load(entry.value));
    }
  }

  /// Decodes the tile at its advertised dimensions and drops obsolete results.
  Future<void> _load(TrekTile tile) async {
    final uri = tile.uri;
    ui.Image? image;
    try {
      final bytes = await widget.source.fetch(uri);
      if (!mounted || !_wanted.containsKey(uri)) return;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted || !_wanted.containsKey(uri)) return;
      if (image.width != tile.layer.tilePixels ||
          image.height != tile.layer.tilePixels) {
        throw const FormatException('Unexpected WMTS tile dimensions');
      }
      _images[uri] = image;
      image = null;
      _evict();
    } catch (_) {
      if (mounted && _wanted.containsKey(uri)) _failed.add(uri);
    } finally {
      image?.dispose();
      _running.remove(uri);
      if (mounted) {
        _startRequests();
        setState(() {});
      }
    }
  }

  /// Keeps current tiles ahead of older tiles when reclaiming decoded memory.
  void _evict() {
    while (_images.length > _maxImages) {
      final oldest = _images.keys.firstWhere(
        (key) => !_wanted.containsKey(key),
        orElse: () => _images.keys.first,
      );
      _images.remove(oldest)!.dispose();
    }
  }

  /// Retries failed tiles while retaining the successfully decoded image cache.
  void _retry() {
    setState(() {
      _failed.clear();
      _startRequests();
    });
  }

  @override
  void dispose() {
    _update?.cancel();
    widget.view.removeListener(_scheduleUpdate);
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _failed.isNotEmpty;
    final baseError = _base.any((tile) => _failed.contains(tile.uri));
    final loading = _running.any(_wanted.containsKey);
    final showResolution = widget.showResolutionLimit && _resolutionLimit;
    final status = widget.showStatus && (loading || hasError || showResolution)
        ? _MapTileStatus(
            loading: loading,
            error: hasError
                ? baseError
                      ? 'Map connection unavailable'
                      : 'Detail tiles unavailable'
                : null,
            onRetry: _retry,
          )
        : null;
    final footer = widget.showStatus ? widget.statusFooter : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _TrekPainter(
              scene: widget.scene,
              tiles: _previousBase
                  .followedBy(_base)
                  .followedBy(_previousDetail)
                  .followedBy(_detail),
              images: _images,
              view: widget.view,
            ),
          ),
        ),
        widget.child,
        if (widget.layoutHud case final layout?)
          layout(status, footer)
        else if (status != null || footer != null)
          Positioned(
            bottom: widget.statusBottom,
            left: widget.statusLeft,
            right: widget.statusRight,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [?status, ?footer],
              ),
            ),
          ),
      ],
    );
  }
}

/// Composites registered rasters and uses cached parent tiles during transitions.
class _TrekPainter extends CustomPainter {
  _TrekPainter({
    required this.scene,
    required this.tiles,
    required this.images,
    required this.view,
  }) : super(repaint: view);

  final MarsScene scene;
  final Iterable<TrekTile> tiles;
  final Map<Uri, ui.Image> images;
  final TerrainViewController view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = DashboardStyle.inset);
    canvas.save();
    canvas.transform(view.value.storage);
    for (final tile in tiles) {
      final target = scene.pixelBounds(tile.bounds.intersect(tile.coverage));
      if (target.isEmpty) continue;
      var candidate = tile;
      var image = images[candidate.uri];
      for (
        var level = tile.matrix - 1;
        image == null && level >= math.max(0, tile.matrix - 2);
        level--
      ) {
        candidate = tile.ancestor(level);
        image = images[candidate.uri];
      }
      if (image == null) continue;
      final bounds = scene.pixelBounds(candidate.bounds);
      canvas.save();
      canvas.clipRect(target, doAntiAlias: false);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.low,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrekPainter oldDelegate) => true;
}

/// Keeps tile progress, connection errors and retry accessible over the map.
class _MapTileStatus extends StatelessWidget {
  const _MapTileStatus({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('map-tile-status'),
    color: DashboardStyle.inset,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Flexible(
            child: Semantics(
              liveRegion: error != null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  error ??
                      (loading
                          ? 'Loading Mars Trek tiles'
                          : 'Raster resolution limit'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          if (error != null)
            TextButton(onPressed: onRetry, child: const Text('Retry'))
          else
            const SizedBox(height: 33),
        ],
      ),
    ),
  );
}
