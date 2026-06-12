import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─── Pothole Data Model ────────────────────────────────────────────────────────

class PotholeMarker {
  final String id;
  final LatLng position;
  final DateTime timestamp;
  final String severity;
  final String triggerWord;

  const PotholeMarker({
    required this.id,
    required this.position,
    required this.timestamp,
    required this.severity,
    this.triggerWord = 'manual',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': position.latitude,
    'lng': position.longitude,
    'timestamp': timestamp.toIso8601String(),
    'severity': severity,
    'triggerWord': triggerWord,
  };

  factory PotholeMarker.fromJson(Map<String, dynamic> j) => PotholeMarker(
    id: j['id'],
    position: LatLng(j['lat'], j['lng']),
    timestamp: DateTime.parse(j['timestamp']),
    severity: j['severity'],
    triggerWord: j['triggerWord'] ?? 'unknown',
  );
}

// ─── Voice Detection Result (public to avoid private-type-in-public-API lint) ─

class DetectionResult {
  final bool detected;
  final String matchedWord;
  final String severity;
  const DetectionResult(this.detected, this.matchedWord, this.severity);
}

// ─── Voice Detection Engine ────────────────────────────────────────────────────

class VoiceDetectionEngine {
  static const Map<String, String> _keywordSeverity = {
    // High
    'pothole': 'high',
    'pot hole': 'high',
    'big hole': 'high',
    'deep hole': 'high',
    'crater': 'high',
    'damage': 'high',
    'road damage': 'high',
    'danger': 'high',
    'dangerous': 'high',
    'broken road': 'high',
    'road broken': 'high',
    'bad road': 'high',
    'very bad': 'high',
    'terrible': 'high',
    // Medium
    'bump': 'medium',
    'speed bump': 'medium',
    'rough': 'medium',
    'rough road': 'medium',
    'uneven': 'medium',
    'crack': 'medium',
    'cracked': 'medium',
    'broken': 'medium',
    'mark': 'medium',
    'mark here': 'medium',
    'mark this': 'medium',
    'mark it': 'medium',
    // Low
    'hole': 'low',
    'small hole': 'low',
    'bump here': 'low',
    'bad': 'low',
    'problem': 'low',
    'issue': 'low',
  };

  static DetectionResult analyze(String rawText) {
    final text = rawText.toLowerCase().trim();
    if (text.isEmpty) return const DetectionResult(false, '', 'low');

    // 1. Exact phrase match
    for (final entry in _keywordSeverity.entries) {
      if (text.contains(entry.key)) {
        return DetectionResult(true, entry.key, entry.value);
      }
    }

    // 2. Fuzzy single-word match (handles partial STT recognition)
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length < 3) continue;
      for (final entry in _keywordSeverity.entries) {
        final keyword = entry.key.split(' ').first;
        if (_isFuzzyMatch(word, keyword)) {
          return DetectionResult(true, keyword, entry.value);
        }
      }
    }

    return const DetectionResult(false, '', 'low');
  }

  static bool _isFuzzyMatch(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 3) return false;
    final maxDist = b.length <= 5 ? 1 : 2;
    return _levenshtein(a, b) <= maxDist;
  }

  static int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce(min);
      }
    }
    return dp[m][n];
  }
}

// ─── Pothole Screen ────────────────────────────────────────────────────────────

class PotholeScreen extends StatefulWidget {
  const PotholeScreen({super.key});

  @override
  State<PotholeScreen> createState() => _PotholeScreenState();
}

