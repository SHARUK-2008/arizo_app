import 'package:latlong2/latlong.dart';

enum NearMissType { hardBraking, sharpSwerve, rapidAcceleration, collision }

class SensorPoint {
  final DateTime timestamp;
  final LatLng position;
  final double speed;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double gForce;

  const SensorPoint({
    required this.timestamp,
    required this.position,
    required this.speed,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.gForce,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'lat': position.latitude,
    'lng': position.longitude,
    'speed': speed,
    'accelX': accelX,
    'accelY': accelY,
    'accelZ': accelZ,
    'gyroX': gyroX,
    'gyroY': gyroY,
    'gyroZ': gyroZ,
    'gForce': gForce,
  };

  factory SensorPoint.fromJson(Map<String, dynamic> j) => SensorPoint(
    timestamp: DateTime.parse(j['timestamp']),
    position: LatLng(j['lat'], j['lng']),
    speed:   (j['speed']  as num).toDouble(),
    accelX:  (j['accelX'] as num).toDouble(),
    accelY:  (j['accelY'] as num).toDouble(),
    accelZ:  (j['accelZ'] as num).toDouble(),
    gyroX:   (j['gyroX']  as num).toDouble(),
    gyroY:   (j['gyroY']  as num).toDouble(),
    gyroZ:   (j['gyroZ']  as num).toDouble(),
    gForce:  (j['gForce'] as num).toDouble(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// NearMissEvent
// ─────────────────────────────────────────────────────────────────────────────

class NearMissEvent {
  final String id;
  final DateTime timestamp;
  final NearMissType type;
  final double peakGForce;
  final double peakGyro;
  final LatLng location;
  final List<SensorPoint> trackPoints;
  final Duration duration;

  /// Path to the front-camera crash video. Only populated for collision events.
  final String? crashVideoPath;

  const NearMissEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.peakGForce,
    required this.peakGyro,
    required this.location,
    required this.trackPoints,
    required this.duration,
    this.crashVideoPath,
  });

  // ── Computed getters ──────────────────────────────────────────────────────

  String get typeLabel {
    switch (type) {
      case NearMissType.hardBraking:       return 'Hard Braking';
      case NearMissType.sharpSwerve:       return 'Sharp Swerve';
      case NearMissType.rapidAcceleration: return 'Rapid Acceleration';
      case NearMissType.collision:         return 'Collision Detected';
    }
  }

  String get severityLabel {
    if (peakGForce > 3.5) return 'CRITICAL';
    if (peakGForce > 2.5) return 'HIGH';
    if (peakGForce > 1.5) return 'MEDIUM';
    return 'LOW';
  }

  /// 0.0–1.0 severity score (capped at 5 g = 1.0).
  double get severityScore => (peakGForce / 5.0).clamp(0.0, 1.0);

  bool get hasCrashVideo => crashVideoPath != null;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id':            id,
    'timestamp':     timestamp.toIso8601String(),
    'type':          type.name,
    'peakGForce':    peakGForce,
    'peakGyro':      peakGyro,
    'lat':           location.latitude,
    'lng':           location.longitude,
    'trackPoints':   trackPoints.map((p) => p.toJson()).toList(),
    'durationMs':    duration.inMilliseconds,
    'crashVideoPath': crashVideoPath,
  };

  factory NearMissEvent.fromJson(Map<String, dynamic> j) => NearMissEvent(
    id:          j['id'] as String,
    timestamp:   DateTime.parse(j['timestamp'] as String),
    type:        NearMissType.values.byName(j['type'] as String),
    peakGForce:  (j['peakGForce'] as num).toDouble(),
    peakGyro:    (j['peakGyro']   as num).toDouble(),
    location:    LatLng(
      (j['lat'] as num).toDouble(),
      (j['lng'] as num).toDouble(),
    ),
    trackPoints: (j['trackPoints'] as List<dynamic>)
        .map((e) => SensorPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    duration:    Duration(milliseconds: (j['durationMs'] as num).toInt()),
    crashVideoPath: j['crashVideoPath'] as String?,
  );

  // ── Mock factory (development / preview) ──────────────────────────────────

  /// Generates a realistic mock event with a 20-point sensor track.
  /// [origin] defaults to Madurai, Tamil Nadu (9.9252° N, 78.1198° E).
  factory NearMissEvent.mock({
    NearMissType type = NearMissType.hardBraking,
    LatLng? origin,
  }) {
    final base = origin ?? const LatLng(9.9252, 78.1198);
    final now  = DateTime.now();
    const steps = 30;

    final points = List.generate(steps, (i) {
      final frac = i / (steps - 1);
      // G-force ramps up to a peak at 70 % then eases off
      final gCurve = frac < 0.7 ? frac / 0.7 : (1.0 - frac) / 0.3;
      final g = 1.0 + gCurve * (type == NearMissType.collision ? 4.5 : 2.8);

      return SensorPoint(
        timestamp: now.subtract(Duration(seconds: steps - i)),
        position:  LatLng(
          base.latitude  + i * 0.00012,
          base.longitude + i * 0.00008,
        ),
        speed:  (12.0 + frac * 8.0),        // 12 → 20 m/s
        accelX: g * 0.25,
        accelY: g * 0.95,
        accelZ: 9.81,
        gyroX:  gCurve * 0.5,
        gyroY:  gCurve * 0.3,
        gyroZ:  gCurve * 0.15,
        gForce: g,
      );
    });

    final peak =
    points.map((p) => p.gForce).reduce((a, b) => a > b ? a : b);

    return NearMissEvent(
      id:          'mock-${now.millisecondsSinceEpoch}',
      timestamp:   now,
      type:        type,
      peakGForce:  peak,
      peakGyro:    1.4,
      location:    base,
      trackPoints: points,
      duration:    Duration(seconds: steps),
      crashVideoPath:
      type == NearMissType.collision ? '/mock/crash_2024.mp4' : null,
    );
  }
}