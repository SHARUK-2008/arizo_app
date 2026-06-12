// lib/screens/crash_triage_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../screens/sos_service.dart';

enum SOSStatus { idle, armed, sending, sent, cancelled }
enum CrashSeverity { none, minor, moderate, severe }

class CrashEvent {
  final DateTime time;
  final CrashSeverity severity;
  final String location;
  final double gForce;
  final bool sosDispatched;

  CrashEvent({
    required this.time,
    required this.severity,
    required this.location,
    required this.gForce,
    this.sosDispatched = false,
  });
}

class CrashTriageScreen extends StatefulWidget {
  const CrashTriageScreen({super.key});

  @override
  State<CrashTriageScreen> createState() => _CrashTriageScreenState();
}

class _CrashTriageScreenState extends State<CrashTriageScreen>
    with TickerProviderStateMixin {

  SOSStatus _sosStatus = SOSStatus.idle;
  int _sosCountdown = 10;
  Timer? _countdownTimer;

  bool _monitoringActive = true;
  double _currentGForce = 0.98;
  double _peakGForce = 0.0;
  CrashSeverity _detectedSeverity = CrashSeverity.none;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  bool _inCooldown = false;

  Position? _currentPosition;
  String _locationLabel = 'Fetching location…';
  bool _locationLoading = true;

  // Background GPS refresh timer
  Timer? _gpsRefreshTimer;

  List<SOSContact> _contacts = [];
  Set<int> _notifiedIndices = {};
  final List<CrashEvent> _history = [];

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _shakeAnim;

  static const double _minorThreshold    = 3.5;
  static const double _moderateThreshold = 6.0;
  static const double _severeThreshold   = 9.0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadContacts();
    _fetchGPS();
    _startAccelerometer();
    _requestPermissionsEarly();
    _startGPSRefreshLoop();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _shakeCtrl.dispose();
    _countdownTimer?.cancel();
    _accelSub?.cancel();
    _gpsRefreshTimer?.cancel();
    super.dispose();
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));

    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim  = Tween(begin: 0.0, end: 1.0).animate(_ringCtrl);
    _shakeAnim = Tween(begin: -7.0, end: 7.0).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
  }

  Future<void> _loadContacts() async {
    final contacts = await SOSService.loadContacts();
    if (!mounted) return;
    setState(() => _contacts = contacts);
    final firstLaunch = await SOSService.isFirstLaunch();
    if (firstLaunch && mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _showContactSetupDialog(isFirstTime: true);
    }
  }

  // ── GPS: initial fetch ─────────────────────────────────────────────────────

  Future<void> _fetchGPS() async {
    if (!mounted) return;
    setState(() => _locationLoading = true);

    // Use more attempts and longer timeout for the initial fetch.
    // SOSService.getCurrentPosition() now tries last-known → high → medium
    // accuracy internally, so even a single attempt here usually succeeds.
    final pos = await _fetchPositionWithRetry(maxAttempts: 3);

    if (!mounted) return;
    setState(() {
      _currentPosition = pos ?? _currentPosition; // keep old if new fails
      _locationLabel   = _currentPosition != null
          ? SOSService.formatPosition(_currentPosition!)
          : 'Location unavailable';
      _locationLoading = false;
    });
  }

  // ── GPS: silent background refresh every 30 s ──────────────────────────────

  void _startGPSRefreshLoop() {
    _gpsRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // Single attempt is enough — SOSService already has internal fallbacks.
      final pos = await _fetchPositionWithRetry(maxAttempts: 1);
      if (!mounted || pos == null) return;
      setState(() {
        _currentPosition = pos;
        _locationLabel   = SOSService.formatPosition(pos);
      });
    });
  }

  // ── GPS: retry helper ──────────────────────────────────────────────────────
  //
  // Each attempt gives SOSService up to 15 seconds.  15 s is enough for a
  // warm GPS fix; cold-start may need 30–60 s, but the internal last-known
  // fallback inside SOSService.getCurrentPosition() covers that instantly.
  //
  // We do NOT pass timeLimit inside LocationSettings (Android bug: it returns
  // null silently instead of throwing).  The .timeout() below is the only
  // deadline, and it triggers a TimeoutException that we can catch and retry.

  Future<Position?> _fetchPositionWithRetry({int maxAttempts = 3}) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // 15 s per attempt — long enough for a warm GPS fix but short enough
        // not to block the UI forever.
        final pos = await SOSService.getCurrentPosition()
            .timeout(const Duration(seconds: 15));
        if (pos != null) {
          // Cache immediately so SOS always has the freshest position.
          if (mounted) {
            setState(() {
              _currentPosition = pos;
              _locationLabel   = SOSService.formatPosition(pos);
            });
          }
          return pos;
        }
      } catch (_) {
        // TimeoutException or any other error → retry
      }

      if (attempt < maxAttempts) {
        // Short pause before next attempt so the GPS chip can settle.
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // All attempts failed — return last cached position (may be null).
    return _currentPosition;
  }

  void _startAccelerometer() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((AccelerometerEvent event) {
      if (!_monitoringActive || _inCooldown) return;

      final mag = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final gForce = mag / 9.81;

      if (mounted) {
        setState(() {
          _currentGForce = gForce;
          if (gForce > _peakGForce) _peakGForce = gForce;
        });
      }

      if (gForce >= _severeThreshold) {
        _onCrashDetected(CrashSeverity.severe, gForce);
      } else if (gForce >= _moderateThreshold) {
        _onCrashDetected(CrashSeverity.moderate, gForce);
      } else if (gForce >= _minorThreshold) {
        _onCrashDetected(CrashSeverity.minor, gForce);
      }
    });
  }

  Future<void> _requestPermissionsEarly() async {
    await SOSService.requestSMSPermission();
    // Warm up GPS permission AND cache a position so we always have one
    // ready when SOS fires.
    final pos = await SOSService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = pos;
        _locationLabel   = SOSService.formatPosition(pos);
        _locationLoading = false;
      });
    }
  }

  void _onCrashDetected(CrashSeverity severity, double gForce) {
    if (_inCooldown || _sosStatus != SOSStatus.idle) return;

    _inCooldown = true;
    Future.delayed(const Duration(seconds: 15), () => _inCooldown = false);

    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);

    if (mounted) {
      setState(() {
        _detectedSeverity = severity;
        _currentGForce    = gForce;
      });
    }

    if (severity == CrashSeverity.severe || severity == CrashSeverity.moderate) {
      _startSOSCountdown(autoTriggered: true, seconds: 10);
    } else {
      _showMinorImpactBanner();
    }
  }

  void _showMinorImpactBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFFF9F0A),
        content: Text(
          '⚠ Minor impact detected (${_currentGForce.toStringAsFixed(1)}g). Are you okay?',
          style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
        ),
        action: SnackBarAction(
          label: 'SEND SOS',
          textColor: Colors.black,
          onPressed: _manualSOS,
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _manualSOS() => _startSOSCountdown(autoTriggered: false, seconds: 5);

  void _startSOSCountdown({required bool autoTriggered, required int seconds}) {
    if (_sosStatus == SOSStatus.armed || _sosStatus == SOSStatus.sending) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _sosStatus    = SOSStatus.armed;
      _sosCountdown = seconds;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_sosCountdown <= 1) {
        timer.cancel();
        _dispatchSOS();
      } else {
        HapticFeedback.selectionClick();
        setState(() => _sosCountdown--);
      }
    });
  }

  void _cancelSOS() {
    _countdownTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _sosStatus    = SOSStatus.cancelled;
      _sosCountdown = 10;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sosStatus = SOSStatus.idle);
    });
  }

  // ── Dispatch SOS ───────────────────────────────────────────────────────────

  Future<void> _dispatchSOS() async {
    if (!mounted) return;
    setState(() {
      _sosStatus       = SOSStatus.sending;
      _notifiedIndices = {};
    });

    HapticFeedback.heavyImpact();

    // ── Step 1: Get the best possible position ─────────────────────────────
    //
    // We try up to 5 attempts (more than the background loop) because
    // accuracy at dispatch time is critical.  SOSService.getCurrentPosition()
    // now tries last-known → high → medium accuracy internally, so the
    // first attempt here often returns instantly via last-known.
    //
    // If ALL attempts fail we still have _currentPosition from the background
    // refresh loop (updated every 30 s).  Only show "unavailable" if we
    // have absolutely nothing cached.
    Position? position = await _fetchPositionWithRetry(maxAttempts: 5);
    position ??= _currentPosition; // final fallback: last cached value

    if (!mounted) return;

    if (position != null) {
      setState(() {
        _currentPosition = position;
        _locationLabel   = SOSService.formatPosition(position!);
      });
    } else {
      setState(() => _locationLabel = 'Location unavailable');
    }

    // ── Step 2: Build severity label ───────────────────────────────────────
    final severity      = _detectedSeverity == CrashSeverity.none
        ? CrashSeverity.minor
        : _detectedSeverity;
    final severityLabel = severity.name.toUpperCase();

    // ── Step 3: Send SMS one contact at a time ─────────────────────────────
    for (int i = 0; i < _contacts.length; i++) {
      await SOSService.sendSMSToAll(
        contacts:  [_contacts[i]],
        severity:  severityLabel,
        gForce:    _currentGForce,
        position:  position, // may be null — SOSService handles gracefully
      );
      if (!mounted) return;
      setState(() => _notifiedIndices = {..._notifiedIndices, i});
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // ── Step 4: Log event ──────────────────────────────────────────────────
    final event = CrashEvent(
      time:         DateTime.now(),
      severity:     severity,
      location:     _locationLabel,
      gForce:       _currentGForce,
      sosDispatched: true,
    );

    if (!mounted) return;
    setState(() {
      _sosStatus = SOSStatus.sent;
      _history.insert(0, event);
    });

    // ── Step 5: Dial 112 ───────────────────────────────────────────────────
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) await SOSService.callEmergencyServices();

    // ── Step 6: Reset ──────────────────────────────────────────────────────
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    setState(() {
      _sosStatus        = SOSStatus.idle;
      _detectedSeverity = CrashSeverity.none;
      _notifiedIndices  = {};
    });
  }

  // ── Contact Setup Dialog ──────────────────────────────────────────────────

  void _showContactSetupDialog({bool isFirstTime = false}) {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: !isFirstTime,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12121F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFirstTime) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SETUP REQUIRED',
                  style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.w800,
                    color: const Color(0xFFFF3B30), letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              isFirstTime ? 'Add Emergency Contact' : 'New Contact',
              style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white,
              ),
            ),
            if (isFirstTime)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This person will receive an automatic SMS with your GPS location when SOS is triggered.',
                  style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF6B7494), height: 1.4,
                  ),
                ),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogTextField(
              controller: nameCtrl,
              label: 'Name (e.g. Neighbour, Family)',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _DialogTextField(
              controller: phoneCtrl,
              label: 'Phone number (with country code)',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          if (!isFirstTime)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: const Color(0xFF4A5070))),
            ),
          ElevatedButton(
            onPressed: () async {
              final name  = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              await SOSService.addContact(SOSContact(name: name, phone: phone));
              await _loadContacts();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save Contact',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showRemoveContactDialog(int index) {
    final c = _contacts[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12121F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Contact?',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        content: Text(
          '${c.name} (${c.phone}) will no longer receive SOS alerts.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7494)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: const Color(0xFF4A5070))),
          ),
          ElevatedButton(
            onPressed: () async {
              await SOSService.removeContact(index);
              await _loadContacts();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Remove',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color get _severityColor => switch (_detectedSeverity) {
    CrashSeverity.minor    => const Color(0xFFFF9F0A),
    CrashSeverity.moderate => const Color(0xFFFF6B30),
    CrashSeverity.severe   => const Color(0xFFFF3B30),
    _                      => const Color(0xFF30D158),
  };

  String get _severityLabel => switch (_detectedSeverity) {
    CrashSeverity.minor    => 'MINOR IMPACT',
    CrashSeverity.moderate => 'MODERATE CRASH',
    CrashSeverity.severe   => 'SEVERE CRASH',
    _                      => 'MONITORING',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildSOSButton(),
                    const SizedBox(height: 20),
                    _buildDetectionCard(),
                    const SizedBox(height: 14),
                    _buildLocationCard(),
                    const SizedBox(height: 14),
                    _buildContactsCard(),
                    const SizedBox(height: 14),
                    _buildServicesCard(),
                    const SizedBox(height: 14),
                    if (_history.isNotEmpty) _buildHistoryCard(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E35), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.emergency_outlined,
                color: Color(0xFFFF3B30), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crash Triage',
                    style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: Colors.white, letterSpacing: -0.3,
                    )),
                Text('One-Tap SOS · Auto Crash Detection',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: const Color(0xFF4A5070))),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _monitoringActive = !_monitoringActive),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _monitoringActive
                    ? const Color(0xFF30D158).withValues(alpha: 0.12)
                    : const Color(0xFF1E1E35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _monitoringActive
                      ? const Color(0xFF30D158).withValues(alpha: 0.35)
                      : const Color(0xFF1E1E35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _monitoringActive
                          ? const Color(0xFF30D158)
                          : const Color(0xFF3A3A55),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _monitoringActive ? 'ARMED' : 'OFF',
                    style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: _monitoringActive
                          ? const Color(0xFF30D158)
                          : const Color(0xFF3A3A55),
                      letterSpacing: 0.6,
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

  Widget _buildSOSButton() {
    final isArmed     = _sosStatus == SOSStatus.armed;
    final isSending   = _sosStatus == SOSStatus.sending;
    final isSent      = _sosStatus == SOSStatus.sent;
    final isCancelled = _sosStatus == SOSStatus.cancelled;

    final btnColor = isArmed     ? const Color(0xFFFF9F0A)
        : isSending   ? const Color(0xFFFF3B30)
        : isSent      ? const Color(0xFF30D158)
        : isCancelled ? const Color(0xFF3A3A55)
        :               const Color(0xFFFF3B30);

    return Column(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_ringAnim, _pulseAnim, _shakeAnim]),
          builder: (_, __) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (isArmed || isSending)
                  ...List.generate(3, (i) {
                    final progress = ((_ringAnim.value + i / 3) % 1.0);
                    return Transform.scale(
                      scale: 1.0 + progress * 0.9,
                      child: Container(
                        width: 165, height: 165,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: btnColor.withValues(alpha: (1 - progress) * 0.45),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }),
                ScaleTransition(
                  scale: _sosStatus == SOSStatus.idle
                      ? _pulseAnim
                      : const AlwaysStoppedAnimation(1.0),
                  child: GestureDetector(
                    onTap: _sosStatus == SOSStatus.idle ? _manualSOS
                        : _sosStatus == SOSStatus.armed ? _cancelSOS
                        : null,
                    child: Transform.translate(
                      offset: _shakeCtrl.isAnimating
                          ? Offset(_shakeAnim.value, 0)
                          : Offset.zero,
                      child: Container(
                        width: 155, height: 155,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: btnColor.withValues(alpha: 0.12),
                          border: Border.all(color: btnColor, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: btnColor.withValues(alpha: 0.35),
                              blurRadius: 32, spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isSending)
                              SizedBox(
                                width: 30, height: 30,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: btnColor),
                              )
                            else
                              Icon(
                                isSent      ? Icons.check_circle_rounded
                                    : isArmed   ? Icons.warning_rounded
                                    : Icons.sos_rounded,
                                color: btnColor, size: 44,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              isArmed    ? '$_sosCountdown'
                                  : isSent     ? 'SENT'
                                  : isCancelled? 'CANCEL'
                                  : isSending  ? 'SENDING'
                                  : 'SOS',
                              style: GoogleFonts.inter(
                                fontSize: isArmed ? 30 : 18,
                                fontWeight: FontWeight.w800,
                                color: btnColor, letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          isArmed    ? 'TAP TO CANCEL · SENDING IN $_sosCountdown s'
              : isSent     ? 'SOS SENT · DIALLING 112…'
              : isSending  ? 'DISPATCHING SOS…'
              : isCancelled? 'SOS CANCELLED'
              :               'TAP FOR EMERGENCY SOS',
          style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: isArmed ? const Color(0xFFFF9F0A)
                : isSent   ? const Color(0xFF30D158)
                :             const Color(0xFF4A5070),
            letterSpacing: 1.1,
          ),
        ),
        if (isArmed) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _sosCountdown / 10.0,
                backgroundColor: const Color(0xFF1E1E35),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFF9F0A)),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _detectedSeverity != CrashSeverity.none
              ? _severityColor.withValues(alpha: 0.4)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CRASH DETECTION',
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: const Color(0xFF3A3A55), letterSpacing: 1.2,
                  )),
              const Spacer(),
              _StatusBadge(label: _severityLabel, color: _severityColor),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MetricBox(
                label: 'G-FORCE',
                value: '${_currentGForce.toStringAsFixed(2)}g',
                color: _currentGForce > _minorThreshold
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF30D158),
              ),
              const SizedBox(width: 10),
              _MetricBox(
                label: 'PEAK',
                value: _peakGForce > 0
                    ? '${_peakGForce.toStringAsFixed(2)}g' : '—',
                color: const Color(0xFFFF9F0A),
              ),
              const SizedBox(width: 10),
              _MetricBox(
                label: 'SENSOR',
                value: _monitoringActive ? 'LIVE' : 'OFF',
                color: _monitoringActive
                    ? const Color(0xFF30D158) : const Color(0xFF3A3A55),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ThresholdBar(
            gForce: _currentGForce,
            minor: _minorThreshold,
            moderate: _moderateThreshold,
            severe: _severeThreshold,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  color: Color(0xFF0A84FF), size: 15),
              const SizedBox(width: 6),
              Text('GPS LOCATION',
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: const Color(0xFF3A3A55), letterSpacing: 1.2,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: _fetchGPS,
                child: Row(
                  children: [
                    if (_locationLoading)
                      const SizedBox(
                        width: 10, height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Color(0xFF30D158)),
                      )
                    else
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPosition != null
                              ? const Color(0xFF30D158)
                              : const Color(0xFFFF9F0A),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _locationLoading ? 'FETCHING' : 'REFRESH',
                      style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: _locationLoading
                            ? const Color(0xFF30D158)
                            : const Color(0xFF0A84FF),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_locationLabel,
              style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: const Color(0xFFE8EAF6),
              )),
          if (_currentPosition != null) ...[
            const SizedBox(height: 3),
            Text(
              'Accuracy: ±${_currentPosition!.accuracy.toStringAsFixed(0)}m'
                  ' · Alt: ${_currentPosition!.altitude.toStringAsFixed(0)}m',
              style: GoogleFonts.inter(
                  fontSize: 10, color: const Color(0xFF4A5070)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InfoChip(
                  icon: Icons.local_hospital_outlined,
                  label: '112 — Emergency',
                  color: const Color(0xFFFF3B30),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoChip(
                  icon: Icons.local_police_outlined,
                  label: '108 — Ambulance',
                  color: const Color(0xFF0A84FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _contacts.isEmpty
              ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_contacts.isEmpty)
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFF3B30), size: 14),
              if (_contacts.isEmpty) const SizedBox(width: 4),
              Text(
                _contacts.isEmpty
                    ? 'NO CONTACTS — SOS WON\'T SEND SMS'
                    : 'EMERGENCY CONTACTS',
                style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: _contacts.isEmpty
                      ? const Color(0xFFFF3B30) : const Color(0xFF3A3A55),
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showContactSetupDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5CC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF00E5CC).withValues(alpha: 0.3)),
                  ),
                  child: Text('+ Add',
                      style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: const Color(0xFF00E5CC),
                      )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_contacts.isEmpty)
            GestureDetector(
              onTap: () => _showContactSetupDialog(isFirstTime: true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person_add_outlined,
                        color: Color(0xFFFF3B30), size: 28),
                    const SizedBox(height: 6),
                    Text('Tap to add neighbour or family',
                        style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF3B30),
                        )),
                    Text('Required for automatic SMS dispatch',
                        style: GoogleFonts.inter(
                            fontSize: 10, color: const Color(0xFF4A5070))),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_contacts.length, (i) {
              final c          = _contacts[i];
              final isNotified = _notifiedIndices.contains(i);
              return GestureDetector(
                onLongPress: () => _showRemoveContactDialog(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isNotified
                        ? const Color(0xFF30D158).withValues(alpha: 0.06)
                        : const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isNotified
                          ? const Color(0xFF30D158).withValues(alpha: 0.3)
                          : const Color(0xFF1E1E35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                          border: Border.all(
                              color: const Color(0xFF0A84FF).withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.person_outline,
                            color: Color(0xFF0A84FF), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: const Color(0xFFE8EAF6),
                                )),
                            Text(c.phone,
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF4A5070))),
                          ],
                        ),
                      ),
                      if (isNotified)
                        _StatusBadge(
                            label: 'SMS SENT ✓',
                            color: const Color(0xFF30D158))
                      else
                        Column(
                          children: [
                            const Icon(Icons.sms_outlined,
                                color: Color(0xFF2A2A45), size: 16),
                            Text('auto-SMS',
                                style: GoogleFonts.inter(
                                    fontSize: 8,
                                    color: const Color(0xFF2A2A45))),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
          if (_contacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Long-press a contact to remove · All contacts get auto-SMS on SOS',
                style: GoogleFonts.inter(
                    fontSize: 10, color: const Color(0xFF3A3A55)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServicesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EMERGENCY SERVICES',
              style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: const Color(0xFF3A3A55), letterSpacing: 1.2,
              )),
          const SizedBox(height: 12),
          _ServiceTile(
            icon: Icons.emergency_outlined,
            name: '112 — National Emergency',
            subtitle: 'Police · Fire · Ambulance',
            color: const Color(0xFFFF3B30),
            onCall: () => SOSService.callEmergencyServices(number: '112'),
          ),
          const SizedBox(height: 8),
          _ServiceTile(
            icon: Icons.local_hospital_outlined,
            name: '108 — Ambulance',
            subtitle: 'Tamil Nadu Medical Services',
            color: const Color(0xFFFF9F0A),
            onCall: () => SOSService.callEmergencyServices(number: '108'),
          ),
          const SizedBox(height: 8),
          _ServiceTile(
            icon: Icons.local_police_outlined,
            name: '100 — Police',
            subtitle: 'Tamil Nadu Police',
            color: const Color(0xFF0A84FF),
            onCall: () => SOSService.callEmergencyServices(number: '100'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INCIDENT HISTORY',
              style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: const Color(0xFF3A3A55), letterSpacing: 1.2,
              )),
          const SizedBox(height: 12),
          ..._history.take(5).map((e) => _HistoryTile(event: e)),
        ],
      ),
    );
  }
}

