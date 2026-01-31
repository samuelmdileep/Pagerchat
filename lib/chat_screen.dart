import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🔥 GLOBAL TRACKER: Tells the app which chat is currently open
String? currentOpenChatId;

class ChatScreen extends StatefulWidget {
  final String chatName;
  final String chatId;
  final String myId;

  const ChatScreen({
    super.key,
    required this.chatName,
    required this.chatId,
    required this.myId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final Set<String> _pendingDeletes = {};
  final Map<String, Timer> _deleteTimers = {};
  final Map<String, VoidCallback> _pendingCommits = {};

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription? _msgSubscription;

  List<String> _messages = [];

  String get _storageKey => "chat_${widget.chatId}";

  CollectionReference get _fireMessages =>
      FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .collection("messages");

  String get otherUserId {
    final parts = widget.chatId.split("_");
    return parts.first == widget.myId ? parts.last : parts.first;
  }

  // ===================== INIT =====================
  @override
  void initState() {
    super.initState();
    currentOpenChatId = widget.chatId;
    _loadMessages();
    _listenToFirebase();
    _updateChatPreview(lastText: "", unread: false);
  }

  @override
  void dispose() {
    if (currentOpenChatId == widget.chatId) {
      currentOpenChatId = null;
    }

    _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();

    _deleteTimers.forEach((id, timer) {
      timer.cancel();
      _pendingCommits[id]?.call();
    });

    _msgSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===================== DATE FORMATTER =====================
  String _formatDateLabel(String dateKey) {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final parts = dateKey.split('-');
      final date = DateTime(
        int.parse(parts[0]), 
        int.parse(parts[1]), 
        int.parse(parts[2])
      );
      
      final check = DateTime(date.year, date.month, date.day);

      if (check == today) return "TODAY";
      if (check == today.subtract(const Duration(days: 1))) return "YESTERDAY";
      
      return "${parts[2]}/${parts[1]}/${parts[0]}"; // DD/MM/YYYY
    } catch (e) {
      return dateKey;
    }
  }

  // ===================== STORAGE =====================
  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    _messages = prefs.getStringList(_storageKey) ?? [];
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _messages);
  }

