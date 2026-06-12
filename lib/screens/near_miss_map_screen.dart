import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'near_miss_event.dart';

// ════════════════════════════════════════════════════════════════════════════
// NearMissMapScreen
// ════════════════════════════════════════════════════════════════════════════

class NearMissMapScreen extends StatefulWidget {
  final NearMissEvent event;
  const NearMissMapScreen({super.key, required this.event});

  @override
  State<NearMissMapScreen> createState() => _NearMissMapScreenState();
}

class _NearMissMapScreenState extends State<NearMissMapScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _replayCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  int _replayIndex = 0;
  bool _isReplaying = false;
  bool _replayDone = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    final trackLen = widget.event.trackPoints.length;
    _replayCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: trackLen < 1 ? 1000 : trackLen * 80),
    )
      ..addListener(_onReplayTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() {
            _isReplaying = false;
            _replayDone = true;
          });
        }
      });
  }

  void _onReplayTick() {
    final total = widget.event.trackPoints.length;
    if (total == 0) return;
    final idx = (_replayCtrl.value * total).floor().clamp(0, total - 1);
    if (idx != _replayIndex) {
      setState(() => _replayIndex = idx);
      final pt = widget.event.trackPoints[idx];
      if (pt.position.latitude != 0) {
        _mapController.move(pt.position, _mapController.camera.zoom);
      }
    }
  }

  @override
  void dispose() {
    _replayCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _startReplay() {
    setState(() {
      _isReplaying = true;
      _replayDone = false;
      _replayIndex = 0;
    });
    _replayCtrl
      ..reset()
      ..forward();
  }

  void _pauseReplay() {
    if (_replayCtrl.isAnimating) {
      _replayCtrl.stop();
      setState(() => _isReplaying = false);
    } else {
      _replayCtrl.forward();
      setState(() => _isReplaying = true);
    }
  }

  void _resetReplay() {
    _replayCtrl.reset();
    setState(() {
      _isReplaying = false;
      _replayDone = false;
      _replayIndex = 0;
    });
  }

  // ── Colour helpers ────────────────────────────────────────────────────────

  static Color gForceColor(double g) {
    if (g > 3.5) return const Color(0xFFFF3B30);
    if (g > 2.5) return const Color(0xFFFF9F0A);
    if (g > 1.5) return const Color(0xFFFFD60A);
    return const Color(0xFF30D158);
  }

  Color get _severityColor => gForceColor(widget.event.peakGForce);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final points = widget.event.trackPoints;
    final hasGps = points.isNotEmpty && points.first.position.latitude != 0;
    final visiblePts = points.isEmpty
        ? <SensorPoint>[]
        : points.sublist(0, _replayIndex + 1);

    LatLng center = widget.event.location;
    if (hasGps) {
      double sumLat = 0, sumLng = 0;
      for (final p in points) {
        sumLat += p.position.latitude;
        sumLng += p.position.longitude;
      }
      center = LatLng(sumLat / points.length, sumLng / points.length);
    }

    final currentPoint = points.isNotEmpty ? points[_replayIndex] : null;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Stack(
          children: [
            // ── Map (full screen) ──────────────────────────────────────────
            hasGps
                ? FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.app',
                  retinaMode:
                  MediaQuery.of(context).devicePixelRatio > 1,
                ),
                if (visiblePts.length > 1)
                  PolylineLayer(
                      polylines: _coloredPolylines(visiblePts)),
                MarkerLayer(
                    markers: _buildMarkers(points, currentPoint)),
              ],
            )
                : _NoGpsPlaceholder(eventType: widget.event.typeLabel),

            // ── Top nav bar ────────────────────────────────────────────────
            _TopBar(
              event: widget.event,
              severityColor: _severityColor,
            ),

            // ── Live sensor strip ──────────────────────────────────────────
            if (currentPoint != null)
              Positioned(
                bottom: 210,
                left: 16,
                right: 16,
                child: _LiveDataStrip(point: currentPoint),
              ),

            // ── Replay panel ───────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BottomReplayPanel(
                event: widget.event,
                replayIndex: _replayIndex,
                isReplaying: _isReplaying,
                replayDone: _replayDone,
                severityColor: _severityColor,
                onStart: _startReplay,
                onPause: _pauseReplay,
                onReset: _resetReplay,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(
      List<SensorPoint> points, SensorPoint? current) {
    final markers = <Marker>[
      Marker(
        point: widget.event.location,
        width: 50,
        height: 50,
        child: _EventMarker(color: _severityColor, type: widget.event.type),
      ),
    ];
    if (points.isNotEmpty && points.first.position.latitude != 0) {
      markers.add(Marker(
        point: points.first.position,
        width: 20,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF30D158),
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ));
    }
    if (current != null && current.position.latitude != 0) {
      markers.add(Marker(
        point: current.position,
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0A84FF),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.5),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ));
    }
    return markers;
  }

  List<Polyline> _coloredPolylines(List<SensorPoint> pts) =>
      List.generate(
        pts.length - 1,
            (i) => Polyline(
          points: [pts[i].position, pts[i + 1].position],
          color: gForceColor(pts[i].gForce).withValues(alpha: 0.85),
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Small reusable widgets
// ════════════════════════════════════════════════════════════════════════════

// ── Top nav bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final NearMissEvent event;
  final Color severityColor;

  const _TopBar({
    required this.event,
    required this.severityColor,
  });

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0A0A0F).withValues(alpha: 0.95),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121F),
                      borderRadius: BorderRadius.circular(12),
                      border:
                      Border.all(color: const Color(0xFF1E1E35)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.typeLabel,
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text(_formatDate(event.timestamp),
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF4A5070))),
                    ],
                  ),
                ),
                _InlineBadge(
                  label: event.severityLabel,
                  color: severityColor,
                  letterSpacing: 0.8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final double letterSpacing;

  const _InlineBadge({
    required this.label,
    required this.color,
    this.icon,
    this.letterSpacing = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: icon != null ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: letterSpacing)),
        ],
      ),
    );
  }
}

