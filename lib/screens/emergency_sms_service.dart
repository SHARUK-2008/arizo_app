import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emergency_contact_model.dart';

// ─── Emergency SMS Service ────────────────────────────────────────────────────
//
// Uses url_launcher (already in your pubspec) with the native sms: URI scheme.
// No third-party SMS package needed — works on Android & iOS.

class EmergencySmsService {
  static const String _contactsKey = 'emergency_contacts';

  // ── Contact Storage ────────────────────────────────────────────────────────

  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_contactsKey, encoded);
  }

  Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_contactsKey) ?? [];
    return raw
        .map((e) =>
        EmergencyContact.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<bool> hasContacts() async {
    final contacts = await loadContacts();
    return contacts.isNotEmpty;
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Request location permission (url_launcher needs no SMS permission).
  Future<bool> requestPermissions() async {
    final location = await Permission.locationWhenInUse.request();
    return location.isGranted;
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  String buildLocationUrl(Position position) =>
      'https://maps.google.com/?q=${position.latitude},${position.longitude}';

  // ── SMS via sms: URI ───────────────────────────────────────────────────────

  String buildDangerMessage({Position? position}) {
    final locationPart = position != null
        ? '\nMy location: ${buildLocationUrl(position)}'
        : '\n(Location unavailable)';
    return 'I AM IN DANGER! Please help me immediately.$locationPart';
  }

  /// Opens the native SMS app pre-filled with all contacts and the danger message.
  ///
  /// The sms: URI accepts multiple recipients separated by semicolons on Android
  /// and commas on iOS. We try both formats for maximum compatibility.
  ///
  /// The user just taps Send — no extra SMS permission required.
  Future<bool> sendDangerAlertToAll() async {
    final contacts = await loadContacts();
    if (contacts.isEmpty) return false;

    final position = await getCurrentLocation();
    final message = buildDangerMessage(position: position);
    final encodedMessage = Uri.encodeComponent(message);

    // Join phone numbers: Android uses ';', iOS uses ','
    final numbers = contacts.map((c) => c.phoneNumber).join(';');

    // Try Android format first (semicolon-separated)
    final androidUri = Uri.parse('sms:$numbers?body=$encodedMessage');
    if (await canLaunchUrl(androidUri)) {
      await launchUrl(androidUri);
      return true;
    }

    // Fallback: iOS / alternate format (comma-separated)
    final numbersIos = contacts.map((c) => c.phoneNumber).join(',');
    final iosUri = Uri.parse('sms:$numbersIos&body=$encodedMessage');
    if (await canLaunchUrl(iosUri)) {
      await launchUrl(iosUri);
      return true;
    }

    // Last resort: send one by one
    bool anySent = false;
    for (final contact in contacts) {
      final uri = Uri.parse(
          'sms:${contact.phoneNumber}?body=$encodedMessage');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        anySent = true;
      }
    }
    return anySent;
  }
}