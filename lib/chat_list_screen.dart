import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart'; // Import to access currentOpenChatId
import 'auth_service.dart';
import 'notification_helper.dart'; // Import your notification helper

class ChatListScreen extends StatefulWidget {
  final String myId;

  const ChatListScreen({
    super.key,
    required this.myId,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, String>> chats = []; // saved contacts
  final List<Map<String, String>> unknownChats = []; // unsaved chats

  final Map<String, dynamic> _lastMessageCache = {};

  String _search = "";
  final TextEditingController _searchController = TextEditingController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // ===================== INIT =====================
  @override
  void initState() {
    super.initState();
    
    // Init local notifications
    NotificationHelper.init();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(
      begin: 0.3,
      end: 0.9,
    ).animate(_pulseController);

    _loadContacts();
    _discoverChatsFromChatIds();

    // 🔥 MAIN LISTENER (Updates list & Triggers Notifications)
    FirebaseFirestore.instance
        .collection("chats")
        .where("users", arrayContains: widget.myId)
        .snapshots()
        .listen((snapshot) {
      
      for (final change in snapshot.docChanges) {
        final data = change.doc.data()!;
        final chatId = change.doc.id;
        
        // 1. Update Cache
        if (data.containsKey('lastMessage')) {
           _lastMessageCache[chatId] = {
             "text": data['lastMessage'],
             "sender": data['lastSender'],
             "time": data['lastTime'],
           };
        }

        // 2. 🔥 TRIGGER NOTIFICATION
        // Only if modified/added, sender is NOT me, and NOT currently open
        if (change.type == DocumentChangeType.modified || change.type == DocumentChangeType.added) {
          final lastSender = data['lastSender'];
          final lastMsg = data['lastMessage'] ?? "New Message";
          final lastUpdated = (data['lastUpdated'] as Timestamp?)?.toDate();

          // Check for "recent" (avoid spam on initial load)
          final isRecent = lastUpdated != null && 
              DateTime.now().difference(lastUpdated).inSeconds < 10;

          if (isRecent && lastSender != widget.myId && currentOpenChatId != chatId) {
             NotificationHelper.showNotification(
               title: "New Page from $lastSender",
               body: lastMsg,
               channelId: chatId,
             );
          }
        }
      }
      if (mounted) setState(() {});
    });
  }

  // ===================== DISPOSE =====================
  @override
  void dispose() {
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ===================== CONTACT STORAGE =====================
  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList("contacts_${widget.myId}") ?? [];

    setState(() {
      chats.clear();
      for (final e in raw) {
        final parts = e.split("|");
        if (parts.length == 2) {
          chats.add({"name": parts[0], "id": parts[1]});
        }
      }
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = chats.map((c) => "${c['name']}|${c['id']}").toList();
    await prefs.setStringList("contacts_${widget.myId}", raw);
  }

  //==================== save CONTACT =====================
  void _openSaveContactDialog(String pagerId) {
    final nameController = TextEditingController();
    String error = "";

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            "SAVE CONTACT",
            style: TextStyle(color: Colors.greenAccent),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.greenAccent),
                decoration: const InputDecoration(
                  hintText: "CONTACT NAME",
                  hintStyle: TextStyle(color: Colors.green),
                ),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();

                if (name.isEmpty) {
                  setLocalState(() => error = "Name required");
                  return;
                }

                if (pagerId == widget.myId) {
                  setLocalState(() => error = "You cannot add yourself");
                  return;
                }

                final snap = await FirebaseFirestore.instance
                    .collection("users")
                    .where("pagerId", isEqualTo: pagerId)
                    .limit(1)
                    .get();

                if (snap.docs.isEmpty) {
                  setLocalState(() => error = "Pager ID does not exist");
                  return;
                }

                if (chats.any((c) => c["id"] == pagerId)) {
                  setLocalState(() => error = "Already in contacts");
                  return;
                }

                setState(() {
                  chats.add({
                    "name": name.toUpperCase(),
                    "id": pagerId,
                  });
                  unknownChats.removeWhere((c) => c["id"] == pagerId);
                });

                await _saveContacts();
                Navigator.pop(context);
              },
              child: const Text(
                "SAVE",
                style: TextStyle(color: Colors.greenAccent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CANCEL",
                style: TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //========================== EDIT CONTACT ==========================
  void _openEditContactDialog(Map<String, String> chat) {
    final nameController = TextEditingController(text: chat["name"]);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Text(
          "EDIT CONTACT",
          style: TextStyle(color: Colors.greenAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.greenAccent),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "CONTACT NAME",
                  hintStyle: TextStyle(color: Colors.green),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "PAGER ID: ${chat["id"]}",
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) return;

              setState(() {
                final index = chats.indexWhere((c) => c["id"] == chat["id"]);
                chats[index]["name"] = newName.toUpperCase();
              });

              await _saveContacts();
              Navigator.pop(context);
            },
            child: const Text(
              "SAVE",
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== DISCOVER CHATS =====================
  Future<void> _discoverChatsFromChatIds() async {
    final snap = await FirebaseFirestore.instance.collection("chats").get();

    for (final doc in snap.docs) {
      final chatId = doc.id;
      final parts = chatId.split("_");
      if (parts.length != 2) continue;
      if (!parts.contains(widget.myId)) continue;

      final otherId = parts.first == widget.myId ? parts.last : parts.first;
      final existsInSaved = chats.any((c) => c["id"] == otherId);
      final existsInUnknown = unknownChats.any((c) => c["id"] == otherId);

      if (!existsInSaved && !existsInUnknown) {
        unknownChats.add({
          "name": "UNKNOWN",
          "id": otherId,
        });
      }
    }
    if (mounted) setState(() {});
  }

  // ===================== ADD CONTACT =====================
  void addContactDialog() {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    String error = "";

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            "ADD CONTACT",
            style: TextStyle(color: Colors.greenAccent),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.greenAccent),
                decoration: const InputDecoration(
                  hintText: "CONTACT NAME",
                  hintStyle: TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: idController,
                style: const TextStyle(color: Colors.greenAccent),
                decoration: const InputDecoration(
                  hintText: "PAGER ID",
                  hintStyle: TextStyle(color: Colors.green),
                ),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error,
                      style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final pagerId = idController.text.trim();

                if (name.isEmpty || pagerId.isEmpty) {
                  setLocalState(() => error = "All fields required");
                  return;
                }

                if (pagerId == widget.myId) {
                  setLocalState(() => error = "You cannot add yourself");
                  return;
                }

                if (chats.any((c) => c["id"] == pagerId)) {
                  setLocalState(() => error = "Already added");
                  return;
                }

                final snap = await FirebaseFirestore.instance
                    .collection("users")
                    .where("pagerId", isEqualTo: pagerId)
                    .limit(1)
                    .get();

                if (snap.docs.isEmpty) {
                  setLocalState(() => error = "Invalid Pager ID");
                  return;
                }

                setState(() {
                  chats.add({
                    "name": name.toUpperCase(),
                    "id": pagerId,
                  });
                  unknownChats.removeWhere((c) => c["id"] == pagerId);
                });

                await _saveContacts();
                Navigator.pop(context);
              },
              child: const Text("SAVE",
                  style: TextStyle(color: Colors.greenAccent)),
            )
          ],
        ),
      ),
    );
  }

