import 'dart:math';

import '../screens/crash_triage_models.dart';
import 'emergency_sms_service.dart';

// ─── Crash Triage Service ─────────────────────────────────────────────────────

class CrashTriageService {
  /// G-force threshold to trigger crash detection (25G ≈ serious automotive impact)
  static const double crashThresholdG = 25.0;

  final EmergencySmsService _smsService = EmergencySmsService();

  // ── Core Detection ─────────────────────────────────────────────────────────

  /// Converts raw accelerometer XYZ values (m/s²) to total G-force magnitude
  double calculateGForce(double x, double y, double z) {
    final magnitude = sqrt(x * x + y * y + z * z);
    return magnitude / 9.80665;
  }

  /// Returns true when measured G-force exceeds the crash threshold
  bool isCrashDetected(double gForce) => gForce >= crashThresholdG;

  /// Classifies crash severity based on measured G-force
  CrashSeverity classifySeverity(double gForce) {
    if (gForce < 35) return CrashSeverity.minor;
    if (gForce < 55) return CrashSeverity.moderate;
    return CrashSeverity.severe;
  }

  // ── Descriptions ───────────────────────────────────────────────────────────

  /// Human-readable description of severity
  String severityDescription(CrashSeverity severity) {
    switch (severity) {
      case CrashSeverity.minor:
        return 'Low-speed impact. Check for injuries and vehicle damage.';
      case CrashSeverity.moderate:
        return 'Moderate impact. Occupant injuries likely. Emergency response advised.';
      case CrashSeverity.severe:
        return 'High-energy impact. Serious injuries probable. Immediate emergency response required.';
    }
  }

  /// Recommended action based on severity
  String recommendedAction(CrashSeverity severity) {
    switch (severity) {
      case CrashSeverity.minor:
        return 'Assess injuries, move to safety if possible.';
      case CrashSeverity.moderate:
        return 'Do not move victims. Call 108 (Ambulance) immediately.';
      case CrashSeverity.severe:
        return 'Call 112 now. Begin triage. Do not move victims.';
    }
  }

  // ── SMS Alert (replaces emergency call) ────────────────────────────────────

  /// Call this when a crash is detected.
  ///
  /// - If no emergency contacts are saved, returns [CrashAlertResult.noContacts]
  ///   so the UI can prompt the user to add one.
  /// - Otherwise sends "I AM IN DANGER + location" to every saved contact and
  ///   returns [CrashAlertResult.sent].
  Future<CrashAlertResult> triggerDangerAlert() async {
    // Guard: contacts must be configured first
    final hasContacts = await _smsService.hasContacts();
    if (!hasContacts) return CrashAlertResult.noContacts;

    // Guard: need SMS + location permissions
    final hasPermissions = await _smsService.requestPermissions();
    if (!hasPermissions) return CrashAlertResult.permissionDenied;

    final sent = await _smsService.sendDangerAlertToAll();
    return sent ? CrashAlertResult.sent : CrashAlertResult.failed;
  }

  /// Convenience: check contacts before showing the crash screen
  Future<bool> hasEmergencyContacts() => _smsService.hasContacts();
}

// ── Result enum ───────────────────────────────────────────────────────────────

enum CrashAlertResult {
  /// SMS sent to at least one contact
  sent,

  /// No emergency contacts have been saved yet
  noContacts,

  /// SMS or location permission was denied
  permissionDenied,

  /// All SMS sends failed
  failed,
}