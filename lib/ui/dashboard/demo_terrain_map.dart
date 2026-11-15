import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dashboard/demo_navigation.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../../maps/mars_projection.dart';
import '../../maps/mars_trek_layers.dart';
import '../../maps/trek_tile_source.dart';
import '../../missions/mission.dart';
import '../../sensors/sensor_measurements.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../../tracking/tracking_geometry.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';
import 'trek_tile_view.dart';

/// Offers pan, pinch, and geographic destination selection.
class DemoTerrainMap extends StatefulWidget {
  /// Composes the interchangeable terrain and local navigation layers.
  const DemoTerrainMap({
    super.key,
    required this.navigation,
    required this.view,
    required this.mission,
    required this.tileSource,
    required this.tracking,
    required this.astronautId,
    required this.teammateId,
    required this.peerPoint,
    required this.peer,
    required this.peerFresh,
    required this.teammateName,
    required this.onSelect,
    this.onAstronaut,
    this.fullScreen = false,
    this.showMapHud = true,
    this.overlayInsets = EdgeInsets.zero,
  });

  final DemoNavigation navigation;
  final TerrainViewController view;
  final MarsMission mission;
  final TrekTileSource tileSource;
  final AstronautTracking tracking;
  final String astronautId;
  final String teammateId;
  final Offset? peerPoint;
  final CrewPresence? peer;
  final bool peerFresh;
  final String teammateName;
  final void Function(Offset point, String label) onSelect;
  final VoidCallback? onAstronaut;
  final bool fullScreen;
  final bool showMapHud;
  final EdgeInsets overlayInsets;

  @override
  State<DemoTerrainMap> createState() => _DemoTerrainMapState();
}