  //================= UI HELPERS =====================
  Widget _optionTile(String text, IconData icon, VoidCallback onTap, {Color color = Colors.redAccent}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: TextStyle(color: color, fontFamily: 'monospace')),
      onTap: onTap,
    );
  }

  void _showMessageOptions({
    required BuildContext context,
    required String messageId,
    required bool isYou,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _optionTile("Delete for me", Icons.delete_outline, () {
            Navigator.pop(context);
            _scheduleDelete(messageId, forEveryone: false);
          }),
          if (isYou)
            _optionTile("Delete for everyone", Icons.delete, () {
              Navigator.pop(context);
              _scheduleDelete(messageId, forEveryone: true);
            }),
          _optionTile("Cancel", Icons.close, () => Navigator.pop(context), color: Colors.green),
        ],
      ),
    );
  }

  //===================== DELETE LOGIC ===================
  void _scheduleDelete(String messageId, {required bool forEveryone}) {
    setState(() => _pendingDeletes.add(messageId));

    void commitDelete() async {
      final batch = FirebaseFirestore.instance.batch();
      final msgRef = _fireMessages.doc(messageId);
      final chatRef = FirebaseFirestore.instance.collection("chats").doc(widget.chatId);

      if (forEveryone) {
        batch.set(msgRef, {"deletedForEveryone": true}, SetOptions(merge: true));
      } else {
        batch.set(msgRef, {"deletedFor": {widget.myId: true}}, SetOptions(merge: true));
      }

      batch.set(chatRef, {
        "lastMessage": "MESSAGE DELETED", 
        "lastUpdated": FieldValue.serverTimestamp()
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) setState(() => _pendingDeletes.remove(messageId));
      _deleteTimers.remove(messageId);
      _pendingCommits.remove(messageId);
    }

    _pendingCommits[messageId] = commitDelete;

    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF060906),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          duration: const Duration(seconds: 5),
          content: Text(
            forEveryone ? "Deleted for everyone" : "Message deleted",
            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
          ),
          action: SnackBarAction(
            label: "UNDO",
            textColor: Colors.greenAccent,
            onPressed: () {
              _deleteTimers[messageId]?.cancel();
              _deleteTimers.remove(messageId);
              _pendingCommits.remove(messageId);
              setState(() => _pendingDeletes.remove(messageId));
            },
          ),
        ),
      );
    }

    _deleteTimers[messageId] = Timer(const Duration(seconds: 5), () {
      commitDelete();
    });
  }

  Future<void> _updateChatPreview({required String lastText, required bool unread}) async {
    final prefs = await SharedPreferences.getInstance();
    if (lastText.isNotEmpty) {
      await prefs.setString("chat_${widget.chatId}_last", lastText);
    }
    await prefs.setBool("chat_${widget.chatId}_unread", unread);
  }

  // ===================== FIREBASE LISTENER =====================
  void _listenToFirebase() {
    _msgSubscription = _fireMessages
        .orderBy("timestamp")
        .snapshots()
        .listen((snapshot) async {
      bool updated = false;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final docId = doc.id;

        final bool deletedForEveryone = data["deletedForEveryone"] == true;
        final bool deletedForMe = data["deletedFor"]?[widget.myId] == true;

        final cleanText = (data["text"] ?? "").toString().replaceAll("|", " ");

        // 🔥 1. EXTRACT DATE KEY FOR HEADERS
        String dateKey = "TODAY";
        if (data["timestamp"] != null && data["timestamp"] is Timestamp) {
          final dt = (data["timestamp"] as Timestamp).toDate();
          dateKey = "${dt.year}-${dt.month}-${dt.day}";
        }

        // 🔥 2. STORE DATE KEY (Index 7)
        final msg =
            "$docId|"
            "$cleanText|"
            "${data["sender"]}|"
            "${data["time"]}|"
            "${data["status"]}|"
            "${deletedForEveryone ? 1 : 0}|"
            "${deletedForMe ? 1 : 0}|"
            "$dateKey";

        final index = _messages.indexWhere((m) => m.startsWith("$docId|"));

        if (index == -1) {
          _messages.add(msg);
          updated = true;

          final fromOther = data["sender"] != widget.myId;
          if (!deletedForEveryone && !deletedForMe) {
            await _updateChatPreview(
              lastText: cleanText,
              unread: fromOther,
            );
          }
        } else {
          if (_messages[index] != msg) {
             _messages[index] = msg;
             updated = true;
          }
        }
      }

      if (updated && mounted) {
        if (_messages.length > 200) {
          _messages = _messages.sublist(_messages.length - 200);
        }
        await _saveMessages();
        if (mounted) setState(() {});
        _scrollToBottom();
      }
    });
  }

  // ===================== SEND MESSAGE =====================
  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final chatRef = FirebaseFirestore.instance.collection("chats").doc(widget.chatId);

    // 🔥 PREPARE TIME DATA
    final now = DateTime.now();
    final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final timeValue = now.hour * 60 + now.minute; 

    // Update main Chat list
    await chatRef.set({
      "users": [widget.myId, otherUserId],
      "lastUpdated": FieldValue.serverTimestamp(),
      "lastMessage": text.toUpperCase(),
      "lastSender": widget.myId,
      "lastTime": timeString,
      "lastTimeValue": timeValue, 
    }, SetOptions(merge: true));

    // Add Message
    await chatRef.collection("messages").add({
      "text": text.toUpperCase(),
      "sender": widget.myId,
      "time": timeString,
      "status": "DELIVERED",
      "timestamp": FieldValue.serverTimestamp(),
    });

    await _updateChatPreview(lastText: text.toUpperCase(), unread: false);
  }

  void _scrollToBottom() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        // 🔥 Fix: Push layout up when keyboard opens
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: Text(
            widget.chatName,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              letterSpacing: 1.2,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.greenAccent.withOpacity(0.2)),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (_, index) {
                  final parts = _messages[index].split('|');
                  if (parts.length < 5) return const SizedBox();

                  final messageId = parts[0];
                  final text = parts[1];
                  final sender = parts[2];
                  final time = parts[3];
                  // final status = parts[4]; 

                  final isDeletedForEveryone = parts.length > 5 && parts[5] == "1";
                  final isDeletedForMe = parts.length > 6 && parts[6] == "1";

                  // 🔥 3. GET DATE KEY (Fallback to TODAY if missing)
                  final dateKey = parts.length > 7 ? parts[7] : "TODAY";

                  // 🔥 4. CALCULATE DATE HEADER
                  bool showDateHeader = false;
                  if (index == 0) {
                    showDateHeader = true;
                  } else {
                    final prevParts = _messages[index - 1].split('|');
                    final prevDateKey = prevParts.length > 7 ? prevParts[7] : "TODAY";
                    if (dateKey != prevDateKey) {
                      showDateHeader = true;
                    }
                  }

                  if (_pendingDeletes.contains(messageId) || isDeletedForEveryone || isDeletedForMe) {
                    return const SizedBox();
                  }

                  final isYou = sender == widget.myId;
                  final baseColor = isYou ? Colors.greenAccent : Colors.green;

                  return Column(
                    children: [
                      // 🔥 5. RENDER DATE HEADER
                      if (showDateHeader)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F140F),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                          ),
                          child: Text(
                            _formatDateLabel(dateKey),
                            style: TextStyle(
                              color: Colors.greenAccent.withOpacity(0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),

                      Align(
                        alignment: isYou ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () {
                            _showMessageOptions(context: context, messageId: messageId, isYou: isYou);
                          },
                          // 🔥 6. RIGHT CLICK SUPPORT (Web)
                          onSecondaryTap: () {
                            _showMessageOptions(context: context, messageId: messageId, isYou: isYou);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: BoxDecoration(
                              color: baseColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: baseColor.withOpacity(0.8), width: 1.1),
                              boxShadow: [
                                BoxShadow(
                                  color: baseColor.withOpacity(0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  text,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      time,
                                      style: TextStyle(
                                        color: Colors.greenAccent.withOpacity(0.55),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isYou) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.done_all,
                                        size: 13,
                                        color: Colors.greenAccent.withOpacity(0.6),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // 🔥 Fix: Safe Area for input
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF060906),
                  border: Border(top: BorderSide(color: Colors.greenAccent.withOpacity(0.25))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => sendMessage(),
                        style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: "TYPE MESSAGE",
                          hintStyle: TextStyle(color: Colors.green),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.greenAccent),
                      onPressed: sendMessage,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}