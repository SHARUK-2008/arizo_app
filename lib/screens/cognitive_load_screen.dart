import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/cognitive_load_service.dart';

class CognitiveLoadScreen extends StatefulWidget {
  const CognitiveLoadScreen({super.key});

  @override
  State<CognitiveLoadScreen> createState() => _CognitiveLoadScreenState();
}

class _CognitiveLoadScreenState extends State<CognitiveLoadScreen>
    with TickerProviderStateMixin {
  late CognitiveLoadService _service;

  // Animations
  late AnimationController _scanController;
  late AnimationController _fadeController;
  late AnimationController _alertController;
  late AnimationController _sleepFlashController;
  late AnimationController _warningPulseController;

  late Animation<double> _alertAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _sleepFlashAnimation;
  late Animation<double> _warningPulseAnimation;

  CognitiveLoadData _data = CognitiveLoadData.initial();
  bool _isActive = false;
  bool _showHighLoadAlert = false;
  final List<double> _loadHistory = [];

  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _service = CognitiveLoadService();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _alertController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _alertAnimation =
        CurvedAnimation(parent: _alertController, curve: Curves.elasticOut);

    // Red full-screen flash for sleep
    _sleepFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _sleepFlashAnimation = Tween<double>(begin: 0.0, end: 0.55).animate(
      CurvedAnimation(parent: _sleepFlashController, curve: Curves.easeInOut),
    );

    // Orange pulse for warning
    _warningPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _warningPulseAnimation = Tween<double>(begin: 0.0, end: 0.3).animate(
      CurvedAnimation(
          parent: _warningPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _service.stop();
    _scanController.dispose();
    _fadeController.dispose();
    _alertController.dispose();
    _sleepFlashController.dispose();
    _warningPulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleMonitoring() async {
    HapticFeedback.mediumImpact();
    if (_isActive) {
      _service.stop();
      _fadeController.reverse();
      setState(() {
        _isActive = false;
        _cameraController = null;
        _data = CognitiveLoadData.initial();
        _loadHistory.clear();
      });
    } else {
      final controller = await _service.start((data) {
        if (!mounted) return;
        setState(() {
          _data = data;
          _loadHistory.add(data.loadPercentage);
          if (_loadHistory.length > 40) _loadHistory.removeAt(0);

          // High cognitive load banner (non-sleep)
          if (data.loadPercentage > 75 &&
              data.drowsinessLevel != DrowsinessLevel.sleeping &&
              !_showHighLoadAlert) {
            _showHighLoadAlert = true;
            _alertController.forward(from: 0);
            _scheduleAlertDismiss();
          }
        });
      });

      if (mounted) {
        setState(() {
          _isActive = true;
          _cameraController = controller;
        });
        _fadeController.forward();
      }
    }
  }

  void _scheduleAlertDismiss() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _alertController.reverse();
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _showHighLoadAlert = false);
        });
      }
    });
  }

  Color get _loadColor {
    switch (_data.drowsinessLevel) {
      case DrowsinessLevel.sleeping:
        return const Color(0xFFFF1744);
      case DrowsinessLevel.warning:
        return const Color(0xFFFF6D00);
      case DrowsinessLevel.alert:
        final pct = _data.loadPercentage;
        if (pct < 40) return const Color(0xFF00E5C3);
        if (pct < 65) return const Color(0xFFFFB547);
        return const Color(0xFFFF4757);
    }
  }

  String get _loadLabel {
    switch (_data.drowsinessLevel) {
      case DrowsinessLevel.sleeping:
        return 'SLEEPING!';
      case DrowsinessLevel.warning:
        return 'DROWSY';
      case DrowsinessLevel.alert:
        final pct = _data.loadPercentage;
        if (pct < 40) return 'FOCUSED';
        if (pct < 65) return 'MODERATE';
        if (pct < 80) return 'HIGH LOAD';
        return 'CRITICAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSleeping = _data.drowsinessLevel == DrowsinessLevel.sleeping;
    final isWarning = _data.drowsinessLevel == DrowsinessLevel.warning;

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: Stack(
            children: [
              // ── Main content ──────────────────────────────────────────────
              Column(
                children: [
                  _buildTopBar(context),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          _buildCameraAndGauge(),
                          const SizedBox(height: 16),
                          // Eye-closed progress bar (only when active)
                          if (_isActive) _buildEyeClosureBar(),
                          if (_isActive) const SizedBox(height: 16),
                          _buildMetricsRow(),
                          const SizedBox(height: 18),
                          _buildHistoryChart(),
                          const SizedBox(height: 18),
                          _buildInsightsCard(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── Control bar floating at bottom ────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildControlBar(),
              ),

              // ── WARNING overlay (eyes closed 1.5–3s) ─────────────────────
              if (_isActive && isWarning)
                AnimatedBuilder(
                  animation: _warningPulseAnimation,
                  builder: (context, child) {
                    return IgnorePointer(
                      child: Container(
                        color: const Color(0xFFFF6D00)
                            .withOpacity(_warningPulseAnimation.value),
                      ),
                    );
                  },
                ),

              // ── SLEEPING full-screen red flash ────────────────────────────
              if (_isActive && isSleeping)
                AnimatedBuilder(
                  animation: _sleepFlashAnimation,
                  builder: (context, child) {
                    return IgnorePointer(
                      child: Container(
                        color: const Color(0xFFFF1744)
                            .withOpacity(_sleepFlashAnimation.value),
                      ),
                    );
                  },
                ),

              // ── SLEEP ALARM banner ────────────────────────────────────────
              if (_isActive && isSleeping)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _buildSleepAlarmCard(),
                    ),
                  ),
                ),

              // ── High cognitive load alert (non-sleep) ─────────────────────
              if (_showHighLoadAlert && !isSleeping)
                Positioned(
                  top: 80,
                  left: 16,
                  right: 16,
                  child: ScaleTransition(
                    scale: _alertAnimation,
                    child: _buildAlertBanner(),
                  ),
                ),

              // ── Drowsy warning toast ──────────────────────────────────────
              if (_isActive && isWarning)
                Positioned(
                  top: 80,
                  left: 16,
                  right: 16,
                  child: _buildDrowsyWarningBanner(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Eye Closure Progress Bar ─────────────────────────────────────────────
  Widget _buildEyeClosureBar() {
    final secs = _data.eyeClosedSeconds;
    final progress = (secs / 3.5).clamp(0.0, 1.0); // fills at 3.5s
    final barColor = secs >= 3.0
        ? const Color(0xFFFF1744)
        : secs >= 1.5
        ? const Color(0xFFFF6D00)
        : const Color(0xFF00E5C3);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: secs > 0 ? barColor.withOpacity(0.4) : const Color(0xFF1A2436),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                secs >= 3.0
                    ? Icons.bedtime_rounded
                    : secs >= 1.5
                    ? Icons.warning_amber_rounded
                    : Icons.visibility_outlined,
                color: barColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                secs >= 3.0
                    ? 'SLEEP DETECTED!'
                    : secs >= 1.5
                    ? 'Drowsy Warning'
                    : 'Eye State',
                style: TextStyle(
                  color: barColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                secs > 0 ? '${secs.toStringAsFixed(1)}s closed' : 'Eyes Open',
                style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF1A2436),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0s', style: _tickStyle),
              Text('1.5s ⚠️', style: _tickStyle),
              Text('3s 🚨', style: _tickStyle),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle get _tickStyle => const TextStyle(
    color: Color(0xFF2D3F55),
    fontSize: 9,
  );

  // ─── Sleep Alarm Card (center screen) ────────────────────────────────────
  Widget _buildSleepAlarmCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0509),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFF1744), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF1744).withOpacity(0.5),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('😴', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          const Text(
            'DRIVER SLEEPING!',
            style: TextStyle(
              color: Color(0xFFFF1744),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eyes closed for too long.\nPlease wake up immediately!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8B9BB4),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF1744).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: const Color(0xFFFF1744).withOpacity(0.4)),
            ),
            child: const Text(
              '🔊  ALARM ACTIVE — OPEN YOUR EYES',
              style: TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Drowsy Warning Banner ────────────────────────────────────────────────
  Widget _buildDrowsyWarningBanner() {
    return AnimatedBuilder(
      animation: _warningPulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0D00),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF6D00)
                  .withOpacity(0.5 + _warningPulseAnimation.value),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6D00)
                    .withOpacity(0.2 + _warningPulseAnimation.value * 0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D00).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFF6D00), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DROWSINESS DETECTED',
                      style: TextStyle(
                        color: Color(0xFFFF6D00),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Eyes closing — stay alert! Alarm in 3s.',
                      style:
                      TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Top Bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF1F2D40)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cognitive Load',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3),
              ),
              Text(
                _isActive ? '● Monitoring Active' : 'Camera Ready',
                style: TextStyle(
                  color: _isActive
                      ? const Color(0xFF00E5C3)
                      : const Color(0xFF4A5568),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isActive
                  ? _loadColor.withOpacity(0.12)
                  : const Color(0xFF111827),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isActive
                    ? _loadColor.withOpacity(0.5)
                    : const Color(0xFF1F2D40),
              ),
            ),
            child: Text(
              _isActive ? _loadLabel : 'STANDBY',
              style: TextStyle(
                color: _isActive ? _loadColor : const Color(0xFF4A5568),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Camera + Gauge ───────────────────────────────────────────────────────
  Widget _buildCameraAndGauge() {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _isActive
              ? _loadColor.withOpacity(0.3)
              : const Color(0xFF1F2D40),
          width: 1.5,
        ),
        boxShadow: _isActive && _data.drowsinessLevel != DrowsinessLevel.alert
            ? [
          BoxShadow(
            color: _loadColor.withOpacity(0.25),
            blurRadius: 30,
            spreadRadius: 2,
          )
        ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCameraView(),

            // Scan line
            if (_isActive)
              AnimatedBuilder(
                animation: _scanController,
                builder: (context, child) => CustomPaint(
                  painter: _ScanLinePainter(
                    progress: _scanController.value,
                    color: _loadColor,
                  ),
                ),
              ),

            // Bottom gradient
            Positioned(
              bottom: 0, left: 0, right: 0, height: 160,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xCC080C14),
                      Color(0xFF080C14),
                    ],
                  ),
                ),
              ),
            ),

            // Face brackets
            if (_isActive)
              Positioned(
                top: 40, left: 0, right: 0,
                child: Center(child: _FaceBrackets(color: _loadColor)),
              ),

            // Gauge overlay at bottom
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildGaugeContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: CameraPreview(_cameraController!),
      );
    }
    return Container(
      color: const Color(0xFF0D1520),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF111827),
              border:
              Border.all(color: const Color(0xFF1F2D40), width: 1.5),
            ),
            child: const Icon(Icons.face_outlined,
                color: Color(0xFF2D3F55), size: 34),
          ),
          const SizedBox(height: 16),
          const Text('Camera preview will appear here',
              style: TextStyle(color: Color(0xFF2D3F55), fontSize: 13)),
          const SizedBox(height: 4),
          const Text('Tap Start to activate monitoring',
              style: TextStyle(color: Color(0xFF1E2D3D), fontSize: 11)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildGaugeContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(110, 110),
                  painter: _ArcGaugePainter(
                    percentage: _data.loadPercentage / 100,
                    color: _loadColor,
                    isActive: _isActive,
                    strokeWidth: 8,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isActive
                          ? '${_data.loadPercentage.toStringAsFixed(0)}%'
                          : '--',
                      style: TextStyle(
                        color: _isActive
                            ? _loadColor
                            : const Color(0xFF2D3F55),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('LOAD',
                        style: TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniStat(
                  label: 'Eye Openness',
                  value: _isActive
                      ? '${(_data.eyeOpenness * 100).toStringAsFixed(0)}%'
                      : '--',
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF00E5C3),
                ),
                const SizedBox(height: 10),
                _MiniStat(
                  label: 'Blink Rate',
                  value: _isActive ? '${_data.blinkRate}/min' : '--',
                  icon: Icons.remove_red_eye_outlined,
                  color: const Color(0xFF4F8EFF),
                ),
                const SizedBox(height: 10),
                _MiniStat(
                  label: 'Head Pose',
                  value: _isActive ? _data.headPoseLabel : '--',
                  icon: Icons.face_outlined,
                  color: const Color(0xFFFFB547),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Metrics Row ──────────────────────────────────────────────────────────
  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: 'Distraction',
            value: _isActive ? _data.distractionLabel : '--',
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFFF4757),
            isActive: _isActive,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'Alertness',
            value: _isActive
                ? '${(100 - _data.loadPercentage).toStringAsFixed(0)}%'
                : '--',
            icon: Icons.bolt_rounded,
            color: const Color(0xFF00E5C3),
            isActive: _isActive,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'Status',
            value: _isActive ? _loadLabel : '--',
            icon: Icons.psychology_rounded,
            color: _isActive ? _loadColor : const Color(0xFF4A5568),
            isActive: _isActive,
          ),
        ),
      ],
    );
  }

  // ─── History Chart ────────────────────────────────────────────────────────
  Widget _buildHistoryChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1A2436)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Load Timeline',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('LAST 40s',
                    style: TextStyle(
                        color: Color(0xFF4A5568),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 80,
            child: _loadHistory.isEmpty
                ? const Center(
                child: Text('Start monitoring to see load history',
                    style:
                    TextStyle(color: Color(0xFF2D3F55), fontSize: 12)))
                : CustomPaint(
              size: const Size(double.infinity, 80),
              painter: _LineChartPainter(
                data: _loadHistory,
                color: _loadColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chartLegend('Safe', const Color(0xFF00E5C3)),
              _chartLegend('Moderate', const Color(0xFFFFB547)),
              _chartLegend('Critical', const Color(0xFFFF4757)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(String label, Color color) => Row(children: [
    Container(
        width: 8,
        height: 8,
        decoration:
        BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label,
        style: const TextStyle(color: Color(0xFF4A5568), fontSize: 10)),
  ]);

  // ─── Insights Card ────────────────────────────────────────────────────────
  Widget _buildInsightsCard() {
    final insights = _isActive ? _getInsights() : _defaultInsights();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1A2436)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: const Color(0xFFFFB547).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFFFFB547), size: 17),
              ),
              const SizedBox(width: 10),
              const Text('AI Insights',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: 16),
          ...insights.asMap().entries.map(
                (e) => Padding(
              padding: EdgeInsets.only(
                  bottom: e.key < insights.length - 1 ? 12 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                        color: const Color(0xFF00E5C3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF00E5C3), size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e.value,
                        style: const TextStyle(
                            color: Color(0xFF8B9BB4),
                            fontSize: 13,
                            height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _defaultInsights() => [
    'ML Kit analyzes facial mesh data in real-time at up to 30 frames/s.',
    'Eyes closed >1.5s triggers a drowsy warning. >3s triggers an alarm.',
    'An audible alarm and phone vibration activate when sleep is detected.',
  ];

  List<String> _getInsights() {
    final insights = <String>[];
    switch (_data.drowsinessLevel) {
      case DrowsinessLevel.sleeping:
        insights.add(
            '🚨 Sleep detected! Eyes closed for ${_data.eyeClosedSeconds.toStringAsFixed(1)}s. Alarm is active!');
        break;
      case DrowsinessLevel.warning:
        insights.add(
            '⚠️ Drowsiness warning — eyes closing for ${_data.eyeClosedSeconds.toStringAsFixed(1)}s. Alarm in ${(3.0 - _data.eyeClosedSeconds).toStringAsFixed(1)}s.');
        break;
      case DrowsinessLevel.alert:
        if (_data.blinkRate < 10) {
          insights.add(
              'Low blink rate (${_data.blinkRate}/min) — possible eye strain. Blink more consciously.');
        } else if (_data.blinkRate > 25) {
          insights.add(
              'High blink rate (${_data.blinkRate}/min) — early drowsiness. Consider a break.');
        }
        if (_data.eyeOpenness < 0.65) {
          insights.add(
              'Eyes partially closed — alertness reduced to ${(_data.eyeOpenness * 100).toStringAsFixed(0)}%.');
        }
        if (_data.loadPercentage > 70) {
          insights.add(
              'High cognitive load. Reduce distractions and slow down.');
        } else if (_data.loadPercentage < 30) {
          insights.add('You are alert and in peak focus. Drive safely!');
        }
    }
    if (insights.isEmpty) {
      insights.add('All indicators within safe range. Continue safely.');
    }
    return insights;
  }

  // ─── Control Bar ──────────────────────────────────────────────────────────
  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00080C14), Color(0xFF080C14), Color(0xFF080C14)],
        ),
      ),
      child: GestureDetector(
        onTap: _toggleMonitoring,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: _isActive
                ? const LinearGradient(
              colors: [Color(0xFFFF4757), Color(0xFFFF6B6B)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            )
                : const LinearGradient(
              colors: [Color(0xFF00E5C3), Color(0xFF4F8EFF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: (_isActive
                    ? const Color(0xFFFF4757)
                    : const Color(0xFF00E5C3))
                    .withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isActive
                      ? Icons.stop_circle_rounded
                      : Icons.play_circle_rounded,
                  color: Colors.white,
                  size: 24,
                  key: ValueKey(_isActive),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isActive ? 'Stop Monitoring' : 'Start Monitoring',
                  key: ValueKey(_isActive),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── High Load Alert Banner ───────────────────────────────────────────────
  Widget _buildAlertBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFFF4757).withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFFFF4757).withOpacity(0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.warning_rounded,
                color: Color(0xFFFF4757), size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HIGH COGNITIVE LOAD',
                    style: TextStyle(
                        color: Color(0xFFFF4757),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                SizedBox(height: 3),
                Text('Fatigue detected. Consider taking a break.',
                    style: TextStyle(
                        color: Color(0xFF8B9BB4), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Subwidgets ───────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat(
      {required this.label,
        required this.value,
        required this.icon,
        required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 14),
    const SizedBox(width: 6),
    Text(value,
        style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    const SizedBox(width: 6),
    Text(label,
        style:
        const TextStyle(color: Color(0xFF4A5568), fontSize: 11)),
  ]);
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isActive;

  const _MetricCard(
      {required this.label,
        required this.value,
        required this.icon,
        required this.color,
        required this.isActive});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1520),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
          color: isActive
              ? color.withOpacity(0.25)
              : const Color(0xFF1A2436)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 10),
        Text(value,
            style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF2D3F55),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF4A5568), fontSize: 10)),
      ],
    ),
  );
}