// ─── Small Reusable Widgets ───────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 8.5, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 0.7,
          )),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 8,
                    color: const Color(0xFF3A3A55),
                    letterSpacing: 0.5),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ThresholdBar extends StatelessWidget {
  final double gForce;
  final double minor;
  final double moderate;
  final double severe;
  const _ThresholdBar(
      {required this.gForce,
        required this.minor,
        required this.moderate,
        required this.severe});

  @override
  Widget build(BuildContext context) {
    final max      = severe + 2.0;
    final fraction = (gForce / max).clamp(0.0, 1.0);
    final barColor = gForce >= severe   ? const Color(0xFFFF3B30)
        : gForce >= moderate ? const Color(0xFFFF6B30)
        : gForce >= minor    ? const Color(0xFFFF9F0A)
        :                      const Color(0xFF30D158);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0g', style: GoogleFonts.inter(
                fontSize: 8, color: const Color(0xFF3A3A55))),
            Text('Minor ${minor}g', style: GoogleFonts.inter(
                fontSize: 8, color: const Color(0xFFFF9F0A))),
            Text('Mod ${moderate}g', style: GoogleFonts.inter(
                fontSize: 8, color: const Color(0xFFFF6B30))),
            Text('Severe ${severe}g+', style: GoogleFonts.inter(
                fontSize: 8, color: const Color(0xFFFF3B30))),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 6, color: const Color(0xFF1E1E35)),
              FractionallySizedBox(
                widthFactor: fraction,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10, color: color,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String subtitle;
  final Color color;
  final VoidCallback onCall;
  const _ServiceTile(
      {required this.icon, required this.name, required this.subtitle,
        required this.color, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8EAF6),
                  )),
              Text(subtitle,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: const Color(0xFF4A5070))),
            ],
          ),
        ),
        GestureDetector(
          onTap: onCall,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.call_outlined, color: color, size: 12),
                const SizedBox(width: 4),
                Text('CALL',
                    style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: color, letterSpacing: 0.6,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: GoogleFonts.inter(
            fontSize: 13, color: const Color(0xFF3A3A55)),
        prefixIcon: Icon(icon, color: const Color(0xFF4A5070), size: 18),
        filled: true,
        fillColor: const Color(0xFF0A0A0F),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E1E35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFFFF3B30), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CrashEvent event;
  const _HistoryTile({required this.event});

  Color get _color => switch (event.severity) {
    CrashSeverity.minor    => const Color(0xFFFF9F0A),
    CrashSeverity.moderate => const Color(0xFFFF6B30),
    CrashSeverity.severe   => const Color(0xFFFF3B30),
    _                      => const Color(0xFF30D158),
  };

  @override
  Widget build(BuildContext context) {
    final h = event.time.hour.toString().padLeft(2, '0');
    final m = event.time.minute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.severity.name.toUpperCase()} — ${event.gForce.toStringAsFixed(1)}g',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: _color),
                ),
                Text(event.location,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: const Color(0xFF4A5070))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$h:$m',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF4A5070))),
              if (event.sosDispatched)
                Text('SOS ✓',
                    style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: const Color(0xFF30D158),
                    )),
            ],
          ),
        ],
      ),
    );
  }
}