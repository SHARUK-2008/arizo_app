import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'near_miss_service.dart';
import 'near_miss_event.dart';
import 'near_miss_map_screen.dart';

class NearMissScreen extends StatefulWidget {
  const NearMissScreen({super.key});

  @override
  State<NearMissScreen> createState() => _NearMissScreenState();
}

class _NearMissScreenState extends State<NearMissScreen>
    with TickerProviderStateMixin {
  final NearMissService _service = NearMissService();

  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  final List<NearMissEvent> _events = [];
  SensorPoint? _latestPoint;

  // Live G-force history for mini chart (last 60 samples)
  final List<double> _gHistory = List.filled(60, 0.0);

  StreamSubscription? _eventSub;
  StreamSubscription? _pointSub;
  StreamSubscription? _recSub;

  bool _isRecording = false;
  int  _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    _eventSub = _service.eventStream.listen((event) {
      setState(() => _events.insert(0, event));
      _showEventSnackbar(event);
    });

    _pointSub = _service.pointStream.listen((pt) {
      setState(() {
        _latestPoint = pt;
        _gHistory.removeAt(0);
        _gHistory.add(pt.gForce);
      });
    });

    _recSub = _service.recordingStream.listen((rec) {
      setState(() => _isRecording = rec);
    });
  }

  @override
  void dispose() {
    _service.dispose();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _eventSub?.cancel();
    _pointSub?.cancel();
    _recSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _toggleRecording() async {
    if (_isRecording) {
      _service.stopRecording();
      _timer?.cancel();
      setState(() => _elapsedSeconds = 0);
    } else {
      await _service.startRecording();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });
    }
  }

  void _showEventSnackbar(NearMissEvent event) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF12121F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _severityColor(event.peakGForce).withValues(alpha: 0.15),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: _severityColor(event.peakGForce), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(event.typeLabel,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  Text('${event.peakGForce.toStringAsFixed(2)}g peak  •  ${event.severityLabel}',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF6B7494))),
                ],
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Color _severityColor(double g) {
    if (g > 3.5) return const Color(0xFFFF3B30);
    if (g > 2.5) return const Color(0xFFFF9F0A);
    if (g > 1.5) return const Color(0xFFFFD60A);
    return const Color(0xFF30D158);
  }

  String _formatElapsed(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: CustomScrollView(
          slivers: [
            // ── App bar ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF12121F),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xFF1E1E35)),
                          ),
                          child: const Icon(Icons.arrow_back_ios_rounded,
                              color: Colors.white70, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Near-Miss',
                                style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.4)),
                            Text('IMU Sensor Fusion + Map Reconstruction',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF4A5070))),
                          ],
                        ),
                      ),
                      if (_isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFFF3B30).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (_, __) => Container(
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.lerp(
                                      const Color(0xFFFF3B30),
                                      const Color(0xFFFF9F0A),
                                      _pulseCtrl.value,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(_formatElapsed(_elapsedSeconds),
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFFF3B30))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Live sensor card ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _LiveSensorCard(
                  point: _latestPoint,
                  gHistory: _gHistory,
                  isRecording: _isRecording,
                  pulseCtrl: _pulseCtrl,
                  severityColor: _severityColor,
                ),
              ),
            ),

            // ── Record button ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _RecordButton(
                  isRecording: _isRecording,
                  onTap: _toggleRecording,
                ),
              ),
            ),

            // ── How it works ──────────────────────────────────────────────────
            if (!_isRecording && _events.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _HowItWorks(),
                ),
              ),

            // ── Events list ───────────────────────────────────────────────────
            if (_events.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('DETECTED EVENTS',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3A3A55),
                              letterSpacing: 1.4)),
                      Text('${_events.length} total',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: const Color(0xFF3A3A55))),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, i) => _EventCard(
                      event: _events[i],
                      severityColor: _severityColor,
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, anim, __) =>
                              NearMissMapScreen(event: _events[i]),
                          transitionsBuilder: (_, anim, __, child) =>
                              SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                    parent: anim,
                                    curve: Curves.easeOutCubic)),
                                child: child,
                              ),
                          transitionDuration: const Duration(milliseconds: 400),
                        ),
                      ),
                    ),
                    childCount: _events.length,
                  ),
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ],
        ),
      ),
    );
  }
}

// ─── Live Sensor Card ─────────────────────────────────────────────────────────

class _LiveSensorCard extends StatelessWidget {
  final SensorPoint? point;
  final List<double> gHistory;
  final bool isRecording;
  final AnimationController pulseCtrl;
  final Color Function(double) severityColor;