  // ===================== HELPERS =====================
  String _buildChatId(String a, String b) =>
      a.compareTo(b) < 0 ? "${a}_$b" : "${b}_$a";

  Future<bool> _isUnread(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool("chat_${chatId}_unread") ?? false;
  }

  // ===================== CHAT OPTIONS =====================
  void _showChatOptions({required Map<String, String> chat}) {
    final isSaved = chats.any((c) => c["id"] == chat["id"]);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.greenAccent, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat["name"]!,
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (!isSaved)
              _optionTile("Save to Contacts", Icons.person_add, () {
                Navigator.pop(context);
                _openSaveContactDialog(chat["id"]!);
              }),
            if (isSaved)
              _optionTile("Edit Contact", Icons.edit, () {
                Navigator.pop(context);
                _openEditContactDialog(chat);
              }),
            _optionTile("Delete", Icons.delete, () async {
              chats.removeWhere((c) => c["id"] == chat["id"]);
              unknownChats.removeWhere((c) => c["id"] == chat["id"]);
              await _saveContacts();
              setState(() {});
              Navigator.pop(context);
            }, color: Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(String text, IconData icon, VoidCallback onTap,
      {Color color = Colors.greenAccent}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: color, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ===================== LOGOUT =====================
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          "LOGOUT",
          style: TextStyle(color: Colors.greenAccent),
        ),
        content: const Text(
          "Are you sure you want to logout?",
          style: TextStyle(color: Colors.green),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.green)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("LOGOUT",
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

// ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final allChats = [...unknownChats, ...chats]
        .where((c) =>
            c["name"]!.toUpperCase().contains(_search.toUpperCase()) ||
            c["id"]!.toUpperCase().contains(_search.toUpperCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050505),

      // ===================== FAB =====================
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.5),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.green.shade900,
          onPressed: addContactDialog,
          child: const Icon(Icons.person_add, color: Colors.greenAccent),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ===================== HEADER =====================
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F0A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.9),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          "PAGER CHAT",
                          style: TextStyle(
                            color: Colors.greenAccent,
                            letterSpacing: 3,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "PAGER ID: ${widget.myId}",
                          style: TextStyle(
                            color: Colors.greenAccent.withOpacity(0.6),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.greenAccent),
                    onPressed: _logout,
                  )
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ===================== SEARCH BAR =====================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.25),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v.trim()),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF0C120C),
                    hintText: "SEARCH CHAT / PAGER ID",
                    hintStyle: TextStyle(
                      color: Colors.greenAccent.withOpacity(0.5),
                    ),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.greenAccent),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.greenAccent),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = "");
                            },
                          )
                        : null,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.greenAccent.withOpacity(0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Colors.greenAccent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            // ===================== CHAT LIST =====================
            Expanded(
              child: Container(
                color: const Color(0xFF070B07),
                child: ListView.builder(
                  itemCount: allChats.length,
                  itemBuilder: (_, index) {
                    final chat = allChats[index];
                    final chatId = _buildChatId(widget.myId, chat["id"]!);

                    final isEven = index % 2 == 0;
                    final bgColor = isEven
                        ? const Color(0xFF0E1A0E)
                        : const Color(0xFF0A140A);

                    final lastMsgData = _lastMessageCache[chatId];
                    final lastMsg = lastMsgData != null 
                        ? (lastMsgData['text'] ?? "NO MESSAGES")
                        : "NO MESSAGES";

                    return FutureBuilder(
                      future: _isUnread(chatId),
                      builder: (context, snap) {
                        final unread = snap.hasData ? snap.data! : false;

                        return GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  chatName: chat["name"]!,
                                  chatId: chatId,
                                  myId: widget.myId,
                                ),
                              ),
                            );
                            await _loadContacts();
                            setState(() {});
                          },
                          onLongPress: () => _showChatOptions(chat: chat),
                          onSecondaryTap: () => _showChatOptions(chat: chat),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.greenAccent.withOpacity(0.30),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        chat["name"]!,
                                        style: TextStyle(
                                          color: Colors.greenAccent
                                              .withOpacity(0.9),
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        lastMsg,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.greenAccent
                                              .withOpacity(0.55),
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (unread)
                                  AnimatedBuilder(
                                    animation: _pulseAnim,
                                    builder: (_, __) => Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.greenAccent,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.greenAccent
                                                .withOpacity(
                                                    _pulseAnim.value * 0.6),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}