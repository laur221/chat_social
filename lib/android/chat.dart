import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatScreen extends StatefulWidget {
  final String username;
  final WebSocketChannel? channel;

  const ChatScreen({super.key, required this.username, this.channel});

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
  final Set<String> myGroups = {'General'};
  final Map<String, String> drafts = {};
  final Map<String, int> unreadCounts = {};
  final Set<String> pinnedChats = {};
  final Map<String, bool> typingUsers = {};
  Timer? typingTimer;
  int reconnectAttempts = 0;
  Timer? reconnectTimer;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    if (widget.channel == null) {
      print('[DEBUG] No channel provided, connecting...');
      connectToServer();
    } else {
      channel = widget.channel!;
      channel.stream.listen(
        (message) {
          setState(() {
            isConnected = true;
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
      print('[DEBUG] Using existing channel from login');
    }
  }

  void connectToServer() {
    try {
      channel = WebSocketChannel.connect(Uri.parse(host));
      channel.stream.listen(
        (message) {
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
            if (selectedChat != sender && target == widget.username) {
              unreadCounts[sender] = (unreadCounts[sender] ?? 0) + 1;
            }
            break;
          case 'group_message':
            final group = data['group'] as String;
            final sender = data['username'] as String;
            if (sender != widget.username) {
              final msg = ChatMessage(
                username: sender,
                message: data['message'] as String,
                timestamp: DateTime.parse(data['timestamp'] as String),
                isPrivate: false,
                group: group,
              );
              messages.add(msg);
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

  void saveCurrentDraft() {
    if (messageController.text.isNotEmpty) {
      drafts[selectedChat] = messageController.text;
    }
  }

  void loadDraft(String chatId) {
    messageController.text = drafts[chatId] ?? '';
  }

  void changeChat(String newChat) {
    saveCurrentDraft();
    setState(() {
      selectedChat = newChat;
      unreadCounts.remove(newChat);
    });
    loadDraft(newChat);
    Navigator.pop(context);
  }

  void togglePin(String chatId) {
    setState(() {
      if (pinnedChats.contains(chatId)) {
        pinnedChats.remove(chatId);
      } else {
        pinnedChats.add(chatId);
      }
    });
  }

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

  void onTextChanged(String text) {
    sendTypingIndicator(true);
    typingTimer?.cancel();
    typingTimer = Timer(const Duration(seconds: 2), () {
      sendTypingIndicator(false);
    });
  }

  List<String> getSortedUsers() {
    final sorted = List<String>.from(users);
    sorted.sort((a, b) {
      final aPinned = pinnedChats.contains(a);
      final bPinned = pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final aUnread = unreadCounts.containsKey(a) && unreadCounts[a]! > 0;
      final bUnread = unreadCounts.containsKey(b) && unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;

      return a.compareTo(b);
    });
    return sorted;
  }

  List<String> getSortedGroups() {
    final sorted = myGroups.toList();
    sorted.sort((a, b) {
      if (a == 'General') return -1;
      if (b == 'General') return 1;

      final aPinned = pinnedChats.contains(a);
      final bPinned = pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final aUnread = unreadCounts.containsKey(a) && unreadCounts[a]! > 0;
      final bUnread = unreadCounts.containsKey(b) && unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;

      return a.compareTo(b);
    });
    return sorted;
  }

  void sendMessage() {
    final message = messageController.text.trim();
    if (message.isEmpty) return;

    try {
      if (selectedChat == 'General') {
        channel.sink.add(
          jsonEncode({
            'type': 'message',
            'username': widget.username,
            'message': message,
          }),
        );
        drafts.remove('General');
        messageController.clear();
      } else if (users.contains(selectedChat)) {
        channel.sink.add(
          jsonEncode({
            'type': 'private_message',
            'username': widget.username,
            'target': selectedChat,
            'message': message,
          }),
        );
        addSentMessage(message, true, null, selectedChat);
        drafts.remove(selectedChat);
        messageController.clear();
      } else if (myGroups.contains(selectedChat)) {
        channel.sink.add(
          jsonEncode({
            'type': 'group_message',
            'username': widget.username,
            'group': selectedChat,
            'message': message,
          }),
        );
        addSentMessage(message, false, selectedChat);
        drafts.remove(selectedChat);
        messageController.clear();
      }

      sendTypingIndicator(false);
    } catch (e) {
      print('Eroare la trimiterea mesajului: $e');
    }
  }

  void addSentMessage(String message, bool isPrivate, String? group, [String? target]) {
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
        const SnackBar(content: Text('Nu sunt utilizatori disponibili')),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Utilizator adăugat')),
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
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 201, 173, 167),
        title: Row(
          children: [
            Icon(
              users.contains(selectedChat) ? Icons.person : Icons.group,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedChat == 'General' ? 'Chat General' : selectedChat,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (typingUsers.containsKey(selectedChat) && typingUsers[selectedChat]!)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TypingIndicator(),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: Drawer(
        child: Container(
          color: const Color.fromARGB(255, 201, 173, 167),
          child: ListView(
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 176, 148, 142),
                ),
                accountName: Text(
                  widget.username,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                accountEmail: const Text(
                  'Chat Social',
                  style: TextStyle(color: Colors.white),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    widget.username[0].toUpperCase(),
                    style: const TextStyle(
                      color: Color.fromARGB(255, 201, 173, 167),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'GRUPURILE MELE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...getSortedGroups().map(
                (group) => ListTile(
                  leading: Stack(
                    children: [
                      const Icon(Icons.group, color: Colors.white),
                      if (unreadCounts.containsKey(group) && unreadCounts[group]! > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
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
                  title: Text(
                    group,
                    style: const TextStyle(color: Colors.white),
                  ),
                  selected: selectedChat == group,
                  selectedTileColor: Colors.white.withOpacity(0.24),
                  onTap: () => changeChat(group),
                  trailing: group != 'General'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                pinnedChats.contains(group)
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                color: Colors.white,
                              ),
                              onPressed: () => togglePin(group),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.white),
                              onPressed: () => addToGroup(group),
                            ),
                          ],
                        )
                      : IconButton(
                          icon: Icon(
                            pinnedChats.contains(group)
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            color: Colors.white,
                          ),
                          onPressed: () => togglePin(group),
                        ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add, color: Colors.white),
                title: const Text(
                  'Creează grup',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  createGroup();
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'UTILIZATORI CONECTAȚI',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...getSortedUsers().map(
                (user) => ListTile(
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
                      if (unreadCounts.containsKey(user) && unreadCounts[user]! > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
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
                  title: Text(
                    user,
                    style: const TextStyle(color: Colors.white),
                  ),
                  selected: selectedChat == user,
                  selectedTileColor: Colors.white.withOpacity(0.24),
                  onTap: () => changeChat(user),
                  trailing: IconButton(
                    icon: Icon(
                      pinnedChats.contains(user)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => togglePin(user),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.white,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg.username == widget.username;

                  if (selectedChat == 'General') {
                    if (msg.isPrivate || msg.group != 'General') {
                      return SizedBox.shrink();
                    }
                  } else if (users.contains(selectedChat)) {
                    if (!msg.isPrivate) {
                      return SizedBox.shrink();
                    }
                    final otherUser = msg.username == widget.username
                        ? msg.target
                        : msg.username;
                    if (otherUser == null || otherUser != selectedChat) {
                      return SizedBox.shrink();
                    }
                  } else if (myGroups.contains(selectedChat)) {
                    if (msg.group != selectedChat || msg.isPrivate) {
                      return SizedBox.shrink();
                    }
                  }

                  return buildMessageBubble(msg, isMe);
                },
              ),
            ),
          ),
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
                    backgroundColor: const Color.fromARGB(255, 201, 173, 167),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(12),
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
        constraints: const BoxConstraints(maxWidth: 280),
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

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Deconectat'),
          content: const Text('Conexiunea cu serverul s-a pierdut.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Înapoi la autentificare'),
            ),
          ],
        ),
      );
    }
  }
}

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
        const Text('scrie', style: TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedOpacity(
              opacity: index <= dotCount ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text('.', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            );
          }).toList(),
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