  const _LiveSensorCard({
    required this.point,
    required this.gHistory,
    required this.isRecording,
    required this.pulseCtrl,
    required this.severityColor,
  });

  @override
  Widget build(BuildContext context) {
    final g = point?.gForce ?? 0.0;
    final speed = ((point?.speed ?? 0) * 3.6);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecording
              ? const Color(0xFFFF3B30).withValues(alpha: 0.3)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        children: [
          // G-force display
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('G-FORCE',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF4A5070),
                            letterSpacing: 1)),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: g.toStringAsFixed(2),
                            style: GoogleFonts.inter(
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              color: isRecording ? severityColor(g) : const Color(0xFF2A2A45),
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: ' g',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              color: const Color(0xFF4A5070),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${speed.toStringAsFixed(0)} km/h',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF6B7494))),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Mini waveform chart
              SizedBox(
                width: 140,
                height: 60,
                child: CustomPaint(
                  painter: _GForcePainter(
                    values: gHistory,
                    color: isRecording ? severityColor(g) : const Color(0xFF2A2A45),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Axis readings
          Row(
            children: [
              _AxisChip(label: 'AX', value: point?.accelX ?? 0, unit: 'm/s²'),
              const SizedBox(width: 6),
              _AxisChip(label: 'AY', value: point?.accelY ?? 0, unit: 'm/s²'),
              const SizedBox(width: 6),
              _AxisChip(label: 'AZ', value: point?.accelZ ?? 0, unit: 'm/s²'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AxisChip extends StatelessWidget {
  final String label, unit;
  final double value;

  const _AxisChip({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Column(
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 9, color: const Color(0xFF4A5070), letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(value.toStringAsFixed(1),
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8EAF6))),
          ],
        ),
      ),
    );
  }
}

// ─── G-Force Waveform Painter ─────────────────────────────────────────────────

class _GForcePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _GForcePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final maxVal = 4.0; // max g displayed
    final path  = Path();
    final fill  = Path();
    final step  = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxVal).clamp(0, 1) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo((values.length - 1) * step, size.height);
    fill.close();

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GForcePainter old) =>
      old.values != values || old.color != color;
}

// ─── Record Button ────────────────────────────────────────────────────────────

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const _RecordButton({required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        decoration: BoxDecoration(
          gradient: isRecording
              ? const LinearGradient(
              colors: [Color(0xFFFF3B30), Color(0xFFFF6B30)])
              : const LinearGradient(
              colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (isRecording
                  ? const Color(0xFFFF3B30)
                  : const Color(0xFFFF9F0A))
                  .withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
                color: Colors.black,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isRecording ? 'Stop Recording' : 'Start Recording',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Event Card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final NearMissEvent event;
  final Color Function(double) severityColor;
  final VoidCallback onTap;

  const _EventCard({
    required this.event,
    required this.severityColor,
    required this.onTap,
  });

  IconData get _icon {
    switch (event.type) {
      case NearMissType.hardBraking:       return Icons.speed_outlined;
      case NearMissType.sharpSwerve:       return Icons.swap_horiz_rounded;
      case NearMissType.rapidAcceleration: return Icons.flash_on_outlined;
      case NearMissType.collision:         return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = severityColor(event.peakGForce);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(_icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.typeLabel,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE8EAF6))),
                  const SizedBox(height: 3),
                  Text(
                      '${event.peakGForce.toStringAsFixed(2)}g peak  •  '
                          '${event.duration.inSeconds}s  •  ${event.severityLabel}',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: const Color(0xFF4A5070))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, color: color, size: 13),
                  const SizedBox(width: 4),
                  Text('Replay',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── How It Works ─────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.sensors, 'Accelerometer + Gyroscope', 'Detects sudden force changes in 3 axes at 10 Hz'),
      (Icons.location_on_outlined, 'GPS Track Recording', 'Logs your path with speed, lat/lng every 100ms'),
      (Icons.warning_amber_rounded, 'Automatic Event Detection', 'Triggers on hard braking, swerves, rapid accel, or collision'),
      (Icons.map_outlined, 'Map Replay', 'Color-coded route on OpenStreetMap showing g-force intensity'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOW IT WORKS',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3A3A55),
                  letterSpacing: 1.4)),
          const SizedBox(height: 14),
          ...steps.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF9F0A).withValues(alpha: 0.25)),
                  ),
                  child: Icon(s.$1, color: const Color(0xFFFF9F0A), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$2,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFE8EAF6))),
                      const SizedBox(height: 2),
                      Text(s.$3,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: const Color(0xFF4A5070))),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}