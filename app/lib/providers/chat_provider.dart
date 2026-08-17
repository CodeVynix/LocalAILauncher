import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fllama/fllama.dart';
import '../models/chat_message.dart';
import 'settings_provider.dart';
import 'model_provider.dart';

final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
  (ref) => ChatMessagesNotifier(ref),
);

final isGeneratingProvider = StateProvider<bool>((ref) => false);
final currentRequestIdProvider = StateProvider<int?>((ref) => null);

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;

  ChatMessagesNotifier(this.ref) : super([]);

  void clearMessages() {
    state = [];
  }

  Future<void> sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    final userMsg = ChatMessage(role: 'user', content: userMessage);
    state = [...state, userMsg];

    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel == null || selectedModel.localPath == null) return;

    ref.read(isGeneratingProvider.notifier).state = true;

    final settings = ref.read(settingsProvider);
    final assistantMsg = ChatMessage(role: 'assistant', content: '');
    state = [...state, assistantMsg];

    final messages = state
        .where((m) => m.content.isNotEmpty || m.role == 'assistant')
        .map((m) => Message(
              m.role == 'user' ? Role.user : Role.assistant,
              m.content,
            ))
        .toList();

    final request = OpenAiRequest(
      messages: messages,
      modelPath: selectedModel.localPath!,
      temperature: settings.temperature,
      maxTokens: 2048,
      contextSize: 4096,
      numGpuLayers: 99,
    );

    final requestId = await fllamaChat(
      request,
      (response, openaiJson, done) {
        if (done) {
          ref.read(isGeneratingProvider.notifier).state = false;
          ref.read(currentRequestIdProvider.notifier).state = null;
        }

        final updatedMessages = List<ChatMessage>.from(state);
        final lastIndex = updatedMessages.length - 1;
        if (lastIndex >= 0 && updatedMessages[lastIndex].role == 'assistant') {
          updatedMessages[lastIndex] = ChatMessage(
            role: 'assistant',
            content: response,
            timestamp: updatedMessages[lastIndex].timestamp,
          );
          state = updatedMessages;
        }
      },
    );

    ref.read(currentRequestIdProvider.notifier).state = requestId;
  }

  void cancelGeneration() {
    final requestId = ref.read(currentRequestIdProvider);
    if (requestId != null) {
      fllamaCancelInference(requestId);
      ref.read(isGeneratingProvider.notifier).state = false;
      ref.read(currentRequestIdProvider.notifier).state = null;
    }
  }
}
