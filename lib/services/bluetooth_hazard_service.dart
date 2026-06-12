// lib/services/bluetooth_hazard_service.dart
//
// MIGRATED from flutter_bluetooth_serial → nearby_connections
//
// WHY: flutter_bluetooth_serial cannot register an SPP server socket on
// modern Android. Both phones were dialling outward with nobody listening,
// so the connection always failed. nearby_connections (Google Nearby API)
// handles discovery + server/client roles automatically — no pairing, no
// Android Settings setup, no SPP UUID issues.
//
// pubspec.yaml — add these, remove flutter_bluetooth_serial:
//   nearby_connections: ^4.1.0
//
// AndroidManifest.xml permissions to add:
//   <uses-permission android:name="android.permission.BLUETOOTH" />
//   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
//   <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
//   <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
//   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
//   <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
//   <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
//   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
//   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
//   <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// ════════════════════════════════════════════════════════════════════
// HAZARD TYPES
// ════════════════════════════════════════════════════════════════════

enum HazardType {
  accident,
  pothole,
  fog,
  flood,
  debris,
  police,
  animal,
  breakdown,
}

extension HazardTypeExt on HazardType {
  String get emoji {
    switch (this) {
      case HazardType.accident:  return '💥';
      case HazardType.pothole:   return '🕳️';
      case HazardType.fog:       return '🌫️';
      case HazardType.flood:     return '🌊';
      case HazardType.debris:    return '🪨';
      case HazardType.police:    return '🚓';
      case HazardType.animal:    return '🐄';
      case HazardType.breakdown: return '🚗';
    }
  }

  String get label {
    switch (this) {
      case HazardType.accident:  return 'Accident';
      case HazardType.pothole:   return 'Pothole';
      case HazardType.fog:       return 'Dense Fog';
      case HazardType.flood:     return 'Flood';
      case HazardType.debris:    return 'Debris';
      case HazardType.police:    return 'Police';
      case HazardType.animal:    return 'Animal';
      case HazardType.breakdown: return 'Breakdown';
    }
  }

  int get severity {
    switch (this) {
      case HazardType.accident:
      case HazardType.flood:
        return 3;
      case HazardType.fog:
      case HazardType.debris:
      case HazardType.animal:
      case HazardType.breakdown:
        return 2;
      default:
        return 1;
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// HAZARD ALERT MODEL
// ════════════════════════════════════════════════════════════════════

class HazardAlert {
  final String id;
  final HazardType type;
  final double latitude;
  final double longitude;
  final String reportedBy;
  final DateTime timestamp;
  int verificationCount;
  bool isVerified;
  double? _cachedDistance;

  HazardAlert({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.reportedBy,
    required this.timestamp,
    this.verificationCount = 1,
    this.isVerified = false,
  });

  double get distanceMeters => _cachedDistance ?? 0;

  String get distanceLabel {
    final d = _cachedDistance;
    if (d == null) return '?m';
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  void updateDistance(double lat, double lng) {
    _cachedDistance =
        Geolocator.distanceBetween(lat, lng, latitude, longitude);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'lat': latitude,
    'lng': longitude,
    'by': reportedBy,
    'ts': timestamp.millisecondsSinceEpoch,
    'vc': verificationCount,
  };

  factory HazardAlert.fromJson(Map<String, dynamic> json) =>
      HazardAlert(
        id: json['id'] as String,
        type: HazardType.values[json['type'] as int],
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        reportedBy: json['by'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['ts'] as int),
        verificationCount: (json['vc'] as int?) ?? 1,
        isVerified: ((json['vc'] as int?) ?? 1) >= 2,
      );
}

// ════════════════════════════════════════════════════════════════════
// CHAT MESSAGE MODEL
// ════════════════════════════════════════════════════════════════════

enum ChatMessageType { text, hazardAlert, system }

class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final ChatMessageType type;
  final bool isMe;
  final Map<String, dynamic>? meta;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.type = ChatMessageType.text,
    this.isMe = false,
    this.meta,
  });

  String get timeLabel {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sid': senderId,
    'msg': content,
    'ts': timestamp.millisecondsSinceEpoch,
    'type': type.index,
    if (meta != null) 'meta': meta,
  };

  factory ChatMessage.fromJson(
      Map<String, dynamic> json, String myId) =>
      ChatMessage(
        id: json['id'] as String,
        senderId: json['sid'] as String,
        content: json['msg'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['ts'] as int),
        type: ChatMessageType
            .values[(json['type'] as int?) ?? 0],
        isMe: (json['sid'] as String) == myId,
        meta: json['meta'] as Map<String, dynamic>?,
      );

  factory ChatMessage.system(String text) => ChatMessage(
    id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
    senderId: 'system',
    content: text,
    timestamp: DateTime.now(),
    type: ChatMessageType.system,
  );
}

// ════════════════════════════════════════════════════════════════════
// CHAT PEER
// ════════════════════════════════════════════════════════════════════

class ChatPeer {
  final String id;
  final String address;
  DateTime lastSeen;
  bool isTyping;

