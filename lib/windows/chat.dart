import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:window_size/window_size.dart';

class ChatScreen extends StatefulWidget {
  final String username;

  const ChatScreen({super.key, required this.username});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}
const host = 'wss://chat-social-ng2d.onrender.com/ws';

class ChatScreenState extends State<ChatScreen> {
  late WebSocketChannel channel;
  final List<String> users = [];
  final List<ChatMessage> messages = [];
  final TextEditingController messageController = TextEditingController();
  String selectedChat = 'General';
  final List<String> groups = [];
  // Stocăm grupurile la care utilizatorul este membru
  final Set<String> myGroups = {'General'};
  // Draft-uri pentru fiecare chat: {chat_id: draft_text}
  final Map<String, String> drafts = {};
  // Contor mesaje necitite: {chat_id: count}
  final Map<String, int> unreadCounts = {};
  // Pinned chats (users and groups)
  final Set<String> pinnedChats = {};
  // Typing indicator: {username: bool}
  final Map<String, bool> typingUsers = {};
  // Typing debounce timer
  Timer? typingTimer;
  // Reconnect attempt counter
  int reconnectAttempts = 0;
  // Reconnect timer
  Timer? reconnectTimer;
  // Connection status
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    connectToServer();
    // Schimbă dimensiunea ferestrei la 1200x800
    Future.delayed(const Duration(milliseconds: 100), () {
      setWindowFrame(const Rect.fromLTWH(100, 100, 1200, 800));
      setWindowMinSize(const Size(1200, 800));
      setWindowMaxSize(Size.infinite);
    });
  }

  void connectToServer() {
    try {
      channel = WebSocketChannel.connect(Uri.parse(host));
      channel.stream.listen(
        (message) {
          // Reset reconnect attempts on successful connection
          setState(() {
            isConnected = true;
            reconnectAttempts = 0;
          });
          final data = jsonDecode(message) as Map<String, dynamic>;
          handleServerMessage(data);
        },
        onError: (error) {
          print('Eroare WebSocket: $error');
          handleDisconnect();
        },
        onDone: () {
          print('WebSocket deconectat');
          handleDisconnect();
        },
      );

      // Trimite autentificarea
      channel.sink.add(
        jsonEncode({'type': 'auth', 'username': widget.username}),
      );
    } catch (e) {
      print('Eroare la conectare: $e');
      handleDisconnect();
    }
  }

  void handleServerMessage(Map<String, dynamic> data) {
    if (!mounted) return;

    try {
      setState(() {
        switch (data['type'] as String) {
          case 'user_list':
            users.clear();
            users.addAll((data['users'] as List).cast<String>());
            break;
          case 'typing':
            final sender = data['username'] as String;
            final target = data['target'] as String;
            final isTyping = data['typing'] as bool;
            if (target == widget.username) {
              typingUsers[sender] = isTyping;
            }
            break;
          case 'message':
            final msg = ChatMessage(
              username: data['username'] as String,
              message: data['message'] as String,
              timestamp: DateTime.parse(data['timestamp'] as String),
              isPrivate: false,
              group: 'General',
            );
            messages.add(msg);
            // Increment unread count for General
            if (selectedChat != 'General') {
              unreadCounts['General'] = (unreadCounts['General'] ?? 0) + 1;
            }
            break;
          case 'private_message':
            final sender = data['username'] as String;
            final target = data['target'] as String;
            final msg = ChatMessage(
              username: sender,
              message: data['message'] as String,
              timestamp: DateTime.parse(data['timestamp'] as String),
              isPrivate: true,
              target: target,
            );
            messages.add(msg);
            // Increment unread count for the sender
            if (selectedChat != sender && target == widget.username) {
              unreadCounts[sender] = (unreadCounts[sender] ?? 0) + 1;
            }
            break;
          case 'group_message':
            final group = data['group'] as String;
            final sender = data['username'] as String;
            // Nu adăuga mesajul dacă îl trimitem noi înșine (deja adăugat local)
            if (sender != widget.username) {
              final msg = ChatMessage(
                username: sender,
                message: data['message'] as String,
                timestamp: DateTime.parse(data['timestamp'] as String),
                isPrivate: false,
                group: group,
              );
              messages.add(msg);
              // Increment unread count for group
              if (selectedChat != group) {
                unreadCounts[group] = (unreadCounts[group] ?? 0) + 1;
              }
            }
            break;
          case 'group_created':
            final groupName = data['group_name'] as String;
            if (!groups.contains(groupName)) {
              groups.add(groupName);
              if (data['creator'] == widget.username) {
                myGroups.add(groupName);
              }
            }
            break;
          case 'added_to_group':
            final groupName = data['group_name'] as String;
            if (!myGroups.contains(groupName)) {
              myGroups.add(groupName);
              if (!groups.contains(groupName)) {
                groups.add(groupName);
              }
            }
            break;
        }
      });
    } catch (e) {
      print('Eroare la procesarea mesajului: $e');
    }
  }

  // Salveaza draft-ul curent înainte de a schimba chat-ul
  void saveCurrentDraft() {
    if (messageController.text.isNotEmpty) {
      drafts[selectedChat] = messageController.text;
    }
  }

  // Încarcă draft-ul pentru un chat
  void loadDraft(String chatId) {
    messageController.text = drafts[chatId] ?? '';
  }

  // Schimbă chat-ul și gestionează draft-urile
  void changeChat(String newChat) {
    saveCurrentDraft();
    // Clear unread count when opening chat
    setState(() {
      selectedChat = newChat;
      unreadCounts.remove(newChat);
    });
    loadDraft(newChat);
  }

  // Toggle pin/unpin
  void togglePin(String chatId) {
    setState(() {
      if (pinnedChats.contains(chatId)) {
        pinnedChats.remove(chatId);
      } else {
        pinnedChats.add(chatId);
      }
    });
  }

  // Trimite typing indicator
  void sendTypingIndicator(bool isTyping) {
    try {
      if (users.contains(selectedChat)) {
        channel.sink.add(
          jsonEncode({
            'type': 'typing',
            'username': widget.username,
            'target': selectedChat,
            'typing': isTyping,
          }),
        );
      }
    } catch (e) {
      print('Eroare la trimiterea typing indicator: $e');
    }
  }

  // Gestionează schimbarea textului pentru typing indicator
  void onTextChanged(String text) {
    // Trimite typing indicator
    sendTypingIndicator(true);

    // Resetează timer-ul
    typingTimer?.cancel();
    typingTimer = Timer(const Duration(seconds: 2), () {
      // Dacă nu mai scrie, trimite indicator stop
      sendTypingIndicator(false);
    });
  }

  // Sort users: pinned first, then unread, then alphabetical
  List<String> getSortedUsers() {
    final sorted = List<String>.from(users);
    sorted.sort((a, b) {
      // Pinned first
      final aPinned = pinnedChats.contains(a);
      final bPinned = pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      // Unread next
      final aUnread = unreadCounts.containsKey(a) && unreadCounts[a]! > 0;
      final bUnread = unreadCounts.containsKey(b) && unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;

      // Alphabetical
      return a.compareTo(b);
    });
    return sorted;
  }

  // Sort groups: pinned first, then unread, then alphabetical
  List<String> getSortedGroups() {
    final sorted = myGroups.toList();
    sorted.sort((a, b) {
      // General always first
      if (a == 'General') return -1;
      if (b == 'General') return 1;

      // Pinned
      final aPinned = pinnedChats.contains(a);
      final bPinned = pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      // Unread
      final aUnread = unreadCounts.containsKey(a) && unreadCounts[a]! > 0;
      final bUnread = unreadCounts.containsKey(b) && unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;

      // Alphabetical
      return a.compareTo(b);
    });
    return sorted;
  }

  void sendMessage() {
    final message = messageController.text.trim();
    if (message.isEmpty) return;

    try {
      if (selectedChat == 'General') {
        // Mesaj public către toți
        channel.sink.add(
          jsonEncode({
            'type': 'message',
            'username': widget.username,
            'message': message,
          }),
        );
        // Șterge draft-ul pentru General după trimitere
        drafts.remove('General');
        messageController.clear();
      } else if (users.contains(selectedChat)) {
        // Mesaj privat către utilizator
        channel.sink.add(
          jsonEncode({
            'type': 'private_message',
            'username': widget.username,
            'target': selectedChat,
            'message': message,
          }),
        );
        // Adaugă mesajul în lista locală
        addSentMessage(message, true, null, selectedChat);
        // Șterge draft-ul după trimitere
        drafts.remove(selectedChat);
        messageController.clear();
      } else if (myGroups.contains(selectedChat)) {
        // Mesaj în grup
        channel.sink.add(
          jsonEncode({
            'type': 'group_message',
            'username': widget.username,
            'group': selectedChat,
            'message': message,
          }),
        );
        // Adaugă mesajul în lista locală
        addSentMessage(message, false, selectedChat);
        // Șterge draft-ul după trimitere
        drafts.remove(selectedChat);
        messageController.clear();
      }

      // Oprește typing indicator după trimitere
      sendTypingIndicator(false);
    } catch (e) {
      print('Eroare la trimiterea mesajului: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Eroare la trimiterea mesajului'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void addSentMessage(
    String message,
    bool isPrivate,
    String? group, [
    String? target,
  ]) {
    setState(() {
      messages.add(
        ChatMessage(
          username: widget.username,
          message: message,
          timestamp: DateTime.now(),
          isPrivate: isPrivate,
          group: group,
          target: target,
        ),
      );
    });
  }

  void createGroup() {
    TextEditingController groupController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Creează un grup'),
        content: TextField(
          controller: groupController,
          decoration: const InputDecoration(labelText: 'Nume grup'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează'),
          ),
          TextButton(
            onPressed: () {
              final groupName = groupController.text.trim();
              if (groupName.isNotEmpty && mounted) {
                channel.sink.add(
                  jsonEncode({
                    'type': 'create_group',
                    'group_name': groupName,
                    'username': widget.username,
                  }),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Creează'),
          ),
        ],
      ),
    );
  }

  void addToGroup(String groupName) {
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nu sunt utilizatori disponibili'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String selectedUser = users.first;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Adaugă în $groupName'),
          content: DropdownButton<String>(
            value: selectedUser,
            items: users.map((user) {
              return DropdownMenuItem<String>(value: user, child: Text(user));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedUser = value;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anulează'),
            ),
            TextButton(
              onPressed: () {
                channel.sink.add(
                  jsonEncode({
                    'type': 'add_to_group',
                    'group_name': groupName,
                    'member': selectedUser,
                  }),
                );
                Navigator.pop(context);
                // Afișează mesaj foarte scurt și sus
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Utilizator adăugat'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(left: 20, right: 20, top: 10),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: const Text('Adaugă'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    channel.sink.close();
    messageController.dispose();
    typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 242, 233, 228),
      body: Row(
        children: [
          // Panoul stâng - Lista utilizatorilor și grupuri
          Container(
            width: 250,
            color: const Color.fromARGB(255, 201, 173, 167),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: const Color.fromARGB(255, 176, 148, 142),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        'Utilizator: ${widget.username}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'GRUPURILE MELE',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                ...getSortedGroups().map(
                  (group) => ListTile(
                    leading: Stack(
                      children: [
                        const Icon(Icons.group),
                        // Red circle indicator for unread
                        if (unreadCounts.containsKey(group) &&
                            unreadCounts[group]! > 0)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color.fromARGB(
                                    255,
                                    201,
                                    173,
                                    167,
                                  ),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  unreadCounts[group]! > 99
                                      ? '99+'
                                      : '${unreadCounts[group]}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(group)),
                        // Draft indicator
                        if (drafts.containsKey(group) &&
                            drafts[group]!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.edit_note,
                              size: 14,
                              color: const Color.fromARGB(255, 103, 80, 164),
                            ),
                          ),
                      ],
                    ),
                    selected: selectedChat == group,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pin button
                        IconButton(
                          icon: Icon(
                            pinnedChats.contains(group)
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 18,
                          ),
                          onPressed: () => togglePin(group),
                        ),
                        // Add member button
                        if (group != 'General')
                          IconButton(
                            icon: const Icon(Icons.add_circle, size: 18),
                            onPressed: () => addToGroup(group),
                          ),
                      ],
                    ),
                    onTap: () => changeChat(group),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Creează grup'),
                  onTap: createGroup,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'UTILIZATORI CONECTAȚI',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: getSortedUsers().length,
                    itemBuilder: (context, index) {
                      final user = getSortedUsers()[index];
                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Text(
                                user[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Color.fromARGB(255, 201, 173, 167),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Red circle indicator for unread
                            if (unreadCounts.containsKey(user) &&
                                unreadCounts[user]! > 0)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      unreadCounts[user]! > 99
                                          ? '99+'
                                          : '${unreadCounts[user]}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(user)),
                            // Draft indicator
                            if (drafts.containsKey(user) &&
                                drafts[user]!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.edit_note,
                                  size: 14,
                                  color: Colors.yellow[700],
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            pinnedChats.contains(user)
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 18,
                          ),
                          onPressed: () => togglePin(user),
                        ),
                        selected: selectedChat == user,
                        onTap: () => changeChat(user),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Panoul drept - Zona de chat
          Expanded(
            child: Column(
              children: [
                // Header chat
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color.fromARGB(255, 201, 173, 167),
                  child: Row(
                    children: [
                      Icon(
                        users.contains(selectedChat)
                            ? Icons.person
                            : Icons.group,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              selectedChat == 'General'
                                  ? 'Chat General'
                                  : selectedChat,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            // Typing indicator in header
                            if (typingUsers.containsKey(selectedChat) &&
                                typingUsers[selectedChat]!)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: TypingIndicator(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Lista mesajelor
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.username == widget.username;
                        // Filtrează mesajele în funcție de chat-ul selectat
                        if (selectedChat == 'General') {
                          if (msg.isPrivate || msg.group != 'General') {
                            return const SizedBox.shrink();
                          }
                        } else if (users.contains(selectedChat)) {
                          // Arată doar mesajele private
                          if (!msg.isPrivate) {
                            return const SizedBox.shrink();
                          }
                          // Arată mesajul dacă sunt în conversația cu sender sau target
                          final otherUser = msg.username == widget.username
                              ? msg.target
                              : msg.username;
                          // Verifică dacă otherUser nu este null
                          if (otherUser == null || otherUser != selectedChat) {
                            return const SizedBox.shrink();
                          }
                        } else if (myGroups.contains(selectedChat)) {
                          if (msg.group != selectedChat || msg.isPrivate) {
                            return const SizedBox.shrink();
                          }
                        }
                        return buildMessageBubble(msg, isMe);
                      },
                    ),
                  ),
                ),
                // Zona de input
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color.fromARGB(255, 242, 233, 228),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          onChanged: onTextChanged,
                          decoration: InputDecoration(
                            hintText: getHintText(),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                          ),
                          onSubmitted: (_) => sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: sendMessage,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            201,
                            173,
                            167,
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String getHintText() {
    if (selectedChat == 'General') {
      return 'Scrie un mesaj public...';
    } else if (users.contains(selectedChat)) {
      return 'Scrie un mesaj privat către $selectedChat...';
    } else {
      return 'Scrie în grupul $selectedChat...';
    }
  }

  Widget buildMessageBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 350),
        decoration: BoxDecoration(
          color: isMe
              ? const Color.fromARGB(255, 201, 173, 167)
              : const Color.fromARGB(255, 242, 233, 228),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.isPrivate
                  ? (isMe
                        ? 'Către: ${msg.target ?? "Necunoscut"}'
                        : 'De la: ${msg.username}')
                  : msg.username,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isMe ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg.message,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              formatTime(msg.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  void handleDisconnect() {
    if (mounted) {
      setState(() {
        isConnected = false;
      });

      // Încearcă să se reconecteze automat la fiecare 3 secunde
      reconnectTimer?.cancel();
      reconnectTimer = Timer.periodic(const Duration(seconds: 3), (
        timer,
      ) async {
        if (isConnected) {
          timer.cancel();
          return;
        }

        reconnectAttempts++;
        print('Încercare reconectare #$reconnectAttempts');

        try {
          final testChannel = WebSocketChannel.connect(
            Uri.parse(host),
          );
          final completer = Completer<bool>();

          // Timeout de 2 secunde
          Timer? timeoutTimer = Timer(const Duration(seconds: 2), () {
            testChannel.sink.close();
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          });

          testChannel.stream.listen(
            (message) {
              timeoutTimer.cancel();
              testChannel.sink.close();
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            },
            onError: (error) {
              timeoutTimer.cancel();
              testChannel.sink.close();
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            },
          );

          final connected = await completer.future;

          if (connected && mounted) {
            timer.cancel();
            reconnectTimer = null;
            // Reconectare completă
            connectToServer();
          }
        } catch (e) {
          print('Eroare reconectare: $e');
        }
      });

      // Afișează dialog cu opțiunea de a reveni la login sau de a aștepta reconectarea
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async {
            reconnectTimer?.cancel();
            reconnectTimer = null;
            Navigator.of(context).pop();
            Navigator.of(context).popUntil((route) => route.isFirst);
            return true;
          },
          child: AlertDialog(
            title: const Text('Deconectat'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Conexiunea cu serverul s-a pierdut.'),
                const SizedBox(height: 10),
                const Text('Se încearcă reconectarea automată...'),
                const SizedBox(height: 10),
                if (isConnected)
                  const Text(
                    'Conectat cu succes!',
                    style: TextStyle(color: Colors.green),
                  )
                else
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Încercare reconectare...'),
                    ],
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  reconnectTimer?.cancel();
                  reconnectTimer = null;
                  Navigator.of(context).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Înapoi la autentificare'),
              ),
            ],
          ),
        ),
      );
    }
  }
}

// Widget pentru typing indicator animat
class TypingIndicator extends StatefulWidget {
  @override
  State<TypingIndicator> createState() => TypingIndicatorState();
}

class TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  int dotCount = 0;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    controller.addListener(() {
      final frame = controller.value * 3;
      setState(() {
        dotCount = (frame % 3).toInt();
      });
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'scrie',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedOpacity(
              opacity: index <= dotCount ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  '.',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String username;
  final String message;
  final DateTime timestamp;
  final bool isPrivate;
  final String? group;
  final String? target;

  ChatMessage({
    required this.username,
    required this.message,
    required this.timestamp,
    this.isPrivate = false,
    this.group,
    this.target,
  });
}
