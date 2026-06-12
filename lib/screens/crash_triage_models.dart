import 'package:flutter/material.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum TriagePhase { monitoring, detected, triaging, completed }

enum CrashSeverity { minor, moderate, severe }

// ─── Crash Event ──────────────────────────────────────────────────────────────

class CrashEvent {
  final DateTime timestamp;
  final double gForce;
  final CrashSeverity severity;
  final double? latitude;
  final double? longitude;

  const CrashEvent({
    required this.timestamp,
    required this.gForce,
    required this.severity,
    this.latitude,
    this.longitude,
  });
}

// ─── Triage Step ──────────────────────────────────────────────────────────────

class TriageStep {
  final String emoji;
  final String title;
  final String description;
  final List<String> checkpoints;
  final String actionLabel;
  final IconData actionIcon;
  final Color color;
  final String urgency;

  const TriageStep({
    required this.emoji,
    required this.title,
    required this.description,
    required this.checkpoints,
    required this.actionLabel,
    required this.actionIcon,
    required this.color,
    required this.urgency,
  });
}

// ─── Triage Step Data ─────────────────────────────────────────────────────────

const List<TriageStep> triageSteps = [
  TriageStep(
    emoji: '🔴',
    title: 'Scene Safety',
    description:
    'Before approaching, ensure the scene is safe for you and others. Turn on hazard lights and set up warning triangles if available.',
    checkpoints: [
      'Turn on vehicle hazard lights',
      'Check for fuel leaks, fire, or unstable vehicles',
      'Set warning triangle 50m behind crash',
      'Keep bystanders at safe distance',
    ],
    actionLabel: 'Scene is Safe',
    actionIcon: Icons.check_circle_outline_rounded,
    color: Color(0xFFFF3B30),
    urgency: 'IMMEDIATE',
  ),
  TriageStep(
    emoji: '🫁',
    title: 'Check Responsiveness',
    description:
    'Approach each victim and assess level of consciousness. Call out loudly and tap their shoulders firmly.',
    checkpoints: [
      'Tap shoulders and call loudly — "Are you OK?"',
      'Check for normal breathing (look, listen, feel)',
      'Do NOT move victim if spinal injury suspected',
      'Mark unresponsive victims as Priority 1',
    ],
    actionLabel: 'Responsiveness Checked',
    actionIcon: Icons.hearing_rounded,
    color: Color(0xFFFF6B00),
    urgency: 'CRITICAL',
  ),
  TriageStep(
    emoji: '🩸',
    title: 'Control Bleeding',
    description:
    'Apply direct pressure to visible wounds. Use cloth, clothing, or a tourniquet if available for severe limb bleeding.',
    checkpoints: [
      'Apply firm direct pressure to wounds',
      'Do NOT remove embedded objects',
      'Apply tourniquet 5cm above severe limb bleeding',
      'Note time of tourniquet application',
    ],
    actionLabel: 'Bleeding Controlled',
    actionIcon: Icons.healing_rounded,
    color: Color(0xFFFF9F0A),
    urgency: 'URGENT',
  ),
  TriageStep(
    emoji: '🫀',
    title: 'Airway & Breathing',
    description:
    'For unconscious victims, tilt head back gently and lift the chin to open airway. Check for breathing every 10 seconds.',
    checkpoints: [
      'Tilt head back, lift chin to open airway',
      'Remove visible obstructions from mouth',
      'If not breathing — begin CPR (30 compressions : 2 breaths)',
      'Place breathing victim in recovery position',
    ],
    actionLabel: 'Airway Secured',
    actionIcon: Icons.air_rounded,
    color: Color(0xFF00E5CC),
    urgency: 'CRITICAL',
  ),
  TriageStep(
    emoji: '📍',
    title: 'Confirm Location & Wait',
    description:
    'Confirm exact GPS coordinates are sent to emergency services. Stay on the line with dispatch and keep victims warm and calm.',
    checkpoints: [
      'Verify GPS location was sent with SOS',
      'Stay on call with 112 dispatcher',
      'Keep victims warm — use jackets/blankets',
      'Do not give food or water to injured',
      'Wait for emergency services to arrive',
    ],
    actionLabel: 'Waiting for Help',
    actionIcon: Icons.location_on_rounded,
    color: Color(0xFF30D158),
    urgency: 'HOLD',
  ),
];