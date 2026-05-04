import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/models.dart';
import '../theme.dart';
import '../services/api_service.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMine;
  final String apiBase;
  final void Function(String emoji) onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int? myUserId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.apiBase,
    required this.onReact,
    this.onEdit,
    this.onDelete,
    this.myUserId,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showReactions = false;

  String _fullUrl(String? path) => ApiService().resolveMediaUrl(path);

  String _formatTime(DateTime t) {
    final h = t.hour;
    final min = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hh = (h % 12 == 0 ? 12 : h % 12);
    return '$hh:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final msg = widget.message;
    final bubbleColor = widget.isMine
        ? (isDark ? kDarkBubbleMine : kLightBubbleMine)
        : (isDark ? kDarkBubbleOther : kLightBubbleOther);
    final textColor = isDark ? kDarkText : kLightText;
    final metaColor = isDark ? kDarkSubText : kLightSubText;

    return GestureDetector(
      onLongPress: () => setState(() => _showReactions = !_showReactions),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment:
              widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Reaction picker
            if (_showReactions)
              _ReactionPicker(
                onPick: (emoji) {
                  widget.onReact(emoji);
                  setState(() => _showReactions = false);
                },
                onClose: () => setState(() => _showReactions = false),
                isMine: widget.isMine,
              ),

            Row(
              mainAxisAlignment: widget.isMine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  decoration: BoxDecoration(
                    color: msg.optimistic
                        ? bubbleColor.withAlpha(153)
                        : bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(widget.isMine ? 12 : 2),
                      bottomRight: Radius.circular(widget.isMine ? 2 : 12),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 4,
                          offset: const Offset(0, 1))
                    ],
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Content
                        _MessageContent(
                          msg: msg,
                          textColor: textColor,
                          fullUrl: _fullUrl,
                        ),

                        const SizedBox(height: 2),

                        // Meta row
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (msg.isEdited)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text('Edited',
                                    style: TextStyle(
                                        color: metaColor, 
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic)),
                              ),
                            Text(
                              _formatTime(msg.createdAt),
                              style: TextStyle(color: metaColor, fontSize: 10),
                            ),
                            if (widget.isMine) ...[
                              const SizedBox(width: 4),
                              _StatusIcon(status: msg.status),
                            ],
                            // Edit button
                            if (widget.onEdit != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: widget.onEdit,
                                child: Icon(Icons.edit_outlined,
                                    size: 12, color: metaColor),
                              ),
                            ],
                            // Delete button
                            if (widget.onDelete != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: widget.onDelete,
                                child: Icon(Icons.delete_outline,
                                    size: 14, color: Colors.redAccent.withOpacity(0.8)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Reactions list
            if (msg.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _ReactionsRow(
                  reactions: msg.reactions,
                  myUserId: widget.myUserId,
                  onTap: (emoji) => widget.onReact(emoji),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageContent extends StatefulWidget {
  final Message msg;
  final Color textColor;
  final String Function(String?) fullUrl;

  const _MessageContent(
      {required this.msg, required this.textColor, required this.fullUrl});

  @override
  State<_MessageContent> createState() => _MessageContentState();
}

class _MessageContentState extends State<_MessageContent> {
  int _retryKey = 0;

  void _retry() {
    if (mounted) {
      setState(() {
        _retryKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final fullUrl = widget.fullUrl;
    final textColor = widget.textColor;

    if (msg.messageType == 'image') {
      final isLocal =
          msg.localFile != null && File(msg.localFile!).existsSync();

      if (isLocal) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(msg.localFile!),
            width: 220,
            fit: BoxFit.cover,
          ),
        );
      }

      final url = fullUrl(msg.file);
      if (url.isEmpty) {
        return const Icon(Icons.broken_image, color: Colors.grey);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () {
            if (_retryKey > 0)
              _retry(); // Only retry on tap if it failed before
            _openImage(context, url);
          },
          child: CachedNetworkImage(
            key: ValueKey('$url-$_retryKey'),
            imageUrl: url,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 220,
              height: 150,
              color: Colors.grey.withAlpha(25),
              child: const Center(
                child: Icon(Icons.image_outlined, color: Colors.grey, size: 32),
              ),
            ),
            errorWidget: (context, url, error) {
              // Auto-retry up to 8 times with increasing delays
              // First retry happens very fast (1s) to catch images that finish processing quickly
              if (_retryKey < 8) {
                final delay = _retryKey == 0 ? 1 : (2 + _retryKey);
                Future.delayed(Duration(seconds: delay), _retry);
              }
              return GestureDetector(
                onTap: _retry,
                child: Container(
                  width: 220,
                  height: 150,
                  color: Colors.grey.withAlpha(25),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.grey),
                      SizedBox(height: 4),
                      Text('Loading failed. Tap to retry',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else if (msg.messageType == 'voice') {
      final isLocal =
          msg.localFile != null && File(msg.localFile!).existsSync();
      final url = isLocal ? msg.localFile! : fullUrl(msg.file);
      return _AudioPlayer(url: url, isLocal: isLocal);
    } else {
      return Text(
        msg.text ?? '',
        style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
      );
    }
  }

  void _openImage(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
            child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url))),
      ),
    ));
  }
}

class _AudioPlayer extends StatefulWidget {
  final String url;
  final bool isLocal;
  const _AudioPlayer({required this.url, this.isLocal = false});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) => setState(() => _duration = d));
    _player.onPositionChanged.listen((p) => setState(() => _position = p));
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_playing) {
                await _player.pause();
              } else {
                if (widget.isLocal) {
                  await _player.play(DeviceFileSource(widget.url));
                } else {
                  await _player.play(UrlSource(widget.url));
                }
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: kBrandGreen, shape: BoxShape.circle),
              child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.withAlpha(76),
                  color: kBrandGreen,
                  minHeight: 3,
                ),
                const SizedBox(height: 3),
                Text(_fmt(_playing ? _position : _duration),
                    style: const TextStyle(fontSize: 10, color: kDarkSubText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'sending') {
      return const Icon(Icons.access_time, size: 12, color: kDarkSubText);
    } else if (status == 'seen') {
      return const Text('✓✓', style: TextStyle(fontSize: 11, color: kSeenBlue));
    } else {
      return const Text('✓',
          style: TextStyle(fontSize: 11, color: kDarkSubText));
    }
  }
}

class _ReactionPicker extends StatelessWidget {
  final void Function(String) onPick;
  final VoidCallback onClose;
  final bool isMine;

  const _ReactionPicker(
      {required this.onPick, required this.onClose, required this.isMine});

  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? kDarkCard : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(38), blurRadius: 8)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _emojis
              .map((e) => GestureDetector(
                    onTap: () => onPick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _ReactionsRow extends StatelessWidget {
  final List<Reaction> reactions;
  final int? myUserId;
  final void Function(String) onTap;

  const _ReactionsRow(
      {required this.reactions, this.myUserId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = <String, int>{};
    for (final r in reactions) {
      groups[r.emoji] = (groups[r.emoji] ?? 0) + 1;
    }
    return Wrap(
      spacing: 4,
      children: groups.entries.map((e) {
        return GestureDetector(
          onTap: () => onTap(e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? kDarkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrandGreen.withAlpha(102), width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(e.key, style: const TextStyle(fontSize: 14)),
              if (e.value > 1) ...[
                const SizedBox(width: 3),
                Text('${e.value}',
                    style: const TextStyle(fontSize: 11, color: kBrandGreen)),
              ],
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// EditInput widget removed