class _FaceBrackets extends StatelessWidget {
  final Color color;
  const _FaceBrackets({required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 140,
      height: 160,
      child: CustomPaint(painter: _BracketPainter(color: color)));
}

// ─── Custom Painters ──────────────────────────────────────────────────────────

class _BracketPainter extends CustomPainter {
  final Color color;
  _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    final r = const Radius.circular(4);
    canvas.drawPath(
        Path()
          ..moveTo(0, len)
          ..arcToPoint(Offset(len, 0), radius: r),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(size.width - len, 0)
          ..arcToPoint(Offset(size.width, len), radius: r),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height - len)
          ..arcToPoint(Offset(len, size.height), radius: r),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(size.width - len, size.height)
          ..arcToPoint(Offset(size.width, size.height - len), radius: r),
        paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = progress * size.height;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        color.withOpacity(0.15),
        color.withOpacity(0.3),
        color.withOpacity(0.15),
        Colors.transparent,
      ],
      stops: const [0, 0.3, 0.5, 0.7, 1],
    );
    final rect = Rect.fromLTWH(0, y - 30, size.width, 60);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()
          ..color = color.withOpacity(0.5)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

class _ArcGaugePainter extends CustomPainter {
  final double percentage;
  final Color color;
  final bool isActive;
  final double strokeWidth;

  _ArcGaugePainter(
      {required this.percentage,
        required this.color,
        required this.isActive,
        this.strokeWidth = 10});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth;
    const startAngle = pi * 0.75;
    const sweepAngle = pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false,
      Paint()
        ..color = const Color(0xFF1A2436)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (!isActive) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle * percentage, false,
      Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle * percentage,
          colors: [color.withOpacity(0.5), color],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.percentage != percentage || old.color != color;
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _LineChartPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF1A2436)
      ..strokeWidth = 1;
    for (final pct in [0.25, 0.5, 0.75]) {
      final y = size.height - pct * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - (data[i] / 100) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = ((i - 1) / (data.length - 1)) * size.width;
        final prevY = size.height - (data[i - 1] / 100) * size.height;
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..style = PaintingStyle.fill);

    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    final dotX = size.width;
    final dotY = size.height - (data.last / 100) * size.height;
    canvas.drawCircle(Offset(dotX, dotY), 4, Paint()..color = color);
    canvas.drawCircle(
        Offset(dotX, dotY),
        7,
        Paint()
          ..color = color.withOpacity(0.2)
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.data != data;
}