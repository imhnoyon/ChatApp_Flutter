import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme.dart';

class CallScreen extends StatefulWidget {
  final CallSession session;
  final bool isIncoming;
  final User? otherUser;

  const CallScreen({
    super.key,
    required this.session,
    this.isIncoming = false,
    this.otherUser,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _api = ApiService();
  final _socket = SocketService();
  late CallSession _session;
  bool _ongoing = false;
  Timer? _timer;
  Duration _duration = Duration.zero;
  bool _muted = false;
  bool _speaker = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session.status == 'ongoing') {
      _ongoing = true;
      _startTimer();
    }

    // Connect to call WebSocket
    _socket.connectCall(
      _session.id,
      callback: _handleSocketPayload,
      onConnected: () {
        debugPrint('Connected to call WebSocket');
      },
    );
  }

  void _handleSocketPayload(Map<String, dynamic> p) {
    if (!mounted) return;
    final type =
        (p['type'] as String? ?? p['action'] as String? ?? '').toLowerCase();

    if (type == 'call_event' ||
        type == 'call_update' ||
        p.containsKey('call_status')) {
      final status = (p['status'] ?? p['call_status']) as String?;
      if (status == 'ongoing') {
        if (!_ongoing) {
          setState(() {
            _ongoing = true;
          });
          _startTimer();
        }
      } else if (status == 'ended' ||
          status == 'rejected' ||
          status == 'missed') {
        _timer?.cancel();
        if (mounted) Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _answer() async {
    try {
      await _api.answerCall(_session.conversationId, _session.id);
      if (mounted) {
        setState(() {
          _ongoing = true;
        });
        _startTimer();
      }
    } catch (e) {
      debugPrint('Answer error: $e');
    }
  }

  Future<void> _reject() async {
    try {
      await _api.rejectCall(_session.conversationId, _session.id);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _end() async {
    try {
      await _api.endCall(_session.conversationId, _session.id);
    } finally {
      _timer?.cancel();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _socket.disconnectCall(manual: true);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final sessionOtherUser =
        _session.caller.id == auth.me?.id ? _session.receiver : _session.caller;
    final otherUser = widget.otherUser ?? sessionOtherUser;
    final isVideo = _session.callType == 'video';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          if (isVideo)
            Container(
              color: Colors.grey[900],
              child: const Center(
                child:
                    Icon(Icons.videocam_off, color: Colors.white54, size: 64),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kBrandGreen.withOpacity(0.8), Colors.black],
                ),
              ),
            ),

          // User Info
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 80),
                _api.resolveMediaUrl(otherUser.avatar).isNotEmpty
                    ? CircleAvatar(
                        radius: 60,
                        backgroundImage: CachedNetworkImageProvider(
                            _api.resolveMediaUrl(otherUser.avatar)),
                      )
                    : CircleAvatar(
                        radius: 60,
                        backgroundColor: kBrandGreen,
                        child: Text(otherUser.initials,
                            style: const TextStyle(
                                fontSize: 48,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                const SizedBox(height: 24),
                Text(
                  otherUser.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _ongoing
                      ? _formatDuration(_duration)
                      : (widget.isIncoming
                          ? 'Incoming ${_session.callType} call...'
                          : 'Calling...'),
                  style: TextStyle(
                      color: _ongoing ? kBrandGreen : Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Controls
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (widget.isIncoming && !_ongoing) ...[
                  // Reject
                  _CircleButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onTap: _reject,
                  ),
                  // Answer
                  _CircleButton(
                    icon: Icons.call,
                    color: Colors.green,
                    onTap: _answer,
                  ),
                ] else ...[
                  // Mute
                  _CircleButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color: _muted ? Colors.white30 : Colors.white12,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  // End
                  _CircleButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 72,
                    onTap: _end,
                  ),
                  // Speaker
                  _CircleButton(
                    icon: _speaker ? Icons.volume_up : Icons.volume_down,
                    color: _speaker ? Colors.white30 : Colors.white12,
                    onTap: () => setState(() => _speaker = !_speaker),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.color,
    this.size = 64,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}
