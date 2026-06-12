import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart'; // FIX: added
import 'near_miss_event.dart';
import 'crash_camera_service.dart';

// ─── Thresholds ───────────────────────────────────────────────────────────────
const double _kHardBrakeG = 1.5;
const double _kSwerveGyro = 2.0;
const double _kRapidAccelG = 1.8;
const double _kCollisionG = 3.5;
const int _kPreBufferSize = 50;
const int _kPostBufferSize = 50;

class NearMissService {
  // ── Public streams ──────────────────────────────────────────────────────────
  final _eventController = StreamController<NearMissEvent>.broadcast();
  final _recordingController = StreamController<bool>.broadcast();
  final _pointController = StreamController<SensorPoint>.broadcast();

  Stream<NearMissEvent> get eventStream => _eventController.stream;
  Stream<bool> get recordingStream => _recordingController.stream;
  Stream<SensorPoint> get pointStream => _pointController.stream;

  // ── Crash camera ────────────────────────────────────────────────────────────
  final CrashCameraService crashCamera = CrashCameraService();

  // ── State ───────────────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  final List<SensorPoint> _preBuffer = [];
  final List<SensorPoint> _postBuffer = [];
  bool _capturingPost = false;
  NearMissType? _pendingType;
  double _pendingPeakG = 0;
  double _pendingPeakGyro = 0;
  LatLng? _pendingLocation;

  String? _lastCrashVideoPath;
  String? get lastCrashVideoPath => _lastCrashVideoPath;

  final List<NearMissEvent> _events = [];
  List<NearMissEvent> get events => List.unmodifiable(_events);

  // ── Sensor subscriptions ────────────────────────────────────────────────────
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _gpsSub;
  Timer? _sampleTimer;

  double _ax = 0, _ay = 0, _az = 9.8;
  double _gx = 0, _gy = 0, _gz = 0;
  Position? _lastPosition;
  double _currentSpeed = 0;

  // ── Start / Stop ────────────────────────────────────────────────────────────
  Future<void> startRecording() async {
    if (_isRecording) return;

    // ─────────────────────────────────────────────────────────────────────────
    // FIX: Request BOTH location AND camera permissions together BEFORE
    // calling crashCamera.initialize(). Previously the camera was initialised
    // without the permission being granted, causing a black preview / crash on
    // Android and a silent failure on iOS.
    // ─────────────────────────────────────────────────────────────────────────
    final permStatuses = await [
      Permission.location,
      Permission.camera,
      Permission.microphone, // needed for video recording with audio
    ].request();

    final locationGranted = permStatuses[Permission.location]?.isGranted ?? false;
    final cameraGranted = permStatuses[Permission.camera]?.isGranted ?? false;

    if (!locationGranted) {
      debugPrint('NearMissService: location permission denied');
    }
    if (!cameraGranted) {
      debugPrint('NearMissService: camera permission denied — '
          'crash video will be unavailable');
      // Continue without camera: sensor recording still works.
    }

    // Only initialise the camera if permission was granted.
    if (cameraGranted) {
      await crashCamera.initialize();
    }

    _isRecording = true;
    _preBuffer.clear();
    _postBuffer.clear();
    _capturingPost = false;
    _recordingController.add(true);

    _accelSub = accelerometerEvents.listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
    });

    _gyroSub = gyroscopeEvents.listen((e) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
    });

    if (locationGranted) {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        _lastPosition = pos;
        _currentSpeed = pos.speed.clamp(0, double.infinity);
      });
    }

    _sampleTimer = Timer.periodic(
      const Duration(milliseconds: 100),
          (_) {
        if (_isRecording) _sample();
      },
    );
  }

  void stopRecording() {
    if (!_isRecording) return;
    _isRecording = false;
    _sampleTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();
    if (crashCamera.isRecording) crashCamera.stopRecording();
    _recordingController.add(false);
  }

  // ── Sample ──────────────────────────────────────────────────────────────────
  void _sample() {
    final gForce = _computeGForce(_ax, _ay, _az);
    final gyroMag = _computeGyroMag(_gx, _gy, _gz);

    final pos = _lastPosition != null
        ? LatLng(_lastPosition!.latitude, _lastPosition!.longitude)
        : const LatLng(0, 0);

    final point = SensorPoint(
      timestamp: DateTime.now(),
      position: pos,
      speed: _currentSpeed,
      accelX: _ax,
      accelY: _ay,
      accelZ: _az,
      gyroX: _gx,
      gyroY: _gy,
      gyroZ: _gz,
      gForce: gForce,
    );

    _pointController.add(point);

    if (_capturingPost) {
      _postBuffer.add(point);
      if (_postBuffer.length >= _kPostBufferSize) _flushEvent();
      return;
    }

    _preBuffer.add(point);
    if (_preBuffer.length > _kPreBufferSize) _preBuffer.removeAt(0);

    NearMissType? detected;

    if (gForce >= _kCollisionG) {
      detected = NearMissType.collision;
    } else if (gyroMag >= _kSwerveGyro) {
      detected = NearMissType.sharpSwerve;
    } else if (_ay < 0 && gForce >= _kHardBrakeG) {
      detected = NearMissType.hardBraking;
    } else if (_ay > 0 && gForce >= _kRapidAccelG) {
      detected = NearMissType.rapidAcceleration;
    }

    if (detected != null) {
      _pendingType = detected;
      _pendingPeakG = gForce;
      _pendingPeakGyro = gyroMag;
      _pendingLocation = pos;
      _postBuffer.clear();
      _capturingPost = true;

      // Only start crash recording if camera was initialised (permission OK)
      if (detected == NearMissType.collision &&
          crashCamera.isInitialized &&
          !crashCamera.isRecording) {
        crashCamera.startCrashRecording().then((path) {
          if (path != null) _lastCrashVideoPath = path;
        });
      }
    }
  }

  void _flushEvent() {
    _capturingPost = false;
    if (_pendingType == null) return;

    final allPoints = [..._preBuffer, ..._postBuffer];

    final videoPath = (_pendingType == NearMissType.collision)
        ? _lastCrashVideoPath
        : null;

    final event = NearMissEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: _pendingType!,
      peakGForce: _pendingPeakG,
      peakGyro: _pendingPeakGyro,
      location: _pendingLocation ?? const LatLng(0, 0),
      trackPoints: allPoints,
      duration: Duration(milliseconds: allPoints.length * 100),
      crashVideoPath: videoPath,
    );

    _events.add(event);
    _eventController.add(event);
    _pendingType = null;
    _postBuffer.clear();
  }

  // ── Math helpers ─────────────────────────────────────────────────────────────
  static double _computeGForce(double x, double y, double z) {
    final mag = math.sqrt(x * x + y * y + z * z);
    return (mag / 9.81 - 1.0).abs();
  }

  static double _computeGyroMag(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  void dispose() {
    stopRecording();
    crashCamera.dispose();
    _eventController.close();
    _recordingController.close();
    _pointController.close();
  }
}