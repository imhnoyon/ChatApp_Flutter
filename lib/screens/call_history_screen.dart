import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme.dart';

class CallHistoryScreen extends StatefulWidget {
  final int? conversationId;
  const CallHistoryScreen({super.key, this.conversationId});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _api = ApiService();
  final _auth = AuthService();
  List<CallSession> _calls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final calls = await _api.getCallHistory(convId: widget.conversationId);
      if (mounted) {
        setState(() {
          _calls = calls;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    if (now.difference(t).inDays == 0) {
      final h = t.hour;
      final min = t.minute.toString().padLeft(2, '0');
      final ampm = h >= 12 ? 'PM' : 'AM';
      final hh = (h % 12 == 0 ? 12 : h % 12);
      return '$hh:$min $ampm';
    }
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kDarkSurface : kLightSurface;
    final textColor = isDark ? kDarkText : kLightText;
    final subColor = isDark ? kDarkSubText : kLightSubText;
    final bgColor = isDark ? kDarkBg : kLightBg;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Call History', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: surfaceColor,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrandGreen))
          : _calls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call_missed_outgoing, size: 64, color: subColor),
                      const SizedBox(height: 16),
                      Text('No call history found', style: TextStyle(color: subColor)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _calls.length,
                  separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: isDark ? kDarkDivider : Colors.grey[200]),
                  itemBuilder: (_, i) {
                    final call = _calls[i];
                    final isOutgoing = call.caller.id == _auth.me?.id;
                    final otherUser = isOutgoing ? call.receiver : call.caller;
                    final avatarUrl = _api.resolveMediaUrl(otherUser.avatar);

                    IconData statusIcon;
                    Color statusColor;

                    if (call.status == 'rejected' || call.status == 'missed') {
                      statusIcon = Icons.call_missed;
                      statusColor = Colors.red;
                    } else if (isOutgoing) {
                      statusIcon = Icons.call_made;
                      statusColor = Colors.green;
                    } else {
                      statusIcon = Icons.call_received;
                      statusColor = Colors.green;
                    }

                    return ListTile(
                      leading: avatarUrl.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage: CachedNetworkImageProvider(avatarUrl),
                            )
                          : CircleAvatar(
                              backgroundColor: kBrandGreen,
                              child: Text(otherUser.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                      title: Text(otherUser.displayName, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                      subtitle: Row(
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            '${call.callType == 'video' ? 'Video' : 'Voice'} • ${call.status}',
                            style: TextStyle(color: subColor, fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        _formatTime(call.startTime ?? call.endTime),
                        style: TextStyle(color: subColor, fontSize: 11),
                      ),
                    );
                  },
                ),
    );
  }
}
