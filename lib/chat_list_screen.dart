import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for Clipboard
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

  // Cache stores text, sender, timestamp (for sorting), AND timeLabel (for display)
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

    // Load contacts, then start listening to ensure less flicker
    _loadContacts().then((_) {
      if (mounted) setState(() {});
    });
    
    _listenToFirebase();
  }

  // ===================== FIREBASE LISTENER =====================
  void _listenToFirebase() {
    FirebaseFirestore.instance
        .collection("chats")
        .where("users", arrayContains: widget.myId)
        .snapshots()
        .listen((snapshot) {
      
      // 1. Notification Logic
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          
          final data = change.doc.data();
          if (data == null) continue;

          final lastSender = data['lastSender'];
          final lastMsg = data['lastMessage'] ?? "New Message";
          
          dynamic rawUpdated = data['lastUpdated'];
          final lastUpdatedDate = (rawUpdated is Timestamp) ? rawUpdated.toDate() : null;

          final isRecent = lastUpdatedDate != null &&
              DateTime.now().difference(lastUpdatedDate).inSeconds < 10;

          if (isRecent &&
              lastSender != widget.myId &&
              currentOpenChatId != change.doc.id) {
            NotificationHelper.showNotification(
              title: "New Page from $lastSender",
              body: lastMsg,
              channelId: change.doc.id,
            );
          }
        }
      }

      // 2. Rebuild Cache & Unknown List
      final Set<String> activeChatIds = {};
      unknownChats.clear(); // Clear to rebuild

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final chatId = doc.id;
        activeChatIds.add(chatId);

        // --- A. CACHE UPDATE ---
        if (data.containsKey('lastMessage')) {
          dynamic rawUpdated = data['lastUpdated'];
          Timestamp? sortTimestamp = (rawUpdated is Timestamp) ? rawUpdated : null;

          String displayTime = "";
          if (sortTimestamp != null) {
            final date = sortTimestamp.toDate();
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final msgDate = DateTime(date.year, date.month, date.day);

            if (msgDate == today) {
              displayTime = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
            } else if (msgDate == today.subtract(const Duration(days: 1))) {
              displayTime = "YESTERDAY";
            } else {
              displayTime = "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}";
            }
          }

          _lastMessageCache[chatId] = {
            "text": data['lastMessage'],
            "sender": data['lastSender'],
            "timestamp": sortTimestamp,
            "timeLabel": displayTime,
          };
        }

        // --- B. UNKNOWN CHAT DISCOVERY ---
        final parts = chatId.split("_");
        if (parts.length == 2 && parts.contains(widget.myId)) {
          final otherId = parts.first == widget.myId ? parts.last : parts.first;
          
          // Note: This check relies on 'chats' being loaded. 
          // If 'chats' loads LATER, this might add a duplicate temporarily.
          // 🔥 The build() method fixes this visual duplicate.
          final isSavedContact = chats.any((c) => c["id"] == otherId);
          if (!isSavedContact) {
            unknownChats.add({
              "name": "UNKNOWN",
              "id": otherId,
            });
          }
        }
      }

      // 3. Cleanup Cache
      _lastMessageCache.removeWhere((key, value) => !activeChatIds.contains(key));

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
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.myId)
          .collection("saved_contacts")
          .get();

      setState(() {
        chats.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          chats.add({
            "name": data["name"].toString(),
            "id": data["id"].toString(),
          });
        }
      });
    } catch (e) {
      debugPrint("Error loading contacts: $e");
    }
  }

  Future<void> _addContactToFirestore(String id, String name) async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.myId)
        .collection("saved_contacts")
        .doc(id)
        .set({
      "name": name,
      "id": id,
      "savedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteContactFromFirestore(String id) async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.myId)
        .collection("saved_contacts")
        .doc(id)
        .delete();
  }

  //==================== SAVE CONTACT =====================
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
                  // Immediately clean up unknown list
                  unknownChats.removeWhere((c) => c["id"] == pagerId);
                });

                await _addContactToFirestore(pagerId, name.toUpperCase());
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

    void copyToClipboard() {
      Clipboard.setData(ClipboardData(text: chat["id"]!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Pager ID Copied to Clipboard",
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.greenAccent,
          duration: Duration(milliseconds: 800),
        ),
      );
    }

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
            GestureDetector(
              onLongPress: copyToClipboard,
              onSecondaryTap: copyToClipboard,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.green.withOpacity(0.1),
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

              await _addContactToFirestore(chat["id"]!, newName.toUpperCase());
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

  // ===================== DELETE CONFIRMATION DIALOG =====================
  void _confirmDeleteChat(String chatId) {
    bool deleteForEveryone = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
          ),
          title: const Text(
            "DELETE CHAT",
            style: TextStyle(color: Colors.redAccent),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Are you sure you want to delete this chat?",
                style: TextStyle(color: Colors.green, fontSize: 16),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  setDialogState(() {
                    deleteForEveryone = !deleteForEveryone;
                  });
                },
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: deleteForEveryone
                            ? Colors.redAccent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: deleteForEveryone
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Delete for everyone",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL", style: TextStyle(color: Colors.green)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                await _performDelete(chatId, deleteForEveryone);
              },
              child: const Text(
                "DELETE",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== PERFORM DELETE LOGIC =====================
  Future<void> _performDelete(String chatId, bool forEveryone) async {
    final chatRef = FirebaseFirestore.instance.collection("chats").doc(chatId);

    // 🔥 Wipe Local Storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("chat_$chatId"); 
    await prefs.remove("chat_${chatId}_last"); 
    await prefs.remove("chat_${chatId}_unread"); 

    if (forEveryone) {
      final messages = await chatRef.collection("messages").get();
      final batch = FirebaseFirestore.instance.batch();
      
      for (var doc in messages.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(chatRef);
      
      await batch.commit();
    } else {
      await chatRef.update({
        "users": FieldValue.arrayRemove([widget.myId])
      });
    }

    setState(() {
      _lastMessageCache.remove(chatId);
    });
  }

  // ===================== CHAT OPTIONS =====================
  void _showChatOptions({required Map<String, String> chat}) {
    final isSaved = chats.any((c) => c["id"] == chat["id"]);
    final fullChatId = _buildChatId(widget.myId, chat["id"]!);

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
            _optionTile("Delete Chat", Icons.delete, () {
              Navigator.pop(context);
              _confirmDeleteChat(fullChatId);
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
          ),
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
                      style: const TextStyle(color: Colors.redAccent)),
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

                await _addContactToFirestore(pagerId, name.toUpperCase());
                if (mounted) Navigator.pop(context);
              },
              child: const Text("SAVE",
                  style: TextStyle(color: Colors.greenAccent)),
            )
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

  // ===================== HELPERS =====================
  String _buildChatId(String a, String b) =>
      a.compareTo(b) < 0 ? "${a}_$b" : "${b}_$a";

  Future<bool> _isUnread(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool("chat_${chatId}_unread") ?? false;
  }

// ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    
    // 1. 🔥 FIX DUPLICATES: Create a Set of saved IDs
    final savedIds = chats.map((c) => c['id']).toSet();

    // 2. 🔥 FIX DUPLICATES: Only allow Unknowns that are NOT saved
    final uniqueUnknowns = unknownChats
        .where((c) => !savedIds.contains(c['id']))
        .toList();

    // 3. Combine Lists
    final allChats = [...uniqueUnknowns, ...chats];

    // 4. Filter by Search
    final filteredChats = allChats.where((c) =>
        c["name"]!.toUpperCase().contains(_search.toUpperCase()) ||
        c["id"]!.toUpperCase().contains(_search.toUpperCase())).toList();

    // 5. Sort by Timestamp
    filteredChats.sort((a, b) {
      final chatIdA = _buildChatId(widget.myId, a["id"]!);
      final chatIdB = _buildChatId(widget.myId, b["id"]!);

      final tA = _lastMessageCache[chatIdA]?['timestamp'] as Timestamp?;
      final tB = _lastMessageCache[chatIdB]?['timestamp'] as Timestamp?;

      if (tA == null && tB == null) return 0;
      if (tA == null) return 1; 
      if (tB == null) return -1; 

      return tB.compareTo(tA);
    });

    void copyMyId() {
      Clipboard.setData(ClipboardData(text: widget.myId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "My Pager ID Copied!",
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.greenAccent,
          duration: Duration(milliseconds: 800),
        ),
      );
    }

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
            GestureDetector(
              onLongPress: copyMyId,
              onSecondaryTap: copyMyId,
              child: Container(
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
                  itemCount: filteredChats.length,
                  itemBuilder: (_, index) {
                    final chat = filteredChats[index];
                    final chatId = _buildChatId(widget.myId, chat["id"]!);

                    final isEven = index % 2 == 0;
                    final bgColor = isEven
                        ? const Color(0xFF0E1A0E)
                        : const Color(0xFF0A140A);

                    final lastMsgData = _lastMessageCache[chatId];
                    final lastMsg = lastMsgData != null
                        ? (lastMsgData['text'] ?? "NO MESSAGES")
                        : "NO MESSAGES";
                    
                    final timeLabel = lastMsgData != null 
                        ? (lastMsgData['timeLabel'] ?? "") 
                        : "";

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
                                  color:
                                      Colors.greenAccent.withOpacity(0.08),
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
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              chat["name"]!,
                                              style: TextStyle(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.9),
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace',
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (timeLabel.isNotEmpty)
                                            Text(
                                              timeLabel,
                                              style: TextStyle(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.5),
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold
                                              ),
                                            ),
                                        ],
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
                                if (unread) ...[
                                  const SizedBox(width: 8),
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
                                ]
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