/// Reuses the map transform for georeferenced markers and camera follow.
class _DemoTerrainMapState extends State<DemoTerrainMap>
    with SingleTickerProviderStateMixin {
  DemoNavigation get navigation => widget.navigation;
  TerrainViewController get view => widget.view;
  AstronautTracking get tracking => widget.tracking;

  static const _openingDelay = Duration(seconds: 1);
  static const _openingDuration = Duration(milliseconds: 1600);
  static const _followDuration = Duration(milliseconds: 220);
  static const _openingScaleBarMeters = 200.0;
  static const _headingDeadband = 1.5 * math.pi / 180;

  late final AnimationController _camera;
  Timer? _openingTimer;
  Timer? _gestureSettle;
  MarsScene? _scene;
  bool _openingZoom = false;
  bool _writingCamera = false;
  bool _interacting = false;
  ({Size viewport, Offset pixel})? _followTarget;
  Offset _cameraAnchor = Offset.zero;
  Offset _screenStart = Offset.zero;
  Offset _screenEnd = Offset.zero;
  double _rotationStart = 0;
  double _rotationEnd = 0;
  double _requestedRotation = 0;
  bool _centeringAstronaut = false;
  Offset _openingAnchor = Offset.zero;
  double _openingScale = 1;
  double _walkingScale = 1;

  @override
  void initState() {
    super.initState();
    _camera = AnimationController(vsync: this)
      ..addListener(_cameraFrame)
      ..addStatusListener(_cameraStatus);
    view.addListener(_cameraChanged);
    view.headingUp.addListener(_headingModeChanged);
    tracking.heading.addListener(_attitudeChanged);
    if (widget.fullScreen && widget.showMapHud) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.showMapHud) return;
        _openingTimer = Timer(_openingDelay, _openWalkingView);
      });
    }
  }

  @override
  void didUpdateWidget(DemoTerrainMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != view) {
      oldWidget.view.removeListener(_cameraChanged);
      oldWidget.view.headingUp.removeListener(_headingModeChanged);
      view.addListener(_cameraChanged);
      view.headingUp.addListener(_headingModeChanged);
      _requestedRotation = view.rotation;
      _manualCameraInput();
    }
    if (oldWidget.tracking != tracking) {
      oldWidget.tracking.heading.removeListener(_attitudeChanged);
      tracking.heading.addListener(_attitudeChanged);
    }
    if (!widget.showMapHud || !widget.fullScreen) _cancelOpeningZoom();
  }

  void _openWalkingView() {
    _openingTimer = null;
    final scene = _scene;
    if (!mounted || !widget.showMapHud || scene == null || _interacting) return;
    final viewport = scene.viewport;
    final pixel = _project(missionWorld(viewport), navigation.position);
    final geographic = scene.toGeographic(pixel);
    final detail = missionTrekMaps[widget.mission.id]!.detail;
    final layer =
        detail != null &&
            detail.coverage.contains(
              Offset(
                MarsProjection.signedLongitude(geographic.dx),
                geographic.dy,
              ),
            )
        ? detail
        : globalTrekLayer;
    _openingScale = view.value.getMaxScaleOnAxis();
    _openingAnchor = MatrixUtils.transformPoint(view.value, pixel);
    _walkingScale = TerrainViewController.zoomForGroundWidth(
      scene,
      pixel,
      _MarsScaleBar.width,
      _openingScaleBarMeters,
    ).clamp(1.0, TerrainViewController.rasterZoomLimit(scene, layer));
    _openingZoom = true;
    _startCamera(_openingDuration);
  }

  void _startCamera(Duration duration) {
    _camera.duration = duration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _camera.value = 0;
      _camera.value = 1;
    } else {
      _camera.forward(from: 0);
    }
  }

  void _cameraFrame() {
    _writingCamera = true;
    try {
      final scene = _scene;
      if (_openingZoom && scene != null) {
        final progress = Curves.easeInOutCubic.transform(_camera.value);
        final scale =
            _openingScale *
            math.pow(_walkingScale / _openingScale, progress).toDouble();
        final viewport = scene.viewport;
        final target = _project(missionWorld(viewport), navigation.position);
        final screen = Offset.lerp(
          _openingAnchor,
          viewport.center(Offset.zero),
          progress,
        )!;
        view.frame(target, screen, scale);
      } else {
        final progress = Curves.easeOut.transform(_camera.value);
        view.frame(
          _cameraAnchor,
          Offset.lerp(_screenStart, _screenEnd, progress)!,
          view.value.getMaxScaleOnAxis(),
          angle: _rotationStart + (_rotationEnd - _rotationStart) * progress,
        );
      }
    } finally {
      _writingCamera = false;
    }
  }

  void _cameraStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_openingZoom) return;
    _openingZoom = false;
    final viewport = _scene!.viewport;
    _followTarget = (
      viewport: viewport,
      pixel: _project(missionWorld(viewport), navigation.position),
    );
    tracking.setFollow(true);
  }

  void _cancelOpeningZoom() {
    _openingTimer?.cancel();
    _openingTimer = null;
    if (!_openingZoom) return;
    _openingZoom = false;
    _camera.stop();
  }

  void _manualCameraInput() {
    _cancelOpeningZoom();
    _camera.stop();
  }

  void _cameraChanged() {
    if (_writingCamera) return;
    _manualCameraInput();
    _gestureSettle?.cancel();
    if (!_interacting &&
        _shortArc(_requestedRotation - view.rotation).abs() >= .00001) {
      // InteractiveViewer can keep panning briefly after the last touch.
      _gestureSettle = Timer(const Duration(milliseconds: 95), () {
        _gestureSettle = null;
        _settleHeading();
      });
    }
  }

  bool get _headingUp => widget.fullScreen && view.headingUp.value;

  void _headingModeChanged() {
    final scene = _scene;
    if (!widget.fullScreen || scene == null) return;
    _gestureSettle?.cancel();
    _gestureSettle = null;
    _manualCameraInput();
    final viewport = scene.viewport;
    final center = viewport.center(Offset.zero);
    final heading = tracking.heading.value;
    _requestedRotation = _headingUp
        ? heading == null
              ? view.rotation
              : -heading * math.pi / 180
        : 0;
    if (_headingUp) {
      final pixel = _project(missionWorld(viewport), navigation.position);
      _followTarget = (viewport: viewport, pixel: pixel);
      tracking.setFollow(true);
      _animateCamera(pixel, center, centeringAstronaut: true);
    } else {
      _animateCamera(view.toScene(center), center);
    }
  }

  void _attitudeChanged() {
    if (!_headingUp) return;
    final heading = tracking.heading.value;
    if (heading == null || !heading.isFinite) return;
    final rotation = -heading * math.pi / 180;
    if (_shortArc(rotation - _requestedRotation).abs() >= _headingDeadband) {
      _requestedRotation = rotation;
    }
    _settleHeading();
  }

  void _settleHeading() {
    final scene = _scene;
    if (!widget.fullScreen ||
        _interacting ||
        _gestureSettle?.isActive == true ||
        scene == null) {
      return;
    }
    final activeRotation = _camera.isAnimating ? _rotationEnd : view.rotation;
    if (_shortArc(_requestedRotation - activeRotation).abs() < .00001) return;
    final center = scene.viewport.center(Offset.zero);
    final focus = _camera.isAnimating && _centeringAstronaut
        ? _followTarget?.pixel
        : null;
    _animateCamera(
      focus ?? view.toScene(center),
      center,
      centeringAstronaut: focus != null,
    );
  }

  double _shortArc(double radians) =>
      (radians + math.pi) % (2 * math.pi) - math.pi;

  /// Moves the existing terrain transform around a geographic anchor.
  void _animateCamera(
    Offset anchor,
    Offset screen, {
    bool centeringAstronaut = false,
  }) {
    final start = MatrixUtils.transformPoint(view.value, anchor);
    final rotation = view.rotation;
    final turn = _shortArc(_requestedRotation - rotation);
    if ((start - screen).distanceSquared < .000001 && turn.abs() < .00001) {
      return;
    }
    _cameraAnchor = anchor;
    _screenStart = start;
    _screenEnd = screen;
    _rotationStart = rotation;
    _rotationEnd = rotation + turn;
    _centeringAstronaut = centeringAstronaut;
    _startCamera(_followDuration);
  }

  /// Follows accepted positions while allowing temporary manual exploration.
  void _follow(Size viewport, Offset pixel) {
    if (!tracking.follow) {
      if (_followTarget != null && _centeringAstronaut && !_openingZoom) {
        _camera.stop();
      }
      _followTarget = null;
      return;
    }
    if (_interacting) return;
    _cancelOpeningZoom();
    final target = (viewport: viewport, pixel: pixel);
    if (_followTarget == target) return;
    _followTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !tracking.follow ||
          _followTarget != target ||
          _interacting) {
        return;
      }
      _animateCamera(
        pixel,
        viewport.center(Offset.zero),
        centeringAstronaut: true,
      );
    });
  }

  void _endInteraction() {
    _interacting = false;
    _settleHeading();
    if (_scene case final scene?) {
      final viewport = scene.viewport;
      _follow(viewport, _project(missionWorld(viewport), navigation.position));
    }
  }

  @override
  void dispose() {
    _openingTimer?.cancel();
    _gestureSettle?.cancel();
    view.removeListener(_cameraChanged);
    view.headingUp.removeListener(_headingModeChanged);
    tracking.heading.removeListener(_attitudeChanged);
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.fullScreen ? 0 : 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          // A square world preserves heading and distance on any viewport.
          final side = viewport.shortestSide;
          final world = missionWorld(viewport);
          final config = navigation.map;
          final areaScale = .52 / config.boundaryBounds.longestSide;
          final mission = widget.mission;
          final trek = missionTrekMaps[mission.id]!;
          final scene = trek.scene(mission, viewport);
          _scene = scene;
          final maxZoom = widget.fullScreen
              ? math.max(
                  areaScale,
                  TerrainViewController.rasterZoomLimit(
                    scene,
                    trek.detail ?? globalTrekLayer,
                  ),
                )
              : math.max(TerrainViewController.maxZoom, areaScale * 4);
          _follow(viewport, _project(world, navigation.position));
          final peerPoint = widget.peerPoint;
          final peer = widget.peer;
          final pairOnPhone = widget.fullScreen && peerPoint != null;
          final sharedAnchor = pairOnPhone && peerPoint == navigation.position
              ? peerPoint
              : null;
          final localAnchor = _project(world, navigation.position);
          final baseAnchor = _project(world, config.base);
          final peerAnchor = peerPoint == null
              ? null
              : _project(world, peerPoint);
          final scalePanel = _scalePanel(
            scene: scene,
            world: world,
            viewport: viewport,
            areaScale: areaScale,
            attribution: widget.fullScreen
                ? 'NASA Mars Trek'
                : 'Map imagery: NASA Mars Trek\n'
                      '${trek.detail?.product ?? globalTrekLayer.product}'
                      '${trek.detail == null ? '' : ' / Global CTX'}',
          );
          return TrekTileView(
            scene: scene,
            view: view,
            source: widget.tileSource,
            detail: trek.detail,
            showStatus: widget.showMapHud,
            showResolutionLimit: !widget.fullScreen,
            statusFooter: widget.fullScreen ? scalePanel : null,
            statusBottom:
                widget.overlayInsets.bottom + (widget.fullScreen ? 15 : 113),
            statusLeft: widget.overlayInsets.left + 14,
            statusRight: widget.overlayInsets.right + 78,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('demo-map-viewport'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final scene =
                        view.toScene(details.localPosition) - world.topLeft;
                    widget.onSelect(scene / side, 'Map waypoint');
                  },
                  child: Listener(
                    onPointerDown: (_) => _manualCameraInput(),
                    onPointerUp: (_) => _settleHeading(),
                    onPointerCancel: (_) => _settleHeading(),
                    onPointerSignal: (_) => _manualCameraInput(),
                    child: InteractiveViewer(
                      transformationController: view,
                      minScale: 1,
                      boundaryMargin: view.panMargin(viewport),
                      maxScale: maxZoom,
                      onInteractionStart: (_) {
                        _interacting = true;
                        _manualCameraInput();
                      },
                      onInteractionUpdate: (details) {
                        if (!_headingUp &&
                            tracking.follow &&
                            details.pointerCount == 1 &&
                            details.focalPointDelta.distanceSquared > 0) {
                          tracking.setFollow(false);
                        }
                      },
                      onInteractionEnd: (_) => _endInteraction(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            key: const ValueKey('mission-route-overlay'),
                            painter: _DemoGrid(
                              world: world,
                              navigation: navigation,
                              view: view,
                            ),
                          ),
                          _marker(
                            world,
                            config.base,
                            'Habitat base',
                            Icons.home_filled,
                            DashboardStyle.text,
                            labelAvoidsMarker: pairOnPhone ? peerAnchor : null,
                            onTap: () =>
                                widget.onSelect(config.base, 'Habitat base'),
                          ),
                          for (final landmark in config.landmarks)
                            _marker(
                              world,
                              landmark.position,
                              landmark.name,
                              Icons.terrain,
                              DashboardStyle.warm,
                              onTap: () => widget.onSelect(
                                landmark.position,
                                landmark.name,
                              ),
                              small: true,
                            ),
                          if (peerPoint != null)
                            _marker(
                              world,
                              peerPoint,
                              peer == null
                                  ? '${widget.teammateId} · DEMO'
                                  : widget.peerFresh
                                  ? widget.teammateId
                                  : '${widget.teammateId} · OFFLINE',
                              peer == null
                                  ? Icons.person
                                  : Icons.navigation_rounded,
                              peer == null
                                  ? DashboardStyle.cyan
                                  : widget.peerFresh
                                  ? DashboardStyle.amber
                                  : DashboardStyle.muted,
                              key: ValueKey(widget.teammateId),
                              heading: peer?.pose.heading,
                              animate: peer != null && !pairOnPhone,
                              nearby: [
                                if (!pairOnPhone) ...[localAnchor, baseAnchor],
                              ],
                              clusterWith: pairOnPhone ? localAnchor : null,
                              firstInCluster:
                                  widget.teammateId.compareTo(
                                    widget.astronautId,
                                  ) <
                                  0,
                              labelAvoidsBase: pairOnPhone ? baseAnchor : null,
                              description:
                                  'Select ${widget.teammateName} on map',
                              onTap: () => widget.onSelect(
                                peerPoint,
                                widget.teammateName,
                              ),
                            ),
                          for (final ping in navigation.pings)
                            _pingMarker(world, ping),
                          // The header still identifies a selected destination at the shared anchor.
                          if (navigation.target case final target?
                              when target != sharedAnchor)
                            _marker(
                              world,
                              target,
                              'Destination',
                              Icons.flag,
                              DashboardStyle.orange,
                              above: true,
                            ),
                          _marker(
                            world,
                            navigation.position,
                            '${widget.astronautId} · YOU',
                            navigation.sos
                                ? Icons.warning_amber_rounded
                                : Icons.navigation_rounded,
                            navigation.sos
                                ? DashboardStyle.danger
                                : DashboardStyle.cyan,
                            above: true,
                            key: ValueKey(widget.astronautId),
                            liveHeading: navigation.sos
                                ? null
                                : tracking.heading,
                            animate:
                                !widget.fullScreen &&
                                tracking.mode == TrackingMode.live,
                            emergency: navigation.sos,
                            localAstronaut: true,
                            onTap: pairOnPhone ? widget.onAstronaut : null,
                            clusterWith: pairOnPhone ? peerAnchor : null,
                            firstInCluster:
                                widget.astronautId.compareTo(
                                  widget.teammateId,
                                ) <
                                0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!widget.fullScreen)
                  Positioned(
                    left: 15,
                    top: 15,
                    child: _MapChip(
                      text: tracking.mode == TrackingMode.live
                          ? 'SIMULATED MARS'
                          : 'DEMO OVERLAY',
                      icon: Icons.layers_outlined,
                      color: DashboardStyle.warm,
                    ),
                  ),
                if (!widget.fullScreen)
                  Positioned(
                    right: 14,
                    top: 14,
                    child: const _MapChip(
                      text: 'N',
                      icon: Icons.navigation_rounded,
                    ),
                  ),
                if (!widget.fullScreen)
                  Positioned(
                    right: 14,
                    bottom: 16,
                    child: ValueListenableBuilder(
                      valueListenable: view,
                      builder: (context, transform, _) {
                        final zoom = transform.getMaxScaleOnAxis();
                        return Column(
                          spacing: 8,
                          children: [
                            _mapButton(
                              'Zoom in',
                              Icons.add,
                              zoom < maxZoom
                                  ? () => view.zoomBy(
                                      1.4,
                                      viewport,
                                      limit: maxZoom,
                                    )
                                  : null,
                            ),
                            _mapButton(
                              'Zoom out',
                              Icons.remove,
                              zoom > 1
                                  ? () => view.zoomBy(
                                      1 / 1.4,
                                      viewport,
                                      limit: maxZoom,
                                    )
                                  : null,
                            ),
                            _mapButton(
                              'Reset view',
                              Icons.center_focus_strong,
                              () {
                                tracking.setFollow(false);
                                view.reset();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (!widget.fullScreen)
                  Positioned(
                    left: 14,
                    right: 82,
                    bottom: 15,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: scalePanel,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scalePanel({
    required MarsScene scene,
    required Rect world,
    required Size viewport,
    required double areaScale,
    required String attribution,
  }) {
    final compact = widget.fullScreen;
    return DecoratedBox(
      key: const ValueKey('map-scale-panel'),
      decoration: DashboardStyle.surface(
        color: const Color(0xEE0B1320),
        radius: 10,
      ),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(10, 4, 10, 7)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: compact ? 3 : 4,
          children: [
            ValueListenableBuilder(
              valueListenable: view,
              builder: (context, transform, _) {
                final zoom = transform.getMaxScaleOnAxis();
                final local = compact
                    ? (zoom - areaScale).abs() < .001
                    : zoom >= areaScale - .001;
                return TextButton(
                  onPressed: () {
                    tracking.setFollow(_headingUp);
                    final point = _headingUp && local
                        ? navigation.position
                        : navigation.map.base;
                    if (local && !_headingUp) {
                      view.reset();
                    } else {
                      view.fitArea(
                        _project(world, point),
                        local ? 1 : areaScale,
                        viewport,
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: DashboardStyle.warm,
                    alignment: compact
                        ? Alignment.bottomLeft
                        : Alignment.center,
                    padding: compact
                        ? const EdgeInsets.only(bottom: 2)
                        : EdgeInsets.zero,
                    minimumSize: Size(0, compact ? 28 : 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '${local ? 'View region' : 'Fit area'} · ${widget.mission.radiusLabel} radius',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
            _MarsScaleBar(scene: scene, view: view),
            if (compact && navigation.routeTarget != null)
              const Text(
                'Direct guidance · Terrain unverified',
                style: TextStyle(fontSize: 11, color: DashboardStyle.warm),
              ),
            Text(
              attribution,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DashboardStyle.text,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Follows the scene anchor while keeping the marker upright in screen space.
  Widget _marker(
    Rect world,
    Offset local,
    String label,
    IconData icon,
    Color color, {
    Key? key,
    double? heading,
    ValueNotifier<double?>? liveHeading,
    bool animate = false,
    List<Offset> nearby = const [],
    Offset? clusterWith,
    bool firstInCluster = false,
    Offset? labelAvoidsMarker,
    Offset? labelAvoidsBase,
    Offset shift = Offset.zero,
    String? description,
    VoidCallback? onTap,
    bool small = false,
    bool above = false,
    bool emergency = false,
    bool localAstronaut = false,
  }) {
    final anchor = _project(world, local);
    final duration = animate && !MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    const width = 210.0;
    const height = 138.0;
    final center = Offset(width / 2, height / 2);
    final buttonSize = small && onTap == null ? 30.0 : 48.0;
    const labelWidth = 146.0;
    return AnimatedPositioned(
      key: key,
      duration: duration,
      curve: Curves.easeOut,
      width: width,
      height: height,
      left: anchor.dx - center.dx,
      top: anchor.dy - center.dy,
      child: ListenableBuilder(
        listenable: Listenable.merge([view, view.headingUp]),
        builder: (context, _) {
          final transform = view.value;
          final scale = transform.getMaxScaleOnAxis();
          final rotation = view.rotation;
          final screenAnchor = MatrixUtils.transformPoint(transform, anchor);
          Offset screenDelta(Offset point) =>
              MatrixUtils.transformPoint(transform, point) - screenAnchor;
          Offset? collision;
          var nearest = 34.0;
          for (final point in nearby) {
            final distance = screenDelta(point).distance;
            if (distance < nearest) {
              nearest = distance;
              collision = point;
            }
          }
          final collisionDelta = collision == null
              ? null
              : screenDelta(collision);
          final separation = collisionDelta == null
              ? Offset.zero
              : Offset(
                  collisionDelta.dx > 0 ? -48 : 48,
                  collisionDelta.dy > 0 ? -24 : 24,
                );
          final partnerDelta = clusterWith == null
              ? null
              : screenDelta(clusterWith);
          final clustered =
              partnerDelta != null && partnerDelta.distance < buttonSize;
          var clusterShift = 0.0;
          if (clustered) {
            // Share the space needed for both touch targets between the chips.
            final needed = math.sqrt(
              buttonSize * buttonSize - partnerDelta.dy * partnerDelta.dy,
            );
            final goesLeft =
                partnerDelta.dx > 0 || (partnerDelta.dx == 0 && firstInCluster);
            clusterShift = (needed - partnerDelta.dx.abs()) / 2;
            if (goesLeft) clusterShift = -clusterShift;
          }
          // Reserve space for nearby labels without moving their markers.
          final peer = labelAvoidsMarker == null
              ? null
              : screenDelta(labelAvoidsMarker);
          final base = labelAvoidsBase == null
              ? null
              : screenDelta(labelAvoidsBase);
          final labelAbove =
              above ||
              clustered ||
              (peer != null &&
                  peer.dx.abs() < labelWidth / 2 + 24 &&
                  peer.dy > 0 &&
                  peer.dy < 68) ||
              (base != null && base.dy >= 0 && base.distance < 72);
          final at = center + shift + separation + Offset(clusterShift, 0);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ(-rotation)
              ..scaleByDouble(1 / scale, 1 / scale, 1 / scale, 1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (collision != null)
                  Positioned(
                    left: center.dx,
                    top: center.dy,
                    child: IgnorePointer(
                      key: const ValueKey('marker-collision-tether'),
                      child: Transform.rotate(
                        angle: separation.direction,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: separation.distance,
                          height: 2,
                          child: ColoredBox(color: color),
                        ),
                      ),
                    ),
                  ),
                if (emergency)
                  Positioned(
                    left: at.dx - 43,
                    top: at.dy - 43,
                    child: IgnorePointer(
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0x66FF4242),
                          border: Border.all(
                            color: DashboardStyle.danger,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: at.dx - buttonSize / 2,
                  top: at.dy - buttonSize / 2,
                  child: _MarkerChip(
                    icon: icon,
                    color: color,
                    size: buttonSize,
                    description: description ?? label,
                    onTap: onTap,
                    small: small,
                    heading: heading,
                    liveHeading: liveHeading,
                    faceUp: localAstronaut && _headingUp,
                    rotation: localAstronaut ? 0 : rotation,
                  ),
                ),
                if (!small)
                  Positioned(
                    width: labelWidth,
                    left: clustered
                        ? clusterShift < 0
                              ? at.dx - labelWidth + 18
                              : at.dx - 18
                        : at.dx - labelWidth / 2,
                    top:
                        at.dy +
                        (labelAbove
                            ? -51
                            : labelAvoidsMarker != null
                            ? 26
                            : 22),
                    child: IgnorePointer(
                      child: Align(
                        alignment: clustered
                            ? clusterShift < 0
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft
                            : Alignment.center,
                        child: _MapChip(
                          text: label,
                          color: color,
                          compact: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Offsets ping glyphs in screen space when they share a route point.
  Widget _pingMarker(Rect world, DemoPing ping) {
    final (icon, color, shift) = switch (ping.type) {
      DemoPingType.location => (
        Icons.place_outlined,
        DashboardStyle.cyan,
        const Offset(-25, -24),
      ),
      DemoPingType.item => (
        Icons.inventory_2_outlined,
        DashboardStyle.warm,
        const Offset(0, -32),
      ),
      DemoPingType.danger => (
        Icons.warning_amber_rounded,
        DashboardStyle.amber,
        const Offset(25, -24),
      ),
    };
    return _marker(
      world,
      ping.position,
      ping.type.label,
      icon,
      color,
      key: ValueKey((ping.type, ping.position)),
      shift: shift,
      small: true,
    );
  }

  /// Provides glove-sized map controls with labels for assistive technology.
  Widget _mapButton(String label, IconData icon, VoidCallback? action) =>
      Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 54,
          child: FilledButton(
            onPressed: action,
            style: MissionTheme.control(
              fill: DashboardStyle.panel,
              border: DashboardStyle.outline,
              elevation: 0,
              radius: 12,
            ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.zero)),
            child: Icon(icon, size: 25),
          ),
        ),
      );
}

/// Projects the normalized local grid using one scale for both axes.
Offset _project(Rect world, Offset point) =>
    world.topLeft + Offset(point.dx * world.width, point.dy * world.height);

/// Renders the boundary, route line and local emergency highlight in scene space.
class _DemoGrid extends CustomPainter {
  _DemoGrid({
    required this.world,
    required DemoNavigation navigation,
    required this.view,
  }) : boundary = navigation.map.boundary,
       position = navigation.position,
       target = navigation.routeTarget,
       emergency = navigation.sos,
       super(repaint: view);

  final Rect world;
  final TerrainViewController view;
  final List<Offset> boundary;
  final Offset position;
  final Offset? target;
  final bool emergency;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0x29F7ECE1);
    final step = world.width / 8;
    for (var x = world.left % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = world.top % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final scale = view.value.getMaxScaleOnAxis();
    final rim = Path()
      ..addPolygon(
        boundary.map((point) => _project(world, point)).toList(),
        true,
      );
    canvas.drawPath(rim, Paint()..color = const Color(0x22FF632E));
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 / scale
        ..color = const Color(0xA5FFB179),
    );

    final from = _project(world, position);
    if (target case final destination?) {
      final vector = _project(world, destination) - from;
      final length = vector.distance;
      final line = Paint()
        ..color = emergency ? DashboardStyle.danger : DashboardStyle.warm
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 / scale;
      if (length > 0) {
        final unit = vector / length;
        const duty = 9 / 16;
        final count = (length * scale / 16).ceil().clamp(1, 300);
        final stride = length / ((count - 1) + duty);
        for (var index = 0; index < count; index++) {
          canvas.drawLine(
            from + unit * (stride * index),
            index == count - 1
                ? _project(world, destination)
                : from + unit * (stride * (index + duty)),
            line,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DemoGrid oldDelegate) =>
      world != oldDelegate.world ||
      boundary != oldDelegate.boundary ||
      position != oldDelegate.position ||
      target != oldDelegate.target ||
      emergency != oldDelegate.emergency;
}

/// A screen-space label with a high-contrast background over orbital imagery.
class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.text,
    this.icon,
    this.color = DashboardStyle.text,
    this.compact = false,
  });

  final String text;
  final IconData? icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: DashboardStyle.surface(
      color: const Color(0xEF101929),
      radius: 9,
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 11,
        vertical: compact ? 5 : 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (icon case final glyph?) Icon(glyph, size: 16, color: color),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MissionTheme.display(
                compact ? 11 : 13,
                tracking: .55,
              ).copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Separates visual marker size from the accessible hit area.
class _MarkerChip extends StatelessWidget {
  const _MarkerChip({
    required this.icon,
    required this.color,
    required this.size,
    required this.description,
    this.onTap,
    this.small = false,
    this.heading,
    this.liveHeading,
    required this.faceUp,
    required this.rotation,
  });

  final IconData icon;
  final Color color;
  final double size;
  final String description;
  final VoidCallback? onTap;
  final bool small;
  final double? heading;
  final ValueNotifier<double?>? liveHeading;
  final bool faceUp;
  final double rotation;

  Widget _arrow(double? value) {
    final glyph = Icon(icon, color: color, size: small ? 15 : 23);
    if (icon != Icons.navigation_rounded) return glyph;
    return Transform.rotate(
      angle: rotation,
      child: RelativeMarkerArrow(
        key: ValueKey(faceUp),
        heading: faceUp && value != null ? 0 : value,
        child: glyph,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marker = Center(
      child: Container(
        width: small ? 26 : 42,
        height: small ? 26 : 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: DashboardStyle.inset,
          border: Border.all(color: color, width: small ? 1.4 : 2),
        ),
        child: liveHeading == null
            ? _arrow(heading)
            : ValueListenableBuilder<double?>(
                valueListenable: liveHeading!,
                builder: (context, value, _) => _arrow(value),
              ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: onTap == null
          ? Semantics(
              label: description,
              child: IgnorePointer(child: marker),
            )
          : Tooltip(
              message: description,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: marker,
                ),
              ),
            ),
    );
  }
}

/// Measures the ground distance along the current screen-horizontal axis.
class _MarsScaleBar extends StatelessWidget {
  const _MarsScaleBar({required this.scene, required this.view});

  static const width = 50.0;

  final MarsScene scene;
  final TerrainViewController view;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: view,
    builder: (context, _, child) {
      final center = scene.viewport.center(Offset.zero);
      const half = Offset(width / 2, 0);
      final start = scene.toGeographic(view.toScene(center - half));
      final end = scene.toGeographic(view.toScene(center + half));
      final meters = surfaceDistance(start, end, MarsProjection.radiusMeters);
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 7,
        children: [
          Container(width: width, height: 2, color: DashboardStyle.warm),
          Text(
            meters >= 1000
                ? '≈ ${(meters / 1000).toStringAsPrecision(2)} km'
                : '≈ ${meters < 100 ? meters.round() : (meters / 10).round() * 10} m',
            style: const TextStyle(color: DashboardStyle.text, fontSize: 11),
          ),
        ],
      );
    },
  );
}

/// Animates only the glyph, unwrapping angles along the shortest arc.
class RelativeMarkerArrow extends StatefulWidget {
  const RelativeMarkerArrow({
    super.key,
    required this.heading,
    required this.child,
  });

  final double? heading;
  final Widget child;

  @override
  State<RelativeMarkerArrow> createState() => _RelativeMarkerArrowState();
}

class _RelativeMarkerArrowState extends State<RelativeMarkerArrow> {
  late double _angle = widget.heading ?? 0;

  @override
  void didUpdateWidget(RelativeMarkerArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.heading case final next?) {
      _angle += signedTurn(next - _angle);
    }
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: widget.heading == null ? .55 : 1,
    child: AnimatedRotation(
      turns: _angle / 360,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: widget.child,
    ),
  );
}
