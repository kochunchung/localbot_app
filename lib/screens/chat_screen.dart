import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/socket_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/sticker_picker.dart';
import 'settings_screen.dart';
import 'location_picker_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  final SocketService _socket = SocketService();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? _messageSub;
  StreamSubscription? _stateSub;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  bool _isRecording = false;
  Timer? _recordTimer;
  int _recordSeconds = 0;
  String? _dismissedQuickReplyMsgId;

  /// QuickReply items are strictly bound to the latest incoming Bot message.
  /// If the latest message is from the user (e.g. user sent text, voice,
  /// image, location, sticker) or does not contain quick reply, it returns null.
  List<dynamic>? get _activeQuickReplyItems {
    if (_messages.isEmpty) return null;
    final lastMsg = _messages.last;
    if (lastMsg.isUser) return null;
    if (lastMsg.id == _dismissedQuickReplyMsgId) return null;
    if (lastMsg.quickReplyItems != null && lastMsg.quickReplyItems!.isNotEmpty) {
      return lastMsg.quickReplyItems;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _auth.init();
    await _loadLocalMessages();

    // Register with server in background
    _auth.registerWithServer();

    // Setup Socket.IO listeners
    _connectionState = _socket.connectionState;
    _stateSub = _socket.onStateChanged.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
      }
    });

    _messageSub = _socket.onMessageReceived.listen((message) {
      _addIncomingMessage(message);
    });

    _socket.connect();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _stateSub?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalMessages() async {
    final localMsgs = await _db.getMessages(limit: 100);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(localMsgs);
        _dismissedQuickReplyMsgId = null;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _addIncomingMessage(ChatMessage message) async {
    await _db.saveMessage(message);
    if (mounted) {
      setState(() {
        _messages.add(message);
        _dismissedQuickReplyMsgId = null;
      });
      _scrollToBottom();
    }
  }

  // ==========================================================================
  // Sending Actions
  // ==========================================================================

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();

    final optimisticMsg = ChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      userId: _auth.userId,
      isUser: true,
      messageType: 'text',
      content: {'text': text},
      timestamp: DateTime.now(),
      status: 'sending',
    );

    setState(() {
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    final resultMsg = await _api.sendTextMessage(text);

    if (resultMsg != null) {
      await _db.saveMessage(resultMsg);
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
        if (idx != -1) {
          _messages[idx] = resultMsg;
        }
      });
    } else {
      setState(() {
        optimisticMsg.status = 'failed';
      });
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;

      final imageFile = File(file.path);

      final optimisticMsg = ChatMessage(
        id: 'local_img_${DateTime.now().millisecondsSinceEpoch}',
        userId: _auth.userId,
        isUser: true,
        messageType: 'image',
        content: {'originalContentUrl': 'file://${file.path}'},
        timestamp: DateTime.now(),
        status: 'sending',
      );

      setState(() {
        _messages.add(optimisticMsg);
      });
      _scrollToBottom();

      final sentMsg = await _api.uploadAndSendMedia(imageFile, 'image');
      if (sentMsg != null) {
        await _db.saveMessage(sentMsg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
          if (idx != -1) {
            _messages[idx] = sentMsg;
          }
        });
      } else {
        setState(() {
          optimisticMsg.status = 'failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('選取圖片失敗: $e')),
      );
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000);
        await _audioRecorder.start(config, path: path);

        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordSeconds++;
            });
          }
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請授予麥克風權限以進行錄音')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('啟動錄音失敗: $e')),
      );
    }
  }

  Future<void> _stopAndSendRecording({bool cancel = false}) async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();

    setState(() {
      _isRecording = false;
    });

    if (cancel || path == null) return;

    final durationMs = _recordSeconds * 1000;
    final audioFile = File(path);

    final optimisticMsg = ChatMessage(
      id: 'local_audio_${DateTime.now().millisecondsSinceEpoch}',
      userId: _auth.userId,
      isUser: true,
      messageType: 'audio',
      content: {'originalContentUrl': 'file://$path', 'duration': durationMs},
      timestamp: DateTime.now(),
      status: 'sending',
    );

    setState(() {
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    final sentMsg = await _api.uploadAndSendMedia(audioFile, 'audio', duration: durationMs);
    if (sentMsg != null) {
      await _db.saveMessage(sentMsg);
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
        if (idx != -1) {
          _messages[idx] = sentMsg;
        }
      });
    } else {
      setState(() {
        optimisticMsg.status = 'failed';
      });
    }
  }

  Future<void> _sendLocation({
    required String title,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final optimisticMsg = ChatMessage(
      id: 'local_loc_${DateTime.now().millisecondsSinceEpoch}',
      userId: _auth.userId,
      isUser: true,
      messageType: 'location',
      content: {
        'title': title,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      },
      timestamp: DateTime.now(),
      status: 'sending',
    );

    setState(() {
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    final sentMsg = await _api.sendLocationMessage(
      title: title,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );

    if (sentMsg != null) {
      await _db.saveMessage(sentMsg);
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
        if (idx != -1) {
          _messages[idx] = sentMsg;
        }
      });
    } else {
      setState(() {
        optimisticMsg.status = 'failed';
      });
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(),
      ),
    );

    if (result != null) {
      final title = result['title'] as String? ?? '選取位置';
      final address = result['address'] as String? ?? '';
      final lat = (result['latitude'] as num?)?.toDouble() ?? 25.0339;
      final lng = (result['longitude'] as num?)?.toDouble() ?? 121.5644;

      _sendLocation(
        title: title,
        address: address,
        latitude: lat,
        longitude: lng,
      );
    }
  }

  void _openStickerPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StickerPickerWidget(
        onStickerSelected: (packageId, stickerId) async {
          final optimisticMsg = ChatMessage(
            id: 'local_stk_${DateTime.now().millisecondsSinceEpoch}',
            userId: _auth.userId,
            isUser: true,
            messageType: 'sticker',
            content: {'packageId': packageId, 'stickerId': stickerId},
            timestamp: DateTime.now(),
            status: 'sending',
          );

          setState(() {
            _messages.add(optimisticMsg);
          });
          _scrollToBottom();

          final sentMsg = await _api.sendSticker(packageId, stickerId);
          if (sentMsg != null) {
            await _db.saveMessage(sentMsg);
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
              if (idx != -1) {
                _messages[idx] = sentMsg;
              }
            });
          } else {
            setState(() {
              optimisticMsg.status = 'failed';
            });
          }
        },
      ),
    );
  }

  void _handleAction(Map<String, dynamic> action) {
    setState(() {
      if (_messages.isNotEmpty) {
        _dismissedQuickReplyMsgId = _messages.last.id;
      }
    });

    final type = action['type'];
    if (type == 'postback') {
      final data = action['data'] ?? '';
      final displayText = action['displayText'] ?? action['label'];

      if (displayText != null && displayText.toString().isNotEmpty) {
        // Optimistically show user choice in chat
        final echoMsg = ChatMessage(
          id: 'pb_echo_${DateTime.now().millisecondsSinceEpoch}',
          userId: _auth.userId,
          isUser: true,
          messageType: 'text',
          content: {'text': displayText},
          timestamp: DateTime.now(),
        );
        setState(() {
          _messages.add(echoMsg);
        });
        _scrollToBottom();
      }

      _api.sendPostback(data, displayText: displayText);
    } else if (type == 'message') {
      final text = action['text'] ?? action['label'] ?? '';
      if (text.isNotEmpty) {
        _textController.text = text;
        _sendText();
      }
    } else if (type == 'camera') {
      _pickAndSendImage(ImageSource.camera);
    } else if (type == 'cameraRoll') {
      _pickAndSendImage(ImageSource.gallery);
    } else if (type == 'location') {
      _openLocationPicker();
    }
  }

  // ==========================================================================
  // UI Builder
  // ==========================================================================

  Widget _buildQuickReplyBar() {
    final items = _activeQuickReplyItems;
    if (items == null || items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final action = item is Map ? (item['action'] ?? item) : {};
                final label = action['label'] ?? action['text'] ?? action['type'] ?? '選項';
                final imageUrl = item is Map ? item['imageUrl'] : null;

                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    side: const BorderSide(color: Color(0xFF00B900), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF00B900),
                  ),
                  onPressed: () {
                    if (action is Map<String, dynamic>) {
                      _handleAction(action);
                    } else if (action is Map) {
                      _handleAction(Map<String, dynamic>.from(action));
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (imageUrl != null && imageUrl.toString().isNotEmpty) ...[
                        Image.network(
                          imageUrl,
                          width: 16,
                          height: 16,
                          errorBuilder: (_, __, ___) => const Icon(Icons.touch_app, size: 14),
                        ),
                        const SizedBox(width: 6),
                      ] else if (action['type'] == 'camera') ...[
                        const Icon(Icons.camera_alt, size: 14),
                        const SizedBox(width: 4),
                      ] else if (action['type'] == 'cameraRoll') ...[
                        const Icon(Icons.photo_library, size: 14),
                        const SizedBox(width: 4),
                      ] else if (action['type'] == 'location') ...[
                        const Icon(Icons.location_on, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.black45),
            tooltip: '收合快速回覆',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              setState(() {
                if (_messages.isNotEmpty) {
                  _dismissedQuickReplyMsgId = _messages.last.id;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    Color color;
    String text;
    switch (_connectionState) {
      case SocketConnectionState.connected:
        color = const Color(0xFF00B900);
        text = '已連線';
        break;
      case SocketConnectionState.connecting:
        color = Colors.orange;
        text = '連線中...';
        break;
      case SocketConnectionState.disconnected:
        color = Colors.red;
        text = '已離線';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8C9DAE), // LINE Classic background grey-blue
      appBar: AppBar(
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LocalBot',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            _buildConnectionIndicator(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '同步紀錄',
            onPressed: () async {
              final history = await _api.fetchHistory();
              if (history.isNotEmpty) {
                for (final h in history) {
                  await _db.saveMessage(h);
                }
                await _loadLocalMessages();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (result == true) {
                _loadLocalMessages();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat history list
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          '尚無訊息，向 Bot 打個招呼吧！',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return ChatBubble(
                          message: msg,
                          onAction: _handleAction,
                        );
                      },
                    ),
            ),

            // QuickReply bar if active
            _buildQuickReplyBar(),

            // Recording banner if active
            if (_isRecording)
              Container(
                color: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '錄音中: ${_recordSeconds}s',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _stopAndSendRecording(cancel: true),
                      child: const Text('取消', style: TextStyle(color: Colors.white70)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade700,
                      ),
                      onPressed: () => _stopAndSendRecording(cancel: false),
                      child: const Text('完成傳送'),
                    ),
                  ],
                ),
              ),

            // Bottom input bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.black54),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Wrap(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.photo_library, color: Color(0xFF00B900)),
                                title: const Text('相簿圖片'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _pickAndSendImage(ImageSource.gallery);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.camera_alt, color: Color(0xFF00B900)),
                                title: const Text('拍照'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _pickAndSendImage(ImageSource.camera);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.location_on, color: Color(0xFF00B900)),
                                title: const Text('分享位置'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _openLocationPicker();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sentiment_satisfied_alt_outlined, color: Colors.black54),
                    onPressed: _openStickerPicker,
                  ),
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic_none,
                      color: _isRecording ? Colors.red : Colors.black54,
                    ),
                    onPressed: () {
                      if (_isRecording) {
                        _stopAndSendRecording(cancel: false);
                      } else {
                        _startRecording();
                      }
                    },
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: const InputDecoration(
                          hintText: '輸入訊息...',
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF00B900)),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
