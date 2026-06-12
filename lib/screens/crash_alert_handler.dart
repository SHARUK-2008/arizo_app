import 'package:flutter/material.dart';

import 'crash_triage_service.dart';
import 'emergency_contact_screen.dart';

// ─── Crash Alert Handler ──────────────────────────────────────────────────────
//
// Drop this mixin into any screen that receives accelerometer data and needs to
// respond to detected crashes.

mixin CrashAlertHandler<T extends StatefulWidget> on State<T> {
  final CrashTriageService _triageService = CrashTriageService();
  bool _alertInProgress = false;

  /// Call this from your accelerometer listener when a crash is detected.
  ///
  /// It handles the full flow:
  ///   1. Guard against double-trigger.
  ///   2. If no contacts saved → navigate to setup screen.
  ///   3. Otherwise send danger SMS and show result snackbar.
  Future<void> handleCrashDetected() async {
    if (_alertInProgress) return;
    _alertInProgress = true;

    try {
      // Check contacts first — avoids spinning during an urgent moment
      final hasContacts = await _triageService.hasEmergencyContacts();
      if (!hasContacts) {
        _showNoContactsDialog();
        return;
      }

      _showSendingIndicator();
      final result = await _triageService.triggerDangerAlert();
      _hideSendingIndicator();

      _showAlertResult(result);
    } finally {
      _alertInProgress = false;
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  void _showNoContactsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B30)),
            SizedBox(width: 8),
            Text('No Emergency Contact', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'You have not set up any emergency contacts.\n\n'
              'Please add at least one contact so that a danger SMS with your location can be sent when a crash is detected.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyContactScreen()),
              );
            },
            child: const Text('Add Contact', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  OverlayEntry? _loadingOverlay;

  void _showSendingIndicator() {
    _loadingOverlay = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: ColoredBox(
          color: Color(0x99000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFFFF3B30)),
                SizedBox(height: 16),
                Text('Sending danger alert…',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_loadingOverlay!);
  }

  void _hideSendingIndicator() {
    _loadingOverlay?.remove();
    _loadingOverlay = null;
  }

  void _showAlertResult(CrashAlertResult result) {
    final (message, color) = switch (result) {
      CrashAlertResult.sent => (
      '✓ Danger SMS sent to your emergency contacts with your location.',
      Colors.green
      ),
      CrashAlertResult.noContacts => (
      'No emergency contacts found. Please add a contact first.',
      Colors.orange
      ),
      CrashAlertResult.permissionDenied => (
      'SMS or location permission denied. Please enable in Settings.',
      Colors.orange
      ),
      CrashAlertResult.failed => (
      'Failed to send SMS. Check your network and try again.',
      Colors.red
      ),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }
}