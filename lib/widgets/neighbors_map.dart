import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/map_tile_cache_service.dart';
import '../theme/mesh_theme.dart';
import 'empty_state.dart';
import 'telemetry_location_map.dart';

/// A repeater neighbor that can be drawn on the map.
class NeighborMapPoint {
  /// Index of the neighbor in the parsed neighbors list.
  final int index;
  final Contact contact;
  final double snr;
  final int lastHeardSeconds;

  const NeighborMapPoint({
    required this.index,
    required this.contact,
    required this.snr,
    required this.lastHeardSeconds,
  });

  LatLng get position => LatLng(contact.latitude!, contact.longitude!);
}

/// Keeps only neighbors that resolve to a known contact with GPS coordinates.
/// Neighbors that are unknown or have no position cannot be placed on a map.
List<NeighborMapPoint> buildNeighborMapPoints(
  List<Map<String, dynamic>> parsedNeighbors,
) {
  final points = <NeighborMapPoint>[];
  for (var i = 0; i < parsedNeighbors.length; i++) {
    final data = parsedNeighbors[i];
    final contact = data['contact'] as Contact?;
    if (contact == null || !contact.hasLocation) continue;
    points.add(
      NeighborMapPoint(
        index: i,
        contact: contact,
        snr: data['snr'] as double,
        lastHeardSeconds: data['lastHeard'] as int,
      ),
    );
  }
  return points;
}

/// Map of a repeater and its neighbors, with links colored by SNR.
class NeighborsMap extends StatefulWidget {
  final Contact repeater;
  final List<NeighborMapPoint> points;
  final int totalNeighbors;

  /// Neighbor (by parsed-list index) to select and center on when opened.
  final int? focusIndex;
  final String Function(int seconds) formatHeard;

  const NeighborsMap({
    super.key,
    required this.repeater,
    required this.points,
    required this.totalNeighbors,
    required this.formatHeard,
    this.focusIndex,
  });

  @override
  State<NeighborsMap> createState() => _NeighborsMapState();
}

class _NeighborsMapState extends State<NeighborsMap> {
  static const double _minZoom = 2.0;
  static const double _maxZoom = 18.0;
  static const double _focusZoom = 15.0;

  final MapController _mapController = MapController();
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.focusIndex;
  }

  @override
  void didUpdateWidget(covariant NeighborsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusIndex != null &&
        widget.focusIndex != oldWidget.focusIndex) {
      _selectedIndex = widget.focusIndex;
      final point = _selectedPoint;
      if (point != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(point.position, _focusZoom);
        });
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  bool get _repeaterHasLocation => widget.repeater.hasLocation;

  LatLng? get _repeaterPosition => _repeaterHasLocation
      ? LatLng(widget.repeater.latitude!, widget.repeater.longitude!)
      : null;

  NeighborMapPoint? get _selectedPoint {
    final selected = _selectedIndex;
    if (selected == null) return null;
    for (final p in widget.points) {
      if (p.index == selected) return p;
    }
    return null;
  }

  List<LatLng> get _allPositions => [
    ?_repeaterPosition,
    ...widget.points.map((p) => p.position),
  ];

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(
      camera.center,
      (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble(),
    );
  }

  void _fitAll() {
    final positions = _allPositions;
    if (positions.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: positions,
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ),
    );
  }

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final positions = _allPositions;
    if (positions.isEmpty) {
      return EmptyState(
        icon: Icons.location_off_outlined,
        title: l10n.neighbors_mapNothingToShow,
      );
    }

    final tileCache = context.read<MapTileCacheService>();
    final repeaterPos = _repeaterPosition;
    final selected = _selectedPoint;
    final notOnMap = widget.totalNeighbors - widget.points.length;
    final focus = selected?.position;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: focus ?? positions.first,
            initialZoom: focus != null ? _focusZoom : 14,
            initialCameraFit: focus == null
                ? CameraFit.coordinates(
                    coordinates: positions,
                    padding: const EdgeInsets.all(56),
                    maxZoom: 16,
                  )
                : null,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onTap: (_, _) => setState(() => _selectedIndex = null),
            interactionOptions: InteractionOptions(
              flags: ~InteractiveFlag.rotate,
              scrollWheelVelocity: _isDesktop ? 0.012 : 0.005,
              cursorKeyboardRotationOptions:
                  CursorKeyboardRotationOptions.disabled(),
            ),
          ),
          children: [
            tileCache.buildTileLayer(context),
            if (repeaterPos != null)
              PolylineLayer(
                polylines: [
                  for (final p in widget.points)
                    Polyline(
                      points: [repeaterPos, p.position],
                      strokeWidth: p.index == _selectedIndex ? 6 : 4,
                      color: MeshTheme.snrColor(
                        p.snr,
                        blocked: false,
                      ).withValues(alpha: 0.9),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final p in widget.points) _neighborMarker(p),
                if (repeaterPos != null) _repeaterMarker(repeaterPos),
              ],
            ),
          ],
        ),
        Positioned(
          left: 8,
          top: 8,
          child: Column(
            children: [
              MapControlButton(
                icon: Icons.add,
                tooltip: l10n.map_zoomIn,
                onPressed: () => _zoomBy(1),
              ),
              const SizedBox(height: 6),
              MapControlButton(
                icon: Icons.remove,
                tooltip: l10n.map_zoomOut,
                onPressed: () => _zoomBy(-1),
              ),
              const SizedBox(height: 6),
              MapControlButton(
                icon: Icons.fit_screen,
                tooltip: l10n.map_centerMap,
                onPressed: _fitAll,
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          left: 64,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (notOnMap > 0)
                _InfoChip(
                  icon: Icons.location_off_outlined,
                  text: l10n.neighbors_notOnMap(
                    notOnMap,
                    widget.totalNeighbors,
                  ),
                ),
              if (!_repeaterHasLocation) ...[
                const SizedBox(height: 6),
                _InfoChip(
                  icon: Icons.link_off,
                  text: l10n.neighbors_repeaterNoLocation,
                ),
              ],
            ],
          ),
        ),
        if (selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _DetailsCard(
              point: selected,
              heard: l10n.neighbors_heardAgo(
                widget.formatHeard(selected.lastHeardSeconds),
              ),
              onClose: () => setState(() => _selectedIndex = null),
            ),
          ),
      ],
    );
  }

  Marker _repeaterMarker(LatLng position) {
    return Marker(
      point: position,
      width: 44,
      height: 44,
      child: IgnorePointer(
        child: MapMarkerBubble(
          color: MeshPalette.blue,
          icon: Icons.cell_tower,
          size: 24,
        ),
      ),
    );
  }

  Marker _neighborMarker(NeighborMapPoint p) {
    final isSelected = p.index == _selectedIndex;
    final size = isSelected ? 42.0 : 34.0;
    return Marker(
      point: p.position,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedIndex = p.index),
        child: MapMarkerBubble(
          color: MeshTheme.snrColor(p.snr, blocked: false),
          icon: p.contact.type == advTypeRepeater
              ? Icons.router
              : Icons.device_unknown,
          size: isSelected ? 22 : 18,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final NeighborMapPoint point;
  final String heard;
  final VoidCallback onClose;

  const _DetailsCard({
    required this.point,
    required this.heard,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snrColor = MeshTheme.snrColor(point.snr, blocked: false);
    return Material(
      color: scheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    point.contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    heard,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${point.snr.toStringAsFixed(1)} dB',
              style: MeshTheme.mono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: snrColor,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