  ChatPeer({
    required this.id,
    required this.address,
    required this.lastSeen,
    this.isTyping = false,
  });

  bool get isOnline =>
      DateTime.now().difference(lastSeen).inSeconds < 45;
}

// ════════════════════════════════════════════════════════════════════
// NETWORK STATUS
// ════════════════════════════════════════════════════════════════════

enum NetworkStatus { idle, starting, active, error }

extension NetworkStatusExt on NetworkStatus {
  bool get isActive => this == NetworkStatus.active;

  String get label {
    switch (this) {
      case NetworkStatus.idle:
        return 'Idle — tap Start';
      case NetworkStatus.starting:
        return 'Starting mesh…';
      case NetworkStatus.active:
        return 'Mesh active — scanning for nearby devices';
      case NetworkStatus.error:
        return 'Error — check permissions';
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// BLUETOOTH HAZARD SERVICE  (nearby_connections backend)
// ════════════════════════════════════════════════════════════════════

class BluetoothHazardService {
  static const String _serviceId = 'com.guardiandrive.mesh';

  // ── Streams ─────────────────────────────────────────────────────
  final _alertController =
  StreamController<List<HazardAlert>>.broadcast();
  final _statusController =
  StreamController<NetworkStatus>.broadcast();
  final _peersController =
  StreamController<Set<String>>.broadcast();
  final _messageController =
  StreamController<List<ChatMessage>>.broadcast();
  final _typingController =
  StreamController<String?>.broadcast();
  final _chatPeerController =
  StreamController<Map<String, ChatPeer>>.broadcast();

  Stream<List<HazardAlert>> get alertStream =>
      _alertController.stream;
  Stream<NetworkStatus> get statusStream =>
      _statusController.stream;
  Stream<Set<String>> get peersStream =>
      _peersController.stream;
  Stream<List<ChatMessage>> get messageStream =>
      _messageController.stream;
  Stream<String?> get typingStream =>
      _typingController.stream;
  Stream<Map<String, ChatPeer>> get chatPeerStream =>
      _chatPeerController.stream;

  // ── State ────────────────────────────────────────────────────────
  final Map<String, HazardAlert> _alertMap = {};
  // key = nearby endpointId
  final Map<String, String> _endpointToId = {};
  final List<ChatMessage> _messages = [];
  final Map<String, ChatPeer> _chatPeers = {};
  final Set<String> _connectedEndpoints = {};
  // track seen message IDs to drop duplicates
  final Set<String> _seenMessageIds = {};

  List<HazardAlert> get alerts {
    final list = _alertMap.values.toList();
    list.sort(
            (a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return list;
  }

  Set<String> get peers =>
      _endpointToId.values.toSet();

  List<ChatMessage> get messages =>
      List.unmodifiable(_messages);

  Map<String, ChatPeer> get chatPeers =>
      Map.unmodifiable(_chatPeers);

  double currentLat = 0;
  double currentLng = 0;

  // Use device name + random suffix so nearby devices are identifiable
  final String _myId =
      'GD_${Random().nextInt(9999).toString().padLeft(4, '0')}';
  String get myId => _myId;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Timer? _cleanupTimer;
  Timer? _locationTimer;
  Timer? _heartbeatTimer;
  Timer? _typingResetTimer;

  final Nearby _nearby = Nearby();

  // ════════════════════════════════════════════════════════════════
  // PERMISSIONS
  // ════════════════════════════════════════════════════════════════

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
    ].request();

    final allGranted = statuses.values
        .every((s) => s == PermissionStatus.granted);

    if (!allGranted) {
      debugPrint('Some permissions denied: $statuses');
    }
    return allGranted;
  }

  // ════════════════════════════════════════════════════════════════
  // START — advertise + discover simultaneously (true mesh)
  // ════════════════════════════════════════════════════════════════

  Future<void> start() async {
    if (_isRunning) return;
    _emitStatus(NetworkStatus.starting);

    final granted = await _requestPermissions();
    if (!granted) {
      _emitStatus(NetworkStatus.error);
      _addSystemMessage(
          'Permissions denied. Please grant all permissions and try again.');
      return;
    }

    await _updateLocation();

    try {
      // ADVERTISE — this phone becomes discoverable
      await _nearby.startAdvertising(
        _myId,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );

      // DISCOVER — also scan for other advertisers
      await _nearby.startDiscovery(
        _myId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );

      _isRunning = true;
      _emitStatus(NetworkStatus.active);
      _addSystemMessage(
          'Mesh started — your ID is $_myId\n'
              'Scanning for nearby GuardianDrive phones…');

      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 15),
            (_) => _broadcast({'type': 'hello', 'id': _myId}),
      );
      _locationTimer = Timer.periodic(
        const Duration(seconds: 10),
            (_) => _updateLocation(),
      );
      _cleanupTimer = Timer.periodic(
        const Duration(minutes: 2),
            (_) => _cleanupStaleAlerts(),
      );
    } catch (e) {
      debugPrint('Nearby start error: $e');
      _emitStatus(NetworkStatus.error);
      _addSystemMessage('Failed to start mesh: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // NEARBY CALLBACKS
  // ════════════════════════════════════════════════════════════════

  // Called on BOTH sides when a connection is initiated
  void _onConnectionInitiated(
      String endpointId, ConnectionInfo info) {
    debugPrint(
        'Connection initiated: $endpointId / ${info.endpointName}');
    // Always accept incoming connections
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _onConnectionResult(
      String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('Connected to endpoint: $endpointId');
      _connectedEndpoints.add(endpointId);
      // Greet the new peer
      _sendToEndpoint(
          endpointId, {'type': 'hello', 'id': _myId});
    } else {
      debugPrint(
          'Connection failed to $endpointId: $status');
      _connectedEndpoints.remove(endpointId);
      _endpointToId.remove(endpointId);
    }
    _emitPeers();
  }

  void _onDisconnected(String endpointId) {
    debugPrint('Disconnected: $endpointId');
    final peerId = _endpointToId.remove(endpointId);
    _connectedEndpoints.remove(endpointId);
    if (peerId != null) {
      _chatPeers.remove(peerId);
      _addSystemMessage('$peerId disconnected');
      _chatPeerController
          .add(Map.unmodifiable(_chatPeers));
    }
    _emitPeers();
  }

  // Called when a nearby device is found during discovery
  void _onEndpointFound(
      String endpointId, String endpointName,
      String serviceId) {
    debugPrint(
        'Endpoint found: $endpointId ($endpointName)');
    if (_connectedEndpoints.contains(endpointId)) {
      return;
    }
    // Request connection — this triggers _onConnectionInitiated
    // on both phones
    _nearby.requestConnection(
      _myId,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onEndpointLost(String? endpointId) {
    if (endpointId == null) return;
    debugPrint('Endpoint lost: $endpointId');
  }

  // ════════════════════════════════════════════════════════════════
  // PAYLOAD (incoming data)
  // ════════════════════════════════════════════════════════════════

  void _onPayloadReceived(
      String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null) return;
    try {
      final raw = utf8.decode(bytes);
      final packet =
      jsonDecode(raw) as Map<String, dynamic>;
      _handlePacket(packet, endpointId);
    } catch (e) {
      debugPrint('Payload parse error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // PACKET HANDLER
  // ════════════════════════════════════════════════════════════════

  void _handlePacket(
      Map<String, dynamic> packet, String fromEndpoint) {
    final packetType = packet['type'] as String?;
    final senderId =
        packet['id'] as String? ?? fromEndpoint;

    if (senderId == _myId) return;

    _endpointToId[fromEndpoint] = senderId;

    switch (packetType) {
      case 'hello':
        if (!_chatPeers.containsKey(senderId)) {
          _chatPeers[senderId] = ChatPeer(
            id: senderId,
            address: fromEndpoint,
            lastSeen: DateTime.now(),
          );
          _addSystemMessage(
              '$senderId joined the mesh');
        } else {
          _chatPeers[senderId]!.lastSeen =
              DateTime.now();
        }
        _chatPeerController
            .add(Map.unmodifiable(_chatPeers));
        _emitPeers();
        _sendToEndpoint(fromEndpoint,
            {'type': 'hello_ack', 'id': _myId});
        break;

      case 'hello_ack':
        if (!_chatPeers.containsKey(senderId)) {
          _chatPeers[senderId] = ChatPeer(
            id: senderId,
            address: fromEndpoint,
            lastSeen: DateTime.now(),
          );
          _addSystemMessage(
              'Connected to $senderId');
        } else {
          _chatPeers[senderId]!.lastSeen =
              DateTime.now();
        }
        _chatPeerController
            .add(Map.unmodifiable(_chatPeers));
        _emitPeers();
        break;

      case 'bye':
        _chatPeers.remove(senderId);
        _addSystemMessage('$senderId left');
        _chatPeerController
            .add(Map.unmodifiable(_chatPeers));
        _emitPeers();
        break;

      case 'hazard':
        final data =
        packet['data'] as Map<String, dynamic>;
        final alert = HazardAlert.fromJson(data);
        if (DateTime.now()
            .difference(alert.timestamp)
            .inMinutes >
            10) {
          return;
        }
        alert.updateDistance(currentLat, currentLng);
        final isNew = !_alertMap.containsKey(alert.id);
        if (isNew) {
          _alertMap[alert.id] = alert;
        } else {
          _alertMap[alert.id]!.verificationCount++;
          _alertMap[alert.id]!.isVerified =
              _alertMap[alert.id]!.verificationCount >= 2;
        }
        _alertController.add(alerts);
        if (isNew) {
          final hopCount =
              (packet['hop'] as int? ?? 0) + 1;
          if (hopCount < 3) {
            _broadcastExcept(fromEndpoint, {
              'type': 'hazard',
              'id': _myId,
              'hop': hopCount,
              'data': data,
            });
          }
        }
        break;

      case 'msg':
        final data =
        packet['data'] as Map<String, dynamic>?;
        if (data == null) return;
        final msgId = data['id'] as String?;
        if (msgId != null &&
            _seenMessageIds.contains(msgId)) {
          return;
        }
        if (msgId != null) {
          _seenMessageIds.add(msgId);
        }
        if (_chatPeers.containsKey(senderId)) {
          _chatPeers[senderId]!.lastSeen =
              DateTime.now();
        }
        final msg =
        ChatMessage.fromJson(data, _myId);
        _messages.add(msg);
        _messages.sort((a, b) =>
            a.timestamp.compareTo(b.timestamp));
        _messageController
            .add(List.unmodifiable(_messages));
        _broadcastExcept(fromEndpoint, packet);
        break;

      case 'typing_start':
        if (_chatPeers.containsKey(senderId)) {
          _chatPeers[senderId]!.isTyping = true;
          _typingController.add(senderId);
          _chatPeerController
              .add(Map.unmodifiable(_chatPeers));
        }
        break;

      case 'typing_stop':
        if (_chatPeers.containsKey(senderId)) {
          _chatPeers[senderId]!.isTyping = false;
          final stillTyping = _chatPeers.values
              .where((p) => p.isTyping)
              .map((p) => p.id)
              .firstOrNull;
          _typingController.add(stillTyping);
          _chatPeerController
              .add(Map.unmodifiable(_chatPeers));
        }
        break;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // HAZARD REPORTING
  // ════════════════════════════════════════════════════════════════

  Future<void> reportHazard(HazardType type) async {
    await _updateLocation();
    final alert = HazardAlert(
      id: '${_myId}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      latitude: currentLat,
      longitude: currentLng,
      reportedBy: _myId,
      timestamp: DateTime.now(),
    );
    alert.updateDistance(currentLat, currentLng);
    _alertMap[alert.id] = alert;
    _alertController.add(alerts);
    _broadcast({
      'type': 'hazard',
      'id': _myId,
      'hop': 0,
      'data': alert.toJson(),
    });
  }

  // ════════════════════════════════════════════════════════════════
  // CHAT
  // ════════════════════════════════════════════════════════════════

  void sendMessage(String text) {
    if (!_isRunning || text.trim().isEmpty) return;
    final msg = ChatMessage(
      id: '${_myId}_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myId,
      content: text.trim(),
      timestamp: DateTime.now(),
      type: ChatMessageType.text,
      isMe: true,
    );
    _seenMessageIds.add(msg.id);
    _messages.add(msg);
    _messageController
        .add(List.unmodifiable(_messages));
    _broadcast(
        {'type': 'msg', 'id': _myId, 'data': msg.toJson()});
    _broadcast(
        {'type': 'typing_stop', 'id': _myId});
  }

  void notifyTyping() {
    if (!_isRunning) return;
    _broadcast({'type': 'typing_start', 'id': _myId});
    _typingResetTimer?.cancel();
    _typingResetTimer = Timer(
        const Duration(seconds: 3), notifyStopTyping);
  }

  void notifyStopTyping() {
    _typingResetTimer?.cancel();
    if (!_isRunning) return;
    _broadcast(
        {'type': 'typing_stop', 'id': _myId});
  }

  void broadcastHazardAsChat({
    required String hazardLabel,
    required String hazardEmoji,
    required String distanceLabel,
  }) {
    final msg = ChatMessage(
      id: '${_myId}_hazard_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myId,
      content:
      '$hazardEmoji $hazardLabel reported by you ($distanceLabel)',
      timestamp: DateTime.now(),
      type: ChatMessageType.hazardAlert,
      isMe: true,
      meta: {
        'emoji': hazardEmoji,
        'label': hazardLabel,
        'distance': distanceLabel,
      },
    );
    _seenMessageIds.add(msg.id);
    _messages.add(msg);
    _messageController
        .add(List.unmodifiable(_messages));
    _broadcast(
        {'type': 'msg', 'id': _myId, 'data': msg.toJson()});
  }

  // ════════════════════════════════════════════════════════════════
  // ALERT MANAGEMENT
  // ════════════════════════════════════════════════════════════════

  void removeAlert(String alertId) {
    _alertMap.remove(alertId);
    _alertController.add(alerts);
  }

  // ════════════════════════════════════════════════════════════════
  // SEND HELPERS
  // ════════════════════════════════════════════════════════════════

  void _sendToEndpoint(
      String endpointId, Map<String, dynamic> data) {
    if (!_connectedEndpoints.contains(endpointId)) {
      return;
    }
    try {
      final bytes =
      utf8.encode(jsonEncode(data));
      _nearby.sendBytesPayload(
          endpointId, Uint8List.fromList(bytes));
    } catch (e) {
      debugPrint('Send error to $endpointId: $e');
    }
  }

  void _broadcast(Map<String, dynamic> data) {
    for (final endpointId
    in _connectedEndpoints.toList()) {
      _sendToEndpoint(endpointId, data);
    }
  }

  void _broadcastExcept(
      String excludeEndpoint,
      Map<String, dynamic> data) {
    for (final endpointId
    in _connectedEndpoints.toList()) {
      if (endpointId != excludeEndpoint) {
        _sendToEndpoint(endpointId, data);
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  // LOCATION
  // ════════════════════════════════════════════════════════════════

  Future<void> _updateLocation() async {
    try {
      var permission =
      await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission =
        await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        return;
      }
      final position =
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      currentLat = position.latitude;
      currentLng = position.longitude;
      for (final alert in _alertMap.values) {
        alert.updateDistance(currentLat, currentLng);
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void _cleanupStaleAlerts() {
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: 10));
    _alertMap.removeWhere(
            (_, alert) => alert.timestamp.isBefore(cutoff));
    _alertController.add(alerts);
  }

  // ════════════════════════════════════════════════════════════════
  // HELPERS  (kept for hazard_screen.dart compatibility)
  // ════════════════════════════════════════════════════════════════

  /// No-op stub — nearby_connections needs no pairing.
  /// Kept so hazard_screen.dart compiles without changes.
  Future<List<dynamic>> getBondedDevices() async => [];

  /// No-op stub — connection is automatic via discovery.
  Future<bool> connectToDevice(dynamic device) async =>
      true;

  void _addSystemMessage(String text) {
    _messages.add(ChatMessage.system(text));
    _messageController
        .add(List.unmodifiable(_messages));
  }

  void _emitStatus(NetworkStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(peers);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // STOP
  // ════════════════════════════════════════════════════════════════

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;

    _broadcast({'type': 'bye', 'id': _myId});

    _cleanupTimer?.cancel();
    _locationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _typingResetTimer?.cancel();

    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _nearby.stopAllEndpoints();

    _alertMap.clear();
    _chatPeers.clear();
    _connectedEndpoints.clear();
    _endpointToId.clear();
    _seenMessageIds.clear();

    _emitStatus(NetworkStatus.idle);
  }

  void dispose() {
    stop();
    _alertController.close();
    _statusController.close();
    _peersController.close();
    _messageController.close();
    _typingController.close();
    _chatPeerController.close();
  }
}