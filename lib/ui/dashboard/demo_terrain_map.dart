import 'package:flutter/material.dart';

import '../../dashboard/demo_navigation.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';

/// A renderer boundary for replacing the bundled backdrop with future tiles.
abstract class TerrainBackdrop extends StatelessWidget {
  /// Gives the renderer the same scene extent as the local overlays.
  const TerrainBackdrop({super.key});
}

/// Paints an unregistered orbital image underneath the demonstration grid.
class OrbitalPhotoBackdrop extends TerrainBackdrop {
  /// Loads a bundled official image without making a network request.
  const OrbitalPhotoBackdrop(this.asset, {super.key});

  final String asset;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
    alignment: const Alignment(.12, 0),
  );
}

/// Offers pinch, pan and destination selection on a north-up demo grid.
class DemoTerrainMap extends StatelessWidget {
  /// Composes the interchangeable terrain and local navigation layers.
  const DemoTerrainMap({
    super.key,
    required this.navigation,
    required this.view,
    required this.backdrop,
    required this.astronautInitials,
    required this.teammateInitials,
    required this.teammateName,
    required this.onSelect,
  });

  final DemoNavigation navigation;
  final TerrainViewController view;
  final TerrainBackdrop backdrop;
  final String astronautInitials;
  final String teammateInitials;
  final String teammateName;
  final void Function(Offset point, String label) onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          // A square world preserves heading and distance on any viewport.
          final side = viewport.shortestSide;
          final world = Rect.fromCenter(
            center: viewport.center(Offset.zero),
            width: side,
            height: side,
          );
          final config = navigation.map;
          final palette = Theme.of(context).textTheme;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                key: const ValueKey('demo-map-viewport'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final scene =
                      view.toScene(details.localPosition) - world.topLeft;
                  onSelect(scene / side, 'Map waypoint');
                },
                child: InteractiveViewer(
                  transformationController: view,
                  minScale: 1,
                  maxScale: TerrainViewController.maxZoom,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      backdrop,
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xA017171E),
                              Color(0x3827130A),
                              Color(0xA90B121E),
                            ],
                            stops: [0, .47, 1],
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _DemoGrid(
                          world: world,
                          navigation: navigation,
                        ),
                      ),
                      _marker(
                        world,
                        config.base,
                        'Habitat base',
                        Icons.home_filled,
                        DashboardStyle.text,
                        onTap: () => onSelect(config.base, 'Habitat base'),
                      ),
                      for (final landmark in config.landmarks)
                        _marker(
                          world,
                          landmark.position,
                          landmark.name,
                          Icons.terrain,
                          DashboardStyle.warm,
                          onTap: () =>
                              onSelect(landmark.position, landmark.name),
                          small: true,
                        ),
                      _marker(
                        world,
                        config.teammate,
                        teammateInitials,
                        Icons.person,
                        DashboardStyle.cyan,
                        description: 'Select $teammateName on map',
                        onTap: () => onSelect(config.teammate, teammateName),
                      ),
                      for (final ping in navigation.pings)
                        _pingMarker(world, ping),
                      if (navigation.target case final target?)
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
                        '$astronautInitials · YOU',
                        navigation.sos
                            ? Icons.warning_amber_rounded
                            : Icons.navigation_rounded,
                        navigation.sos
                            ? DashboardStyle.danger
                            : DashboardStyle.cyan,
                        above: true,
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 15,
                top: 15,
                child: _MapChip(
                  text: 'DEMO GRID · ORBITAL IMAGERY',
                  icon: Icons.layers_outlined,
                  color: DashboardStyle.warm,
                ),
              ),
              Positioned(
                right: 14,
                top: 14,
                child: const _MapChip(
                  text: 'N',
                  icon: Icons.navigation_rounded,
                ),
              ),
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
                          zoom < TerrainViewController.maxZoom
                              ? () => view.zoomBy(1.4, viewport)
                              : null,
                        ),
                        _mapButton(
                          'Zoom out',
                          Icons.remove,
                          zoom > 1
                              ? () => view.zoomBy(1 / 1.4, viewport)
                              : null,
                        ),
                        _mapButton(
                          'Reset view',
                          Icons.center_focus_strong,
                          view.reset,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                left: 14,
                right: 82,
                bottom: 15,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: DecoratedBox(
                    decoration: DashboardStyle.surface(
                      color: const Color(0xEE0B1320),
                      radius: 10,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      child: Text(
                        config.credit,
                        style: palette.bodySmall?.copyWith(
                          color: DashboardStyle.text,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Positions a marker in the same square scene as the painted route.
  Widget _marker(
    Rect world,
    Offset local,
    String label,
    IconData icon,
    Color color, {
    String? description,
    VoidCallback? onTap,
    bool small = false,
    bool above = false,
  }) {
    final center = _project(world, local);
    final buttonSize = small && onTap == null ? 30.0 : 48.0;
    final labelWidth = small ? 110.0 : 146.0;
    final chip = _MarkerChip(
      icon: icon,
      color: color,
      size: buttonSize,
      description: description ?? label,
      onTap: onTap,
      small: small,
    );
    return Stack(
      children: [
        Positioned(
          left: center.dx - buttonSize / 2,
          top: center.dy - buttonSize / 2,
          child: chip,
        ),
        if (!small)
          Positioned(
            width: labelWidth,
            left: center.dx - labelWidth / 2,
            top: above ? center.dy - 51 : center.dy + 22,
            child: IgnorePointer(
              child: Align(
                child: _MapChip(text: label, color: color, compact: true),
              ),
            ),
          ),
      ],
    );
  }

  /// Keeps annotations visually distinct when they share a navigation target.
  Widget _pingMarker(Rect world, DemoPing ping) {
    final point = _project(world, ping.position);
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
    return Positioned(
      key: ValueKey((ping.type, ping.position)),
      left: point.dx + shift.dx - 15,
      top: point.dy + shift.dy - 15,
      child: IgnorePointer(
        child: _MarkerChip(
          icon: icon,
          color: color,
          size: 30,
          description: ping.type.label,
          small: true,
        ),
      ),
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
  _DemoGrid({required this.world, required DemoNavigation navigation})
    : base = navigation.map.base,
      radius = navigation.map.radius,
      position = navigation.position,
      target = navigation.target,
      emergency = navigation.sos;

  final Rect world;
  final Offset base;
  final double radius;
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
    final center = _project(world, base);
    final extent = radius * world.width;
    canvas.drawCircle(center, extent, Paint()..color = const Color(0x22FF632E));
    canvas.drawCircle(
      center,
      extent,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xA5FFB179),
    );

    final from = _project(world, position);
    if (target case final destination?) {
      final vector = _project(world, destination) - from;
      final length = vector.distance;
      final line = Paint()
        ..color = emergency ? DashboardStyle.danger : DashboardStyle.warm
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3;
      if (length > 0) {
        final unit = vector / length;
        for (double segment = 0; segment < length; segment += 16) {
          canvas.drawLine(
            from + unit * segment,
            from + unit * (segment + 9).clamp(0, length).toDouble(),
            line,
          );
        }
      }
    }
    if (emergency) {
      canvas.drawCircle(from, 43, Paint()..color = const Color(0x66FF4242));
      canvas.drawCircle(
        from,
        43,
        Paint()
          ..color = DashboardStyle.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_DemoGrid oldDelegate) =>
      world != oldDelegate.world ||
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
  });

  final IconData icon;
  final Color color;
  final double size;
  final String description;
  final VoidCallback? onTap;
  final bool small;

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
        child: Icon(icon, color: color, size: small ? 15 : 23),
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
