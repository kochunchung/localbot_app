import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import 'audio_player_widget.dart';
import 'template_widgets.dart';
import 'flex_message_widget.dart';

/// Chat bubble rendering all message types with LINE-style appearance.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final ActionCallback onAction;

  const ChatBubble({
    super.key,
    required this.message,
    required this.onAction,
  });

  bool get _isCarousel {
    if (message.messageType == 'flex') {
      final flexData = (message.content is Map && message.content['contents'] != null)
          ? message.content['contents']
          : message.content;
      return flexData is Map && flexData['type'] == 'carousel';
    }
    if (message.messageType == 'template') {
      final templateData = (message.content is Map && message.content['template'] != null)
          ? message.content['template']
          : message.content;
      return templateData is Map && templateData['type'] == 'carousel';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final isCarousel = _isCarousel;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: isCarousel && !isUser ? 0 : 12,
        top: 6,
        bottom: 6,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF00B900),
              child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
          ],
          if (isUser) _buildMetaInfo(timeStr, isUser),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildContent(context, isUser),
                if (isCarousel && !isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildMetaInfo(timeStr, isUser),
                  ),
              ],
            ),
          ),
          if (!isUser && !isCarousel) _buildMetaInfo(timeStr, isUser),
        ],
      ),
    );
  }

  Widget _buildMetaInfo(String timeStr, bool isUser) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isUser && message.status == 'sending')
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else if (isUser && message.status == 'failed')
            const Icon(Icons.error_outline, size: 14, color: Colors.red)
          else if (isUser)
            const Text(
              '已送達',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          Text(
            timeStr,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    switch (message.messageType) {
      case 'text':
        return _buildTextBubble(isUser);
      case 'image':
        return _buildImageBubble(context, isUser);
      case 'audio':
        return _buildAudioBubble(isUser);
      case 'sticker':
        return _buildStickerBubble(context);
      case 'location':
        return _buildLocationBubble(context, isUser);
      case 'template':
        return _buildTemplateBubble();
      case 'flex':
        return _buildFlexBubble();
      default:
        return _buildTextBubble(isUser);
    }
  }

  Widget _buildTextBubble(bool isUser) {
    final bgColor = isUser ? const Color(0xFF00B900) : Colors.white;
    final textColor = isUser ? Colors.white : Colors.black87;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SelectableText(
        message.text,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context, bool isUser) {
    final url = message.mediaUrl ?? '';
    final isLocal = url.startsWith('/') || url.startsWith('file://');

    Widget imageWidget;
    if (isLocal) {
      final file = File(url.replaceFirst('file://', ''));
      imageWidget = Image.file(file, fit: BoxFit.cover);
    } else if (url.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 200,
          height: 180,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 200,
          height: 180,
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      imageWidget = const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        if (url.isNotEmpty) {
          _showFullScreenImage(context, url, isLocal);
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: imageWidget,
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String url, bool isLocal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: isLocal
                  ? Image.file(File(url.replaceFirst('file://', '')))
                  : CachedNetworkImage(imageUrl: url),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioBubble(bool isUser) {
    final url = message.mediaUrl ?? '';
    final bgColor = isUser ? const Color(0xFF00B900) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: AudioPlayerWidget(
        audioUrl: url,
        durationMs: message.duration,
        isUser: isUser,
      ),
    );
  }

  Widget _buildStickerBubble(BuildContext context) {
    final content = message.content is Map ? message.content as Map : {};
    final pkgId = content['packageId']?.toString() ?? '1';
    final stickerId = content['stickerId']?.toString() ?? '1';
    final baseUrl = AuthService().serverUrl.replaceAll(RegExp(r'/+$'), '');
    final stickerUrl = '$baseUrl/stickers/$pkgId/$stickerId';

    return Container(
      constraints: const BoxConstraints(maxWidth: 140, maxHeight: 140),
      padding: const EdgeInsets.all(4),
      child: CachedNetworkImage(
        imageUrl: stickerUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox(
          width: 80,
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Text('😊', style: TextStyle(fontSize: 64)),
        ),
      ),
    );
  }

  Widget _buildTemplateBubble() {
    final templateData = (message.content is Map && message.content['template'] != null)
        ? Map<String, dynamic>.from(message.content['template'])
        : (message.content is Map ? Map<String, dynamic>.from(message.content) : <String, dynamic>{});

    return TemplateMessageWidget(
      templateData: templateData,
      onAction: onAction,
    );
  }

  Widget _buildFlexBubble() {
    final flexData = (message.content is Map && message.content['contents'] != null)
        ? Map<String, dynamic>.from(message.content['contents'])
        : (message.content is Map ? Map<String, dynamic>.from(message.content) : <String, dynamic>{});

    return FlexMessageWidget(
      flexContents: flexData,
      onAction: onAction,
    );
  }

  Widget _buildLocationBubble(BuildContext context, bool isUser) {
    final title = message.locationTitle;
    final address = message.locationAddress;
    final lat = message.latitude;
    final lng = message.longitude;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Map Banner Visual
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade400, Colors.teal.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  right: -15,
                  bottom: -15,
                  child: Icon(
                    Icons.map_outlined,
                    size: 110,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.redAccent,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),

          // Location Info Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '📍 $lat, $lng',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

