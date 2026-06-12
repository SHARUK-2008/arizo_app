import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/bluetooth_hazard_service.dart';
import 'chat_screen_bt.dart';

class HazardScreen extends StatefulWidget {
  const HazardScreen({super.key});

  @override
  State<HazardScreen> createState() => _HazardScreenState();
}

class _HazardScreenState extends State<HazardScreen>
    with TickerProviderStateMixin {
  late BluetoothHazardService _service;
  late AnimationController _radarController;
  late AnimationController _pulseController;

  NetworkStatus _status = NetworkStatus.idle;
  List<HazardAlert> _alerts = [];
  Set<String> _peers = {};
  bool _isStarted = false;

  StreamSubscription? _alertSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _peersSub;

  @override
  void initState() {
    super.initState();
    _service = BluetoothHazardService();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _statusSub?.cancel();
    _peersSub?.cancel();
    _service.stop();
    _radarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Start mesh ─────────────────────────────────────────────────────────────
  // nearby_connections handles discovery automatically — no device picker needed
  void _handleStartMesh() {
    HapticFeedback.mediumImpact();
    setState(() => _isStarted = true);
    _service.start();

    _alertSub = _service.alertStream.listen((alerts) {
      if (!mounted) return;
      final prevCount = _alerts.length;
      setState(() => _alerts = alerts);
      if (alerts.length > prevCount) HapticFeedback.heavyImpact();
    });

    _statusSub = _service.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });

    _peersSub = _service.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _peers = peers);
    });
  }

  void _stopMesh() {
    HapticFeedback.mediumImpact();
    _alertSub?.cancel();
    _statusSub?.cancel();
    _peersSub?.cancel();
    _service.stop();
    setState(() {
      _isStarted = false;
      _status = NetworkStatus.idle;
      _alerts = [];
      _peers = {};
    });
  }

  void _reportHazard(HazardType type) {
    HapticFeedback.heavyImpact();
    _service.reportHazard(type);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.surfaceDark2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Text(type.emoji,
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(
              '${type.label} reported & broadcast via mesh',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark1,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppTheme.borderDark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report a Hazard',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Alert broadcasts to all nearby devices automatically',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              children: HazardType.values.map((type) {
                return GestureDetector(
                  onTap: () => _reportHazard(type),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _severityColor(type.severity)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _severityColor(type.severity)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(type.emoji,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(height: 4),
                        Text(
                          type.label,
                          style: TextStyle(
                            color: _severityColor(type.severity),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _severityColor(int severity) {
    switch (severity) {
      case 1:  return AppTheme.accentGreen;
      case 2:  return AppTheme.accentAmber;
      default: return AppTheme.accentRed;
    }
  }

  Color _alertColor(HazardAlert alert) =>
      _severityColor(alert.type.severity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildNetworkStatus(),
                    const SizedBox(height: 16),
                    _buildRadarView(),
                    const SizedBox(height: 20),
                    _buildPeersRow(),
                    const SizedBox(height: 20),
                    _buildAlertsSection(),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppTheme.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mesh Hazard Alerts',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                Text('Nearby devices via Bluetooth / WiFi Direct',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(service: _service),
              ),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppTheme.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          if (_status.isActive)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.accentGreen
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(
                            alpha: 0.5 + 0.5 * _pulseController.value),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_peers.length} PEERS',
                      style: const TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNetworkStatus() {
    if (!_isStarted) return const SizedBox.shrink();

    final isActive   = _status.isActive;
    final isStarting = _status == NetworkStatus.starting;
    final Color color;
    if (isActive) {
      color = AppTheme.accentGreen;
    } else if (isStarting) {
      color = AppTheme.accentAmber;
    } else {
      color = AppTheme.accentRed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isActive
                ? Icons.bluetooth_connected
                : Icons.bluetooth_searching,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_status.label,
                style: TextStyle(color: color, fontSize: 12)),
          ),
          Text(
            'ID: ${_service.myId}',
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarView() {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(4, (i) {
            final radius = (i + 1) * 30.0;
            return Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.borderDark, width: 0.5),
              ),
            );
          }),
          if (_isStarted)
            AnimatedBuilder(
              animation: _radarController,
              builder: (_, __) => CustomPaint(
                size: const Size(240, 240),
                painter: _RadarSweepPainter(
                  angle: _radarController.value * 2 * pi,
                  color: const Color(0xFF2979FF),
                ),
              ),
            ),
          ..._alerts.take(8).map((alert) {
            final angle = atan2(
              alert.latitude - _service.currentLat,
              alert.longitude - _service.currentLng,
            );
            final dist =
                (alert.distanceMeters / 2000).clamp(0.0, 1.0) * 110;
            return Transform.translate(
              offset: Offset(dist * cos(angle), -dist * sin(angle)),
              child: _HazardDot(
                  alert: alert, color: _alertColor(alert)),
            );
          }),
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppTheme.primaryCyan,
              shape: BoxShape.circle,
            ),
          ),
          if (!_isStarted)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgDark.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_searching,
                        color: AppTheme.textTertiary, size: 40),
                    SizedBox(height: 10),
                    Text(
                      'Tap Start to activate mesh\nNo pairing needed',
                      style: TextStyle(
                          color: AppTheme.textTertiary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeersRow() {
    if (!_status.isActive || _peers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected,
              color: AppTheme.primaryBlue, size: 18),
          const SizedBox(width: 10),
          const Text('Connected Devices',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          ..._peers.take(4).map((id) => Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color:
                  AppTheme.primaryBlue.withValues(alpha: 0.3)),
            ),
            child: Text(
              id,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Active Alerts',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_alerts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_alerts.length}',
                  style: const TextStyle(
                      color: AppTheme.accentRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_alerts.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppTheme.accentGreen, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    _status.isActive
                        ? 'No hazards nearby. Road is clear!'
                        : 'Connect to receive hazard alerts',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._alerts.map((alert) => _AlertCard(
            alert: alert,
            color: _alertColor(alert),
            onDismiss: () => _service.removeAlert(alert.id),
          )),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _isStarted ? _stopMesh : _handleStartMesh,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: _isStarted
                      ? LinearGradient(colors: [
                    AppTheme.accentRed,
                    AppTheme.accentRed.withValues(alpha: 0.8),
                  ])
                      : const LinearGradient(
                    colors: [
                      Color(0xFF2979FF),
                      Color(0xFF651FFF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isStarted
                          ? Icons.bluetooth_disabled
                          : Icons.bluetooth,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isStarted
                          ? 'Disconnect'
                          : 'Start Mesh',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_status.isActive) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _showReportSheet,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color:
                      AppTheme.accentAmber.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.add_alert_outlined,
                    color: AppTheme.accentAmber, size: 24),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Alert Card ─────────────────────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final HazardAlert alert;
  final Color color;
  final VoidCallback onDismiss;

  const _AlertCard({
    required this.alert,
    required this.color,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(alert.type.emoji,
                  style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(alert.type.label,
                        style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (alert.isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded,
                          color: AppTheme.primaryCyan, size: 14),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${alert.distanceLabel} away · ${alert.timeAgo}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  'From ${alert.reportedBy} · ${alert.verificationCount} reports',
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded,
                color: AppTheme.textTertiary, size: 18),
          ),
        ],
      ),
    );
  }
}

// ── Hazard Dot ─────────────────────────────────────────────────────────────────
class _HazardDot extends StatelessWidget {
  final HazardAlert alert;
  final Color color;

  const _HazardDot({required this.alert, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(alert.type.emoji,
            style: const TextStyle(fontSize: 8)),
      ),
    );
  }
}

// ── Radar Sweep Painter ────────────────────────────────────────────────────────
class _RadarSweepPainter extends CustomPainter {
  final double angle;
  final Color color;

  _RadarSweepPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - 1.2,
        endAngle: angle,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.3),
        ],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      center,
      Offset(center.dx + radius * cos(angle),
          center.dy + radius * sin(angle)),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_RadarSweepPainter old) => old.angle != angle;
}