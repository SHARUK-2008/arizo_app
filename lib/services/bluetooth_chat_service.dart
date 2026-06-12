import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── Chat Message Model ───────────────────────────────────────────────────────
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

  factory ChatMessage.fromJson(Map<String, dynamic> j, String myId) =>
      ChatMessage(
        id: j['id'] as String,
        senderId: j['sid'] as String,
        content: j['msg'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
        type: ChatMessageType.values[(j['type'] as int?) ?? 0],
        isMe: (j['sid'] as String) == myId,
        meta: j['meta'] as Map<String, dynamic>?,
      );

  factory ChatMessage.system(String text) => ChatMessage(
    id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
    senderId: 'system',
    content: text,
    timestamp: DateTime.now(),
    type: ChatMessageType.system,
  );
}

// ─── Peer Model ───────────────────────────────────────────────────────────────
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

  bool get isOnline => DateTime.now().difference(lastSeen).inSeconds < 45;
}

// ─── Bluetooth Chat Service ───────────────────────────────────────────────────
class BluetoothChatService {
  static const String _serviceId = 'com.guardiandrive.mesh';

  // ── Streams ────────────────────────────────────────────────────────────────
  final _messageCtrl = StreamController<List<ChatMessage>>.broadcast();
  final _peerCtrl    = StreamController<Map<String, ChatPeer>>.broadcast();
  final _statusCtrl  = StreamController<bool>.broadcast();
  final _typingCtrl  = StreamController<String?>.broadcast();

  Stream<List<ChatMessage>>     get messageStream => _messageCtrl.stream;
  Stream<Map<String, ChatPeer>> get peerStream    => _peerCtrl.stream;
  Stream<bool>                  get statusStream  => _statusCtrl.stream;
  Stream<String?>               get typingStream  => _typingCtrl.stream;

  // ── State ──────────────────────────────────────────────────────────────────
  final List<ChatMessage>     _messages   = [];
  final Map<String, ChatPeer> _peers      = {};
  final Set<String>           _endpoints  = {};
  final Map<String, String>   _endpointToId = {};
  final Set<String>           _seenIds    = {};

  List<ChatMessage>         get messages => List.unmodifiable(_messages);
  Map<String, ChatPeer>     get peers    => Map.unmodifiable(_peers);

  bool _isRunning = false;
  bool get isConnected => _isRunning;

  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  Timer? _typingResetTimer;

  final Nearby _nearby = Nearby();

  final String _myId;
  String get myId => _myId;

  BluetoothChatService({String? deviceId})
      : _myId = deviceId ??
      'GD_${Random().nextInt(9999).toString().padLeft(4, '0')}';

