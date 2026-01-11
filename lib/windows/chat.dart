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
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late WebSocketChannel _channel;
  final List<String> _users = [];
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  String _selectedChat = 'General';
  final List<String> _groups = [];
  // Stocăm grupurile la care utilizatorul este membru
  final Set<String> _myGroups = {'General'};
  // Draft-uri pentru fiecare chat: {chat_id: draft_text}
  final Map<String, String> _drafts = {};
  // Contor mesaje necitite: {chat_id: count}
  final Map<String, int> _unreadCounts = {};
  // Pinned chats (users and groups)
  final Set<String> _pinnedChats = {};

  @override
  void initState() {
    super.initState();
    _connectToServer();
    // Schimbă dimensiunea ferestrei la 1200x800
    Future.delayed(const Duration(milliseconds: 100), () {
      setWindowFrame(const Rect.fromLTWH(100, 100, 1200, 800));
      setWindowMinSize(const Size(1200, 800));
      setWindowMaxSize(Size.infinite);
    });
  }

  void _connectToServer() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));
      _channel.stream.listen(
        (message) {
          final data = jsonDecode(message) as Map<String, dynamic>;
          _handleServerMessage(data);
        },
        onError: (error) {
          print('Eroare WebSocket: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('WebSocket deconectat');
          _handleDisconnect();
        },
      );

      // Trimite autentificarea
      _channel.sink.add(jsonEncode({
        'type': 'auth',
        'username': widget.username,
      }));
    } catch (e) {
      print('Eroare la conectare: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nu s-a putut conecta la server'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleServerMessage(Map<String, dynamic> data) {
    setState(() {
      switch (data['type'] as String) {
        case 'user_list':
          _users.clear();
          _users.addAll((data['users'] as List).cast<String>());
          break;
        case 'message':
          final msg = ChatMessage(
            username: data['username'] as String,
            message: data['message'] as String,
            timestamp: DateTime.parse(data['timestamp'] as String),
            isPrivate: false,
            group: 'General',
          );
          _messages.add(msg);
          // Increment unread count for General
          if (_selectedChat != 'General') {
            _unreadCounts['General'] = (_unreadCounts['General'] ?? 0) + 1;
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
          _messages.add(msg);
          // Increment unread count for the sender
          if (_selectedChat != sender && target == widget.username) {
            _unreadCounts[sender] = (_unreadCounts[sender] ?? 0) + 1;
          }
          break;
        case 'group_message':
          final group = data['group'] as String;
          final msg = ChatMessage(
            username: data['username'] as String,
            message: data['message'] as String,
            timestamp: DateTime.parse(data['timestamp'] as String),
            isPrivate: false,
            group: group,
          );
          _messages.add(msg);
          // Increment unread count for the group
          if (_selectedChat != group) {
            _unreadCounts[group] = (_unreadCounts[group] ?? 0) + 1;
          }
          break;
        case 'group_created':
          final groupName = data['group_name'] as String;
          if (!_groups.contains(groupName)) {
            _groups.add(groupName);
            if (data['creator'] == widget.username) {
              _myGroups.add(groupName);
            }
          }
          break;
        case 'added_to_group':
          final groupName = data['group_name'] as String;
          if (!_myGroups.contains(groupName)) {
            _myGroups.add(groupName);
            if (!_groups.contains(groupName)) {
              _groups.add(groupName);
            }
          }
          break;
      }
    });
  }

  // Salvează draft-ul curent înainte de a schimba chat-ul
  void _saveCurrentDraft() {
    if (_messageController.text.isNotEmpty) {
      _drafts[_selectedChat] = _messageController.text;
    }
  }

  // Încarcă draft-ul pentru un chat
  void _loadDraft(String chatId) {
    _messageController.text = _drafts[chatId] ?? '';
  }

  // Schimbă chat-ul și gestionează draft-urile
  void _changeChat(String newChat) {
    _saveCurrentDraft();
    // Clear unread count when opening chat
    setState(() {
      _selectedChat = newChat;
      _unreadCounts.remove(newChat);
    });
    _loadDraft(newChat);
  }

  // Toggle pin/unpin
  void _togglePin(String chatId) {
    setState(() {
      if (_pinnedChats.contains(chatId)) {
        _pinnedChats.remove(chatId);
      } else {
        _pinnedChats.add(chatId);
      }
    });
  }

  // Sort users: pinned first, then unread, then alphabetical
  List<String> _getSortedUsers() {
    final sorted = List<String>.from(_users);
    sorted.sort((a, b) {
      // Pinned first
      final aPinned = _pinnedChats.contains(a);
      final bPinned = _pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      
      // Unread next
      final aUnread = _unreadCounts.containsKey(a) && _unreadCounts[a]! > 0;
      final bUnread = _unreadCounts.containsKey(b) && _unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;
      
      // Alphabetical
      return a.compareTo(b);
    });
    return sorted;
  }

  // Sort groups: pinned first, then unread, then alphabetical
  List<String> _getSortedGroups() {
    final sorted = _myGroups.toList();
    sorted.sort((a, b) {
      // General always first
      if (a == 'General') return -1;
      if (b == 'General') return 1;
      
      // Pinned
      final aPinned = _pinnedChats.contains(a);
      final bPinned = _pinnedChats.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      
      // Unread
      final aUnread = _unreadCounts.containsKey(a) && _unreadCounts[a]! > 0;
      final bUnread = _unreadCounts.containsKey(b) && _unreadCounts[b]! > 0;
      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;
      
      // Alphabetical
      return a.compareTo(b);
    });
    return sorted;
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    if (_selectedChat == 'General') {
      // Mesaj public către toți
      _channel.sink.add(jsonEncode({
        'type': 'message',
        'username': widget.username,
        'message': message,
      }));
      // Șterge draft-ul pentru General după trimitere
      _drafts.remove('General');
      _messageController.clear();
    } else if (_users.contains(_selectedChat)) {
      // Mesaj privat către utilizator
      _channel.sink.add(jsonEncode({
        'type': 'private_message',
        'username': widget.username,
        'target': _selectedChat,
        'message': message,
      }));
      // Adaugă mesajul în lista locală
      _addSentMessage(message, true, null, _selectedChat);
      // Șterge draft-ul după trimitere
      _drafts.remove(_selectedChat);
      _messageController.clear();
    } else if (_myGroups.contains(_selectedChat)) {
      // Mesaj în grup
      _channel.sink.add(jsonEncode({
        'type': 'group_message',
        'username': widget.username,
        'group': _selectedChat,
        'message': message,
      }));
      // Adaugă mesajul în lista locală
      _addSentMessage(message, false, _selectedChat);
      // Șterge draft-ul după trimitere
      _drafts.remove(_selectedChat);
      _messageController.clear();
    }
  }

  void _addSentMessage(String message, bool isPrivate, String? group, [String? target]) {
    setState(() {
      _messages.add(ChatMessage(
        username: widget.username,
        message: message,
        timestamp: DateTime.now(),
        isPrivate: isPrivate,
        group: group,
        target: target,
      ));
    });
  }

  void _createGroup() {
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
                _channel.sink.add(jsonEncode({
                  'type': 'create_group',
                  'group_name': groupName,
                  'username': widget.username,
                }));
                Navigator.pop(context);
              }
            },
            child: const Text('Creează'),
          ),
        ],
      ),
    );
  }

  void _addToGroup(String groupName) {
    if (_users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nu sunt utilizatori disponibili'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String selectedUser = _users.first;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Adaugă în $groupName'),
          content: DropdownButton<String>(
            value: selectedUser,
            items: _users.map((user) {
              return DropdownMenuItem<String>(
                value: user,
                child: Text(user),
              );
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
                _channel.sink.add(jsonEncode({
                  'type': 'add_to_group',
                  'group_name': groupName,
                  'member': selectedUser,
                }));
                Navigator.pop(context);
                // Afișează mesaj foarte scurt și sus
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Utilizator adăugat'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 10,
                    ),
                    duration: const Duration(seconds:1),
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
    _channel.sink.close();
    _messageController.dispose();
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
            width: 280,
            color: const Color.fromARGB(255, 201, 173, 167),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
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
                ..._getSortedGroups().map((group) => ListTile(
                      leading: Stack(
                        children: [
                          const Icon(Icons.group),
                          // Red circle indicator for unread
                          if (_unreadCounts.containsKey(group) && _unreadCounts[group]! > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color.fromARGB(255, 201, 173, 167), width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    _unreadCounts[group]! > 99 ? '99+' : '${_unreadCounts[group]}',
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
                          if (_drafts.containsKey(group) && _drafts[group]!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left:4),
                              child: Icon(Icons.edit_note, size: 14, color: Colors.yellow[700]),
                            ),
                        ],
                      ),
                      selected: _selectedChat == group,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pin button
                          IconButton(
                            icon: Icon(
                              _pinnedChats.contains(group) ? Icons.push_pin : Icons.push_pin_outlined,
                              size: 18,
                            ),
                            onPressed: () => _togglePin(group),
                          ),
                          // Add member button
                          if (group != 'General')
                            IconButton(
                              icon: const Icon(Icons.add_circle, size: 18),
                              onPressed: () => _addToGroup(group),
                            ),
                        ],
                      ),
                      onTap: () => _changeChat(group),
                    )),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Creează grup'),
                  onTap: _createGroup,
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
                    itemCount: _getSortedUsers().length,
                    itemBuilder: (context, index) {
                      final user = _getSortedUsers()[index];
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
                            if (_unreadCounts.containsKey(user) && _unreadCounts[user]! > 0)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _unreadCounts[user]! > 99 ? '99+' : '${_unreadCounts[user]}',
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
                            if (_drafts.containsKey(user) && _drafts[user]!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left:4),
                                child: Icon(Icons.edit_note, size: 14, color: Colors.yellow[700]),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            _pinnedChats.contains(user) ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 18,
                          ),
                          onPressed: () => _togglePin(user),
                        ),
                        selected: _selectedChat == user,
                        onTap: () => _changeChat(user),
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
                        _users.contains(_selectedChat)
                            ? Icons.person
                            : Icons.group,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _selectedChat == 'General' ? 'Chat General' : _selectedChat,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
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
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.username == widget.username;
                        // Filtrează mesajele în funcție de chat-ul selectat
                        if (_selectedChat == 'General') {
                          if (msg.isPrivate || msg.group != 'General') {
                            return const SizedBox.shrink();
                          }
                        } else if (_users.contains(_selectedChat)) {
                          if (!msg.isPrivate || 
                              (msg.target != _selectedChat && msg.username != _selectedChat)) {
                            return const SizedBox.shrink();
                          }
                        } else if (_myGroups.contains(_selectedChat)) {
                          if (msg.group != _selectedChat || msg.isPrivate) {
                            return const SizedBox.shrink();
                          }
                        }
                        return _buildMessageBubble(msg, isMe);
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
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: _getHintText(),
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
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _sendMessage,
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
          ),
        ],
      ),
    );
  }

  String _getHintText() {
    if (_selectedChat == 'General') {
      return 'Scrie un mesaj public...';
    } else if (_users.contains(_selectedChat)) {
      return 'Scrie un mesaj privat către $_selectedChat...';
    } else {
      return 'Scrie în grupul $_selectedChat...';
    }
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
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
                  ? (isMe ? 'Către: ${msg.target ?? "Necunoscut"}' : 'De la: ${msg.username}')
                  : msg.username,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isMe ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height:4),
            Text(
              msg.message,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height:4),
            Text(
              _formatTime(msg.timestamp),
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

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  void _handleDisconnect() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Deconectat'),
          content: const Text('Conexiunea cu serverul s-a pierdut. Vei fi redirecționat spre pagina de autentificare.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
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
