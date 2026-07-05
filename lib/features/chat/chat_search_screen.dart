import 'package:flutter/material.dart';

import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';
import 'widgets/message_bubble.dart';

class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key, required this.messages});

  final List<ChatMessage> messages;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _query = TextEditingController();
  List<ChatMessage> _results = [];

  @override
  void initState() {
    super.initState();
    _query.addListener(_runSearch);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _results = widget.messages.where((m) => m.body.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Search in chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search messages…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_query.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_results.length} result${_results.length == 1 ? '' : 's'}', style: TextStyle(color: ext.subtext)),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final msg = _results[index];
                return MessageBubble(message: msg, showSender: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}