  // ── Permissions ────────────────────────────────────────────────────────────
  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
    ].request();
    return statuses.values.every((s) => s == PermissionStatus.granted);
  }

  // ── Start ──────────────────────────────────────────────────────────────────
  Future<bool> start() async {
    if (_isRunning) return true;

    final granted = await _requestPermissions();
    if (!granted) {
      _statusCtrl.add(false);
      return false;
    }

    try {
      await _nearby.startAdvertising(
        _myId,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );

      await _nearby.startDiscovery(
        _myId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );

      _isRunning = true;
      _statusCtrl.add(true);
      _addSystemMessage('You joined the mesh chat — ID: $_myId');

      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 12),
            (_) => _broadcast({'type': 'heartbeat', 'id': _myId}),
      );
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 20),
            (_) => _cleanupPeers(),
      );

      return true;
    } catch (e) {
      debugPrint('BluetoothChatService start error: $e');
      _statusCtrl.add(false);
      return false;
    }
  }

  // ── Nearby callbacks ───────────────────────────────────────────────────────
  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _endpoints.add(endpointId);
      _sendToEndpoint(endpointId, {'type': 'join', 'id': _myId});
    } else {
      _endpoints.remove(endpointId);
      _endpointToId.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    final peerId = _endpointToId.remove(endpointId);
    _endpoints.remove(endpointId);
    if (peerId != null) {
      _peers.remove(peerId);
      _addSystemMessage('$peerId disconnected');
      _peerCtrl.add(Map.unmodifiable(_peers));
    }
  }

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) {
    if (_endpoints.contains(endpointId)) return;
    _nearby.requestConnection(
      _myId,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onEndpointLost(String? endpointId) {}

  // ── Payload ────────────────────────────────────────────────────────────────
  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null) return;
    try {
      final packet = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      _handlePacket(packet, endpointId);
    } catch (e) {
      debugPrint('Chat payload parse error: $e');
    }
  }

  // ── Packet handler ─────────────────────────────────────────────────────────
  void _handlePacket(Map<String, dynamic> packet, String fromEndpoint) {
    final pType    = packet['type']  as String?;
    final senderId = packet['id']    as String? ?? fromEndpoint;

    if (senderId == _myId) return;

    _endpointToId[fromEndpoint] = senderId;

    if (_peers.containsKey(senderId)) {
      _peers[senderId]!.lastSeen = DateTime.now();
    } else if (pType != 'leave') {
      _peers[senderId] = ChatPeer(
        id: senderId,
        address: fromEndpoint,
        lastSeen: DateTime.now(),
      );
    }

    switch (pType) {
      case 'join':
        _addSystemMessage('$senderId joined the chat');
        _peerCtrl.add(Map.unmodifiable(_peers));
        _sendToEndpoint(fromEndpoint, {'type': 'heartbeat', 'id': _myId});
        break;

      case 'heartbeat':
        _peerCtrl.add(Map.unmodifiable(_peers));
        break;

      case 'leave':
        _peers.remove(senderId);
        _addSystemMessage('$senderId left the chat');
        _peerCtrl.add(Map.unmodifiable(_peers));
        break;

      case 'msg':
        final data = packet['data'] as Map<String, dynamic>?;
        if (data == null) return;
        final msgId = data['id'] as String?;
        if (msgId != null && _seenIds.contains(msgId)) return;
        if (msgId != null) _seenIds.add(msgId);

        final msg = ChatMessage.fromJson(data, _myId);
        _messages.add(msg);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _messageCtrl.add(List.unmodifiable(_messages));

        _broadcastExcept(fromEndpoint, packet);
        break;

      case 'typing_start':
        if (_peers.containsKey(senderId)) {
          _peers[senderId]!.isTyping = true;
          _typingCtrl.add(senderId);
          _peerCtrl.add(Map.unmodifiable(_peers));
        }
        break;

      case 'typing_stop':
        if (_peers.containsKey(senderId)) {
          _peers[senderId]!.isTyping = false;
          final still = _peers.values
              .where((p) => p.isTyping)
              .map((p) => p.id)
              .firstOrNull;
          _typingCtrl.add(still);
          _peerCtrl.add(Map.unmodifiable(_peers));
        }
        break;
    }
  }

  // ── Send text message ──────────────────────────────────────────────────────
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

    _seenIds.add(msg.id);
    _messages.add(msg);
    _messageCtrl.add(List.unmodifiable(_messages));
    _broadcast({'type': 'msg', 'id': _myId, 'data': msg.toJson()});
    _broadcast({'type': 'typing_stop', 'id': _myId});
  }

  // ── Hazard → chat bridge ───────────────────────────────────────────────────
  void broadcastHazardAsChat({
    required String hazardLabel,
    required String hazardEmoji,
    required String distanceLabel,
  }) {
    final msg = ChatMessage(
      id: '${_myId}_hazard_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myId,
      content: '$hazardEmoji $hazardLabel reported by you ($distanceLabel)',
      timestamp: DateTime.now(),
      type: ChatMessageType.hazardAlert,
      isMe: true,
      meta: {
        'emoji': hazardEmoji,
        'label': hazardLabel,
        'distance': distanceLabel,
      },
    );

    _seenIds.add(msg.id);
    _messages.add(msg);
    _messageCtrl.add(List.unmodifiable(_messages));
    _broadcast({'type': 'msg', 'id': _myId, 'data': msg.toJson()});
  }

  // ── Typing indicators ──────────────────────────────────────────────────────
  void notifyTyping() {
    if (!_isRunning) return;
    _broadcast({'type': 'typing_start', 'id': _myId});
    _typingResetTimer?.cancel();
    _typingResetTimer =
        Timer(const Duration(seconds: 3), notifyStopTyping);
  }

  void notifyStopTyping() {
    _typingResetTimer?.cancel();
    if (!_isRunning) return;
    _broadcast({'type': 'typing_stop', 'id': _myId});
  }

  // ── Send helpers ───────────────────────────────────────────────────────────
  void _sendToEndpoint(String endpointId, Map<String, dynamic> data) {
    if (!_endpoints.contains(endpointId)) return;
    try {
      final bytes = utf8.encode(jsonEncode(data));
      _nearby.sendBytesPayload(endpointId, Uint8List.fromList(bytes));
    } catch (e) {
      debugPrint('Chat send error to $endpointId: $e');
    }
  }

  void _broadcast(Map<String, dynamic> data) {
    for (final id in _endpoints.toList()) {
      _sendToEndpoint(id, data);
    }
  }

  void _broadcastExcept(String exclude, Map<String, dynamic> data) {
    for (final id in _endpoints.toList()) {
      if (id != exclude) _sendToEndpoint(id, data);
    }
  }

  // ── Cleanup stale peers ────────────────────────────────────────────────────
  void _cleanupPeers() {
    final stale = _peers.entries
        .where((e) => !e.value.isOnline)
        .map((e) => e.key)
        .toList();
    for (final id in stale) {
      _peers.remove(id);
      _addSystemMessage('$id went offline');
    }
    if (stale.isNotEmpty) _peerCtrl.add(Map.unmodifiable(_peers));
  }

  void _addSystemMessage(String text) {
    _messages.add(ChatMessage.system(text));
    _messageCtrl.add(List.unmodifiable(_messages));
  }

  // ── Stop ───────────────────────────────────────────────────────────────────
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;

    _broadcast({'type': 'leave', 'id': _myId});

    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _typingResetTimer?.cancel();

    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _nearby.stopAllEndpoints();

    _peers.clear();
    _endpoints.clear();
    _endpointToId.clear();
    _seenIds.clear();
    _statusCtrl.add(false);
  }

  void dispose() {
    stop();
    _messageCtrl.close();
    _peerCtrl.close();
    _statusCtrl.close();
    _typingCtrl.close();
  }
}