class _PotholeScreenState extends State<PotholeScreen>
    with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final MapController _mapController = MapController();

  List<PotholeMarker> _potholes = [];
  LatLng? _currentLocation;
  bool _isListening = false;
  bool _speechAvailable = false;
  String _statusText = 'Tap mic to begin voice detection';
  String _lastWords = '';
  StreamSubscription<Position>? _positionSub;
  Timer? _restartTimer;
  bool _isMarking = false;
  int _sessionMarks = 0;

  late AnimationController _pulseCtrl;
  late AnimationController _rippleCtrl;
  late AnimationController _markCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;
  late Animation<double> _markAnim;

  static const _kPrimaryRed = Color(0xFFE53E3E);
  static const _kAccentOrange = Color(0xFFED8936);
  static const _kAccentYellow = Color(0xFFECC94B);
  static const _kSurface = Color(0xFF0D0D14);
  static const _kCard = Color(0xFF13131E);
  static const _kBorder = Color(0xFF1F1F30);
  static const _kMuted = Color(0xFF3A3A58);
  static const _kDim = Color(0xFF252538);

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _rippleAnim = Tween<double>(begin: 0.6, end: 1.4).animate(_rippleCtrl);

    _markCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _markAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _markCtrl, curve: Curves.elasticOut));

    _initAll();
  }

  Future<void> _initAll() async {
    await _initSpeech();
    await _initLocation();
    await _loadSavedPotholes();
  }

  Future<void> _initSpeech() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;
    _speechAvailable = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (e) {
        debugPrint('Speech error: $e');
        if (_isListening) {
          _scheduleRestart(delay: const Duration(milliseconds: 500));
        }
      },
    );
    setState(() {});
  }

  Future<void> _initLocation() async {
    final status = await Permission.location.request();
    if (!status.isGranted) return;
    try {
      // FIX: use locationSettings instead of deprecated desiredAccuracy
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
        const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_currentLocation!, 15.5);
    } catch (_) {}

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 4),
    ).listen((pos) {
      setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
    });
  }

  Future<void> _loadSavedPotholes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('potholes_v2');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => PotholeMarker.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _potholes = list);
    }
  }

  Future<void> _savePotholes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'potholes_v2', jsonEncode(_potholes.map((p) => p.toJson()).toList()));
  }

  // ── Speech ───────────────────────────────────────────────────────────────────

  void _onSpeechStatus(String status) {
    if (!_isListening) return;
    if (status == 'done' || status == 'notListening') {
      _scheduleRestart(delay: const Duration(milliseconds: 250));
    }
  }

  void _scheduleRestart(
      {Duration delay = const Duration(milliseconds: 300)}) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (_isListening && mounted) _startListeningSession();
    });
  }

  void _startListeningSession() {
    if (!_speechAvailable || !mounted) return;
    // FIX: use SpeechListenOptions instead of deprecated positional params
    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        if (words.isEmpty) return;
        setState(() => _lastWords = words);
        final detection = VoiceDetectionEngine.analyze(words);
        if (detection.detected && !_isMarking) {
          _markPothole(
              severity: detection.severity, trigger: detection.matchedWord);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  void _toggleListening() {
    HapticFeedback.mediumImpact();
    _isListening ? _stopListening() : _startListening();
  }

  void _startListening() {
    setState(() {
      _isListening = true;
      _sessionMarks = 0;
      _statusText = 'Listening — say "pothole", "damage", "bump"…';
    });
    _startListeningSession();
  }

  void _stopListening() {
    _restartTimer?.cancel();
    _speech.stop();
    setState(() {
      _isListening = false;
      _lastWords = '';
      _statusText = 'Tap mic to begin voice detection';
    });
  }

  // ── Marking ──────────────────────────────────────────────────────────────────

  void _markPothole({String severity = 'high', String trigger = 'manual'}) {
    if (_currentLocation == null || _isMarking) return;
    _isMarking = true;

    final marker = PotholeMarker(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: _currentLocation!,
      timestamp: DateTime.now(),
      severity: severity,
      triggerWord: trigger,
    );

    HapticFeedback.heavyImpact();
    _markCtrl.forward(from: 0);

    setState(() {
      _potholes.add(marker);
      _sessionMarks++;
      _statusText = trigger == 'manual'
          ? '📍 Marked manually — ${_currentLocation!.latitude.toStringAsFixed(5)}'
          : '🎙 Detected "${trigger.toUpperCase()}" → $severity';
    });

    _savePotholes();
    _showConfirmSnackBar(severity, trigger);
    Timer(const Duration(seconds: 2), () => _isMarking = false);
  }

  void _showConfirmSnackBar(String severity, String trigger) {
    final color = _severityColor(severity);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.5), width: 1),
        ),
        duration: const Duration(seconds: 2),
        content: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.warning_rounded, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${severity.toUpperCase()} severity marked',
                  style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                if (trigger != 'manual')
                  Text(
                    'Voice: "$trigger"',
                    style: GoogleFonts.dmMono(
                        color: color.withValues(alpha: 0.8), fontSize: 11),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _clearAll() async {
    HapticFeedback.lightImpact();
    setState(() {
      _potholes = [];
      _sessionMarks = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('potholes_v2');
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'high':
        return _kPrimaryRed;
      case 'medium':
        return _kAccentOrange;
      default:
        return _kAccentYellow;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _markCtrl.dispose();
    _restartTimer?.cancel();
    _positionSub?.cancel();
    _speech.stop();
    super.dispose();
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildVoiceStatus(),
            Expanded(child: _buildMap()),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? _kPrimaryRed : _kMuted,
                        boxShadow: _isListening
                            ? [
                          BoxShadow(
                              color: _kPrimaryRed.withValues(alpha: 0.6),
                              blurRadius: 6)
                        ]
                            : [],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isListening ? 'ACTIVE' : 'STANDBY',
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _isListening ? _kPrimaryRed : _kMuted,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Road\nScanner',
                  style: GoogleFonts.dmSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildStatChip(
                  icon: Icons.location_on_rounded,
                  label: '${_potholes.length} total',
                  color: _kPrimaryRed),
              const SizedBox(height: 6),
              _buildStatChip(
                  icon: Icons.bolt_rounded,
                  label: '$_sessionMarks session',
                  color: _kAccentOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      {required IconData icon,
        required String label,
        required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.dmMono(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceStatus() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
          _isListening ? _kPrimaryRed.withValues(alpha: 0.35) : _kBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isListening
                ? Icons.graphic_eq_rounded
                : Icons.info_outline_rounded,
            color: _isListening ? _kPrimaryRed : _kMuted,
            size: 15,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusText,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _isListening
                    ? Colors.white.withValues(alpha: 0.85)
                    : _kMuted,
              ),
            ),
          ),
          // Live transcription pill — FIX: removed invalid 'overflow' param from Text
          if (_isListening && _lastWords.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxWidth: 100),
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kDim,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _lastWords.length > 18
                    ? '\u2026${_lastWords.substring(_lastWords.length - 16)}'
                    : _lastWords,
                style: GoogleFonts.dmMono(fontSize: 10, color: _kMuted),
                overflow: TextOverflow.ellipsis, // correct placement: on Text
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final center = _currentLocation ?? const LatLng(13.0827, 80.2707);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.5,
            ),
            children: [
              TileLayer(
                urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 22,
                      height: 22,
                      child: _buildCurrentLocationDot(),
                    ),
                  ..._potholes.map((p) => Marker(
                    point: p.position,
                    width: 30,
                    height: 30,
                    child: Tooltip(
                      message:
                      '${p.severity.toUpperCase()} • "${p.triggerWord}" • ${_formatTime(p.timestamp)}',
                      child: _buildPotholeMarkerWidget(p),
                    ),
                  )),
                ],
              ),
            ],
          ),
          // Top fade overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _kSurface.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Map controls
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _mapIconButton(
                  icon: Icons.my_location_rounded,
                  color: const Color(0xFF4299E1),
                  onTap: () {
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, 16.0);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _mapIconButton(
                  icon: Icons.add_rounded,
                  color: _kMuted,
                  onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1),
                ),
                const SizedBox(height: 8),
                _mapIconButton(
                  icon: Icons.remove_rounded,
                  color: _kMuted,
                  onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _buildLegend(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationDot() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4299E1),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF4299E1).withValues(alpha: 0.5),
              blurRadius: 10)
        ],
      ),
    );
  }

  Widget _buildPotholeMarkerWidget(PotholeMarker p) {
    final color = _severityColor(p.severity);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8)
        ],
      ),
      child: const Icon(Icons.warning_rounded, color: Colors.white, size: 14),
    );
  }

  Widget _mapIconButton(
      {required IconData icon,
        required Color color,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _kCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _kCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(_kPrimaryRed, 'High'),
          const SizedBox(height: 4),
          _legendRow(_kAccentOrange, 'Medium'),
          const SizedBox(height: 4),
          _legendRow(_kAccentYellow, 'Low'),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.dmMono(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        children: [
          if (_isListening) _buildKeywordHints(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildMarkButton()),
              const SizedBox(width: 16),
              _buildMicButton(),
              const SizedBox(width: 16),
              Expanded(child: _buildClearButton()),
            ],
          ),
          if (!_speechAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Microphone permission required',
                style: GoogleFonts.dmSans(fontSize: 11, color: _kPrimaryRed),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeywordHints() {
    final hints = ['damage', 'pothole', 'bump', 'crack', 'bad'];
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hints.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final isActive = _lastWords.toLowerCase().contains(hints[i]);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? _kPrimaryRed.withValues(alpha: 0.2) : _kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? _kPrimaryRed.withValues(alpha: 0.6)
                    : _kBorder,
              ),
            ),
            child: Text(
              hints[i],
              style: GoogleFonts.dmMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? _kPrimaryRed : _kMuted,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarkButton() {
    return GestureDetector(
      onTap: () => _markPothole(severity: 'high', trigger: 'manual'),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_location_alt_rounded,
                color: Colors.white, size: 18),
            const SizedBox(height: 2),
            Text(
              'Mark',
              style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: _speechAvailable ? _toggleListening : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isListening)
            AnimatedBuilder(
              animation: _rippleAnim,
              builder: (_, __) => Container(
                width: 72 * _rippleAnim.value,
                height: 72 * _rippleAnim.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _kPrimaryRed.withValues(
                        alpha: (1.4 - _rippleAnim.value).clamp(0.0, 0.4)),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ScaleTransition(
            scale: _isListening
                ? _pulseAnim
                : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? _kPrimaryRed : _kCard,
                border: Border.all(
                  color: _isListening ? _kPrimaryRed : _kBorder,
                  width: 1.5,
                ),
                boxShadow: _isListening
                    ? [
                  BoxShadow(
                    color: _kPrimaryRed.withValues(alpha: 0.45),
                    blurRadius: 22,
                    spreadRadius: 3,
                  ),
                ]
                    : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _isListening ? Colors.white : _kMuted,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearButton() {
    return GestureDetector(
      onTap: _potholes.isNotEmpty ? _clearAll : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _potholes.isNotEmpty ? 1.0 : 0.35,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline_rounded,
                  color: _potholes.isNotEmpty ? _kPrimaryRed : _kMuted,
                  size: 18),
              const SizedBox(height: 2),
              Text(
                'Clear',
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _potholes.isNotEmpty
                        ? _kPrimaryRed.withValues(alpha: 0.8)
                        : _kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}