import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../providers/model_selection_provider.dart';
import '../providers/tab_provider.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final isGenerating = ref.watch(isGeneratingProvider);
    final models = ref.watch(modelListProvider);

    if (models.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Error: No local model detected, download one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(currentTabProvider.notifier).state = 1;
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Go to Download'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (models.length >= 2 && selectedModel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.tune, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Select your local model',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Multiple models are available. Choose one to start chatting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    hint: const Text('Select a model'),
                    items: models
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (modelId) {
                      if (modelId == null) return;
                      final model = models.firstWhere((m) => m.id == modelId);
                      ref
                          .read(selectedModelProvider.notifier)
                          .selectModel(model);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedModel!.name),
        actions: [
          if (isGenerating)
            IconButton(
              icon: const Icon(Icons.stop_circle),
              onPressed: () {
                ref.read(chatMessagesProvider.notifier).cancelGeneration();
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).clearMessages();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      _scrollToBottom();
                      return ChatBubble(
                        message: msg.content,
                        isUser: msg.role == 'user',
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(25),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty && !isGenerating) {
                          ref
                              .read(chatMessagesProvider.notifier)
                              .sendMessage(value.trim());
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isGenerating
                        ? null
                        : () {
                            if (_controller.text.trim().isNotEmpty) {
                              ref
                                  .read(chatMessagesProvider.notifier)
                                  .sendMessage(_controller.text.trim());
                              _controller.clear();
                            }
                          },
                    icon: isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
