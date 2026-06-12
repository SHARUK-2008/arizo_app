// lib/screens/chat_screen_bt.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/bluetooth_hazard_service.dart';

const _kPeerColors = [
  Color(0xFF6480FF),
  Color(0xFF00C896),
  Color(0xFFFFAA00),
  Color(0xFFFF6B8A),
  Color(0xFF9A7FFF),
];

class ChatScreen extends StatefulWidget {
  final BluetoothHazardService service;
  const ChatScreen({super.key, required this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _inputCtrl  = TextEditingController();
  final ScrollController      _scrollCtrl = ScrollController();
  final FocusNode             _focusNode  = FocusNode();

  List<ChatMessage>     _messages     = [];
  Map<String, ChatPeer> _peers        = {};
  bool                  _isConnected  = false;
  String?               _typingPeerId;

  StreamSubscription<List<ChatMessage>>?     _msgSub;
  StreamSubscription<Map<String, ChatPeer>>? _peerSub;
  StreamSubscription<NetworkStatus>?         _statusSub;
  StreamSubscription<String?>?               _typingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _isConnected = widget.service.isRunning;
    _messages    = widget.service.messages.toList();
    _peers       = Map.from(widget.service.chatPeers);

    _msgSub = widget.service.messageStream.listen((messages) {
      if (!mounted) return;
      setState(() => _messages = messages.toList());
      _scrollToBottom();
    });

    _peerSub = widget.service.chatPeerStream.listen((peers) {
      if (!mounted) return;
      setState(() => _peers = Map.from(peers));
    });

    _statusSub = widget.service.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _isConnected = status.isActive);
    });

    _typingSub = widget.service.typingStream.listen((peerId) {
      if (!mounted) return;
      setState(() => _typingPeerId = peerId);
      if (peerId != null) _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _peerSub?.cancel();
    _statusSub?.cancel();
    _typingSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.service.sendMessage(text);
    _inputCtrl.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  Color _peerColor(String peerId) {
    final idx = peerId.codeUnits.fold(0, (a, b) => a + b) % _kPeerColors.length;
    return _kPeerColors[idx];
  }

  String _shortId(String id) =>
      id.length > 7 ? id.substring(id.length - 7) : id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (_peers.isNotEmpty) _buildPeersBar(),
            Expanded(child: _buildMessageList()),
            if (_typingPeerId != null) _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final count = _peers.length;
    final color = _isConnected ? AppTheme.accentGreen : AppTheme.accentAmber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark1,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppTheme.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bluetooth Mesh Chat',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                Text(
                  _isConnected
                      ? '$count driver${count == 1 ? '' : 's'} nearby'
                      : 'Bluetooth offline',
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark1,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Text(widget.service.myId,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ),
          if (_isConnected) ...[
            const SizedBox(width: 8),
            Icon(Icons.bluetooth_connected, color: color, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildPeersBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _peers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final peer  = _peers.values.elementAt(i);
          final color = _peerColor(peer.id);
          final initials = peer.id.length >= 2
              ? peer.id.substring(peer.id.length - 2)
              : peer.id;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 9,
                backgroundColor: color.withOpacity(0.2),
                child: Text(initials,
                    style: TextStyle(
                        color: color,
                        fontSize: 8,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 5),
              Text(peer.id, style: TextStyle(color: color, fontSize: 10)),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline,
                color: AppTheme.textTertiary, size: 44),
            const SizedBox(height: 12),
            Text(
              _isConnected
                  ? 'No messages yet.\nSay hello to nearby drivers!'
                  : 'Connect to a device first\nthen come back to chat.',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg  = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showSender = msg.type != ChatMessageType.system &&
            (prev == null || prev.senderId != msg.senderId);

        if (msg.type == ChatMessageType.system) {
          return _SystemBubble(message: msg);
        }
        if (msg.type == ChatMessageType.hazardAlert) {
          return _HazardBubble(
              message: msg, peerColor: _peerColor(msg.senderId));
        }
        return _MessageBubble(
          message: msg,
          peerColor: _peerColor(msg.senderId),
          showSenderLabel: showSender,
          shortId: _shortId(msg.senderId),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    final peer = _typingPeerId;
    if (peer == null) return const SizedBox.shrink();
    final color = _peerColor(peer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: color.withOpacity(0.15),
          child: Text(
            peer.length >= 2 ? peer.substring(peer.length - 2) : peer,
            style: TextStyle(
                color: color, fontSize: 7, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderDark, width: 0.5),
          ),
          child: Row(
            children: List.generate(3, (i) {
              return Container(
                width: 5, height: 5,
                margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.textTertiary.withOpacity(0.5),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 6),
        Text('$peer is typing…',
            style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderDark)),
        color: AppTheme.bgDark,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 130),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark1,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                maxLines: 5,
                minLines: 1,
                enabled: true,
                textInputAction: TextInputAction.send,
                onChanged: (_) {
                  if (_isConnected) widget.service.notifyTyping();
                  setState(() {});
                },
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _isConnected
                      ? 'Message nearby drivers…'
                      : 'Connect to a device to chat…',
                  hintStyle: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _inputCtrl.text.trim().isNotEmpty ? _sendMessage : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _inputCtrl.text.trim().isNotEmpty
                    ? const Color(0xFF5E5CE6)
                    : AppTheme.surfaceDark1,
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: _inputCtrl.text.trim().isNotEmpty
                    ? Colors.white
                    : AppTheme.textTertiary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color peerColor;
  final bool showSenderLabel;
  final String shortId;
  const _MessageBubble({
    required this.message,
    required this.peerColor,
    required this.showSenderLabel,
    required this.shortId,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Padding(
      padding: EdgeInsets.only(top: showSenderLabel ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: peerColor.withOpacity(0.15),
              child: Text(
                shortId.length >= 2
                    ? shortId.substring(shortId.length - 2)
                    : shortId,
                style: TextStyle(
                    color: peerColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showSenderLabel && !isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 2),
                    child: Text(message.senderId,
                        style: TextStyle(
                            color: peerColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w500)),
                  ),
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.65),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF3730A3)
                        : AppTheme.surfaceDark1,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: isMe
                        ? null
                        : Border.all(
                        color: AppTheme.borderDark, width: 0.5),
                  ),
                  child: Text(message.content,
                      style: TextStyle(
                          color:
                          isMe ? Colors.white : AppTheme.textPrimary,
                          fontSize: 14,
                          height: 1.4)),
                ),
                Padding(
                  padding:
                  const EdgeInsets.only(top: 3, left: 2, right: 2),
                  child: Text(message.timeLabel,
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 10)),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 32),
        ],
      ),
    );
  }
}

// ── Hazard Bubble ──────────────────────────────────────────────────────────────
class _HazardBubble extends StatelessWidget {
  final ChatMessage message;
  final Color peerColor;
  const _HazardBubble(
      {required this.message, required this.peerColor});

  @override
  Widget build(BuildContext context) {
    final emoji    = message.meta?['emoji']    as String? ?? '⚠️';
    final label    = message.meta?['label']    as String? ?? 'Hazard';
    final distance = message.meta?['distance'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.accentRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
              child: Text(emoji,
                  style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label reported',
                    style: const TextStyle(
                        color: AppTheme.accentRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    '${message.isMe ? 'You' : message.senderId} · $distance · ${message.timeLabel}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ]),
        ),
        const Icon(Icons.warning_amber_rounded,
            color: AppTheme.accentRed, size: 16),
      ]),
    );
  }
}

// ── System Bubble ──────────────────────────────────────────────────────────────
class _SystemBubble extends StatelessWidget {
  final ChatMessage message;
  const _SystemBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark1,
            borderRadius: BorderRadius.circular(20),
            border:
            Border.all(color: AppTheme.borderDark, width: 0.5),
          ),
          child: Text(message.content,
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 11)),
        ),
      ),
    );
  }
}