import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SOSContact {
  final String name;
  final String phone;

  const SOSContact({
    required this.name,
    required this.phone,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
  };

  factory SOSContact.fromJson(Map<String, dynamic> j) {
    return SOSContact(
      name: j['name'] as String,
      phone: j['phone'] as String,
    );
  }
}

class SOSService {
  static const _channel = MethodChannel('com.example.near_miss_detector/sms');
  static const _contactsKey = 'sos_contacts_v2';
  static const _firstLaunchKey = 'first_launch_done';

  // ================= CONTACTS =================

  static Future<List<SOSContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_contactsKey) ?? [];
    return raw
        .map(
          (e) => SOSContact.fromJson(
        jsonDecode(e) as Map<String, dynamic>,
      ),
    )
        .toList();
  }

  static Future<void> addContact(SOSContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await loadContacts();
    contacts.add(contact);
    await prefs.setStringList(
      _contactsKey,
      contacts.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  static Future<void> removeContact(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await loadContacts();
    if (index < 0 || index >= contacts.length) return;
    contacts.removeAt(index);
    await prefs.setStringList(
      _contactsKey,
      contacts.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_firstLaunchKey) ?? true) {
      await prefs.setBool(_firstLaunchKey, false);
      return true;
    }
    return false;
  }

  // ================= PHONE FORMAT =================

  static String formatPhoneNumber(String phone) {
    phone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    return '+91$phone';
  }

  // ================= SMS PERMISSION =================

  static Future<bool> requestSMSPermission() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();
    return statuses[Permission.sms]?.isGranted ?? false;
  }

  static Future<bool> checkSMSPermission() async {
    return await Permission.sms.isGranted;
  }

  // ================= GPS =================

  /// Checks and requests location permission.
  /// Returns true if permission is granted (either fine or coarse).
  static Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log('Location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _log('Location permission denied: $permission');
      return false;
    }
    return true;
  }

  /// Gets current GPS position with a multi-strategy approach:
  ///
  /// 1. First try `getLastKnownPosition()` — instant, no timeout risk.
  /// 2. Then try a high-accuracy fresh fix (15 s window, no timeLimit in
  ///    LocationSettings to avoid Android silent-failure bug).
  /// 3. If that throws/times-out, retry with medium accuracy (faster TTFF).
  ///
  /// The caller in [_CrashTriageScreenState._fetchPositionWithRetry] wraps
  /// each call in its own `.timeout()`, so we don't double-set timeouts here.
  static Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) return null;

      // ── Strategy 1: Last known position (instant) ──────────────────────
      // Use as a fast fallback while the fresh fix is pending.
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _log(
            'Last known position: '
                '${lastKnown.latitude}, ${lastKnown.longitude} '
                '(±${lastKnown.accuracy.toStringAsFixed(0)} m)',
          );
        }
      } catch (e) {
        _log('getLastKnownPosition failed: $e');
      }

      // ── Strategy 2: Fresh high-accuracy fix ────────────────────────────
      // IMPORTANT: Do NOT set timeLimit inside LocationSettings on Android —
      // it silently returns null instead of throwing, making retries useless.
      // The caller's .timeout() handles the deadline instead.
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            // No timeLimit here — let the caller's .timeout() control this
          ),
        );
        _log(
          'Fresh GPS fix: ${fresh.latitude}, ${fresh.longitude} '
              '(±${fresh.accuracy.toStringAsFixed(0)} m)',
        );
        return fresh;
      } catch (e) {
        _log('High-accuracy GPS failed: $e — trying medium accuracy');
      }

      // ── Strategy 3: Medium-accuracy fallback (faster TTFF) ────────────
      try {
        final medium = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        _log(
          'Medium-accuracy GPS fix: ${medium.latitude}, ${medium.longitude} '
              '(±${medium.accuracy.toStringAsFixed(0)} m)',
        );
        return medium;
      } catch (e) {
        _log('Medium-accuracy GPS failed: $e');
      }

      // ── Strategy 4: Return last known as final fallback ────────────────
      if (lastKnown != null) {
        _log('Returning last known position as final fallback');
      }
      return lastKnown;
    } catch (e) {
      _log('getCurrentPosition unexpected error: $e');
      return null;
    }
  }

  static String formatPosition(Position pos) {
    final lat = pos.latitude.toStringAsFixed(5);
    final lng = pos.longitude.toStringAsFixed(5);
    return '$lat° N, $lng° E';
  }

  // ================= BUILD LOCATION STRING =================

  /// Returns a detailed location block for the SMS:
  ///   Coords: 10.79417° N, 78.70003° E (±12 m)
  ///   Maps: https://maps.google.com/?q=10.79417,78.70003
  static String _buildLocationText(Position pos) {
    final lat = pos.latitude.toStringAsFixed(5);
    final lng = pos.longitude.toStringAsFixed(5);

    final latDir = pos.latitude >= 0 ? 'N' : 'S';
    final lngDir = pos.longitude >= 0 ? 'E' : 'W';

    final coordLine = 'Coords: $lat° $latDir, $lng° $lngDir';
    final mapsLink =
        'Maps: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';

    final accuracyLine =
    (pos.accuracy > 0 && pos.accuracy <= 500)
        ? ' (±${pos.accuracy.toStringAsFixed(0)} m)'
        : '';

    return '$coordLine$accuracyLine\n$mapsLink';
  }

  // ================= SEND SMS =================

  static Future<bool> sendSMSToAll({
    required List<SOSContact> contacts,
    required String severity,
    required double gForce,
    Position? position,
  }) async {
    if (contacts.isEmpty) return false;

    final hasPermission = await requestSMSPermission();
    if (!hasPermission) return false;

    final locationPart = position != null
        ? _buildLocationText(position)
        : 'Location: unavailable';

    final message =
        'SOS ALERT: Crash detected - $severity impact '
        '(${gForce.toStringAsFixed(1)}g).\n'
        '$locationPart\n'
        'Call immediately or dial 112.';

    bool anySuccess = false;

    for (final contact in contacts) {
      try {
        final formattedNumber = formatPhoneNumber(contact.phone);
        _log('Sending SMS to ${contact.name} at $formattedNumber');

        final bool success = await _channel.invokeMethod('sendSms', {
          'phone': formattedNumber,
          'message': message,
        });

        await Future.delayed(const Duration(seconds: 2));

        if (success) {
          anySuccess = true;
          _log('SMS sent to ${contact.name}');
        } else {
          _log('SMS failed to ${contact.name}');
        }
      } catch (e) {
        _log('SMS to ${contact.name} failed: $e');
      }
    }

    return anySuccess;
  }

  // ================= EMERGENCY CALL =================

  static Future<void> callEmergencyServices({
    String number = '112',
  }) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ================= LOG =================

  static void _log(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'SOSService');
    }
  }
}