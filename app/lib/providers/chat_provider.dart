import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fllama/fllama.dart';
import '../models/chat_message.dart';
import 'settings_provider.dart';
import 'model_selection_provider.dart';

final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
  (ref) => ChatMessagesNotifier(ref),
);

final isGeneratingProvider = StateProvider<bool>((ref) => false);
final currentRequestIdProvider = StateProvider<int?>((ref) => null);

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;
  Timer? _callbackTimeout;

  ChatMessagesNotifier(this.ref) : super([]);

  void clearMessages() {
    state = [];
  }

  void _failWithError(String errorMsg) {
    debugPrint('[Chat] Error: $errorMsg');
    final updatedMessages = List<ChatMessage>.from(state);
    final lastIndex = updatedMessages.length - 1;
    if (lastIndex >= 0 && updatedMessages[lastIndex].role == 'assistant') {
      updatedMessages[lastIndex] = ChatMessage(
        role: 'assistant',
        content: 'Error generating response: $errorMsg',
        timestamp: updatedMessages[lastIndex].timestamp,
      );
      state = updatedMessages;
    }
    ref.read(isGeneratingProvider.notifier).state = false;
    ref.read(currentRequestIdProvider.notifier).state = null;
  }

  Future<void> sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    final userMsg = ChatMessage(role: 'user', content: userMessage);
    state = [...state, userMsg];

    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel == null || selectedModel.localPath == null) {
      _failWithError('No model selected.');
      return;
    }

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
      numGpuLayers: 0,
    );

    debugPrint(
      '[Chat] Sending request — model: ${selectedModel.localPath}, '
      'temp: ${settings.temperature}, gpuLayers: 0, messages: ${messages.length}',
    );

    bool callbackFired = false;

    try {
      final requestId = await fllamaChat(
        request,
        (response, openaiJson, done) {
          if (!callbackFired) {
            callbackFired = true;
            debugPrint('[Chat] Response callback invoked for the first time');
            _callbackTimeout?.cancel();
          }

          if (done) {
            debugPrint('[Chat] Response complete');
            ref.read(isGeneratingProvider.notifier).state = false;
            ref.read(currentRequestIdProvider.notifier).state = null;
          }

          final updatedMessages = List<ChatMessage>.from(state);
          final lastIndex = updatedMessages.length - 1;
          if (lastIndex >= 0 &&
              updatedMessages[lastIndex].role == 'assistant') {
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
      debugPrint('[Chat] fllamaChat returned requestId: $requestId');

      if (!callbackFired) {
        _callbackTimeout = Timer(const Duration(seconds: 60), () {
          if (!callbackFired) {
            debugPrint('[Chat] TIMEOUT: no response after 60 seconds');
            _failWithError(
              'The model did not respond within 60 seconds. '
              'Try a shorter message or check your device resources.',
            );
          }
        });
      }
    } catch (e) {
      debugPrint('[Chat] Exception from fllamaChat: $e');
      _failWithError('$e');
    }
  }

  void cancelGeneration() {
    _callbackTimeout?.cancel();
    final requestId = ref.read(currentRequestIdProvider);
    if (requestId != null) {
      fllamaCancelInference(requestId);
      ref.read(isGeneratingProvider.notifier).state = false;
      ref.read(currentRequestIdProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _callbackTimeout?.cancel();
    super.dispose();
  }
}