// ── Event map marker ──────────────────────────────────────────────────────────

class _EventMarker extends StatelessWidget {
  final Color color;
  final NearMissType type;
  const _EventMarker({required this.color, required this.type});

  IconData get _icon => switch (type) {
    NearMissType.hardBraking => Icons.speed_outlined,
    NearMissType.sharpSwerve => Icons.swap_horiz_rounded,
    NearMissType.rapidAcceleration => Icons.flash_on_outlined,
    NearMissType.collision => Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 16),
        ],
      ),
      child: Icon(_icon, color: Colors.white, size: 24),
    );
  }
}

// ── Live sensor strip ─────────────────────────────────────────────────────────

class _LiveDataStrip extends StatelessWidget {
  final SensorPoint point;
  const _LiveDataStrip({required this.point});

  static Color _gColor(double g) =>
      _NearMissMapScreenState.gForceColor(g);

  @override
  Widget build(BuildContext context) {
    final g = point.gForce;
    final gyro = math.sqrt(point.gyroX * point.gyroX +
        point.gyroY * point.gyroY +
        point.gyroZ * point.gyroZ);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _DataChip(
              label: 'G-FORCE',
              value: '${g.toStringAsFixed(2)}g',
              color: _gColor(g)),
          _DataChip(
              label: 'SPEED',
              value: '${(point.speed * 3.6).toStringAsFixed(0)} km/h',
              color: const Color(0xFF0A84FF)),
          _DataChip(
              label: 'GYRO',
              value: '${gyro.toStringAsFixed(2)} r/s',
              color: const Color(0xFFBF5AF2)),
        ],
      ),
    );
  }
}

class _DataChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _DataChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9,
                color: const Color(0xFF4A5070),
                letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color)),
      ],
    );
  }
}

// ── Bottom replay panel ───────────────────────────────────────────────────────

class _BottomReplayPanel extends StatelessWidget {
  final NearMissEvent event;
  final int replayIndex;
  final bool isReplaying, replayDone;
  final Color severityColor;
  final VoidCallback onStart, onPause, onReset;

  const _BottomReplayPanel({
    required this.event,
    required this.replayIndex,
    required this.isReplaying,
    required this.replayDone,
    required this.severityColor,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final total = event.trackPoints.length;
    final progress = total > 0 ? replayIndex / total : 0.0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1E1E35))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _StatPill(
                label: 'Peak G',
                value: '${event.peakGForce.toStringAsFixed(2)}g',
                color: severityColor),
            const SizedBox(width: 8),
            _StatPill(
                label: 'Duration',
                value: '${event.duration.inSeconds}s',
                color: const Color(0xFF0A84FF)),
            const SizedBox(width: 8),
            _StatPill(
                label: 'Points',
                value: '$total',
                color: const Color(0xFFBF5AF2)),
          ]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('REPLAY',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFF4A5070),
                      letterSpacing: 1)),
              Text('${(progress * 100).toInt()}%',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: severityColor,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF1E1E35),
              valueColor: AlwaysStoppedAnimation<Color>(severityColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            GestureDetector(
              onTap: onReset,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF12121F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E1E35)),
                ),
                child: const Icon(Icons.replay_rounded,
                    color: Color(0xFF6B7494), size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: replayDone
                    ? onStart
                    : (isReplaying ? onPause : onStart),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      severityColor,
                      severityColor.withValues(alpha: 0.7),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          replayDone
                              ? Icons.replay_rounded
                              : (isReplaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          color: Colors.black,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          replayDone
                              ? 'Replay Again'
                              : (isReplaying ? 'Pause' : 'Play Replay'),
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 10, color: const Color(0xFF4A5070))),
        ]),
      ),
    );
  }
}

// ── No-GPS placeholder ────────────────────────────────────────────────────────

class _NoGpsPlaceholder extends StatelessWidget {
  final String eventType;
  const _NoGpsPlaceholder({required this.eventType});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0D0D1A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF9F0A).withValues(alpha: 0.12),
                border: Border.all(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.location_off_outlined,
                  color: Color(0xFFFF9F0A), size: 36),
            ),
            const SizedBox(height: 16),
            Text('No GPS Data',
                style: GoogleFonts.inter(
                    fontSize: 18,

                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              'Sensor data recorded — location unavailable\nfor this $eventType event.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF4A5070)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}