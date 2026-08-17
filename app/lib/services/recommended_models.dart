import '../models/model_info.dart';

class RecommendedModels {
  static const List<ModelInfo> models = [
    ModelInfo(
      id: 'phi-3-mini-3.8b-q4',
      name: 'Phi-3 Mini 3.8B',
      description: 'Microsoft\'s compact yet capable model. Great for general tasks.',
      fileName: 'Phi-3-mini-3.8B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Phi-3-mini-3.8B-Instruct-GGUF/resolve/main/Phi-3-mini-3.8B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2320000000,
      paramCount: 3800000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.nonAggressive,
      censorship: ModelCensorship.censored,
      minRamGb: 4,
    ),
    ModelInfo(
      id: 'gemma-2-2b-it-q4',
      name: 'Gemma 2 2B',
      description: 'Google\'s lightweight model. Fast and efficient.',
      fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      sizeBytes: 1600000000,
      paramCount: 2000000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.nonAggressive,
      censorship: ModelCensorship.censored,
      minRamGb: 3,
    ),
    ModelInfo(
      id: 'llama-3.2-3b-q4',
      name: 'Llama 3.2 3B',
      description: 'Meta\'s latest small model. Strong reasoning for its size.',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2000000000,
      paramCount: 3000000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.nonAggressive,
      censorship: ModelCensorship.censored,
      minRamGb: 4,
    ),
    ModelInfo(
      id: 'dolphin-2.6-mistral-7b-q4',
      name: 'Dolphin 2.6 Mistral 7B',
      description: 'Uncensored model based on Mistral. Aggressive and unrestricted.',
      fileName: 'dolphin-2.6-mistral-7b-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/dolphin-2.6-mistral-7B-GGUF/resolve/main/dolphin-2.6-mistral-7B-Q4_K_M.gguf',
      sizeBytes: 4100000000,
      paramCount: 7000000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.aggressive,
      censorship: ModelCensorship.uncensored,
      minRamGb: 8,
    ),
    ModelInfo(
      id: 'smollm2-1.7b-q4',
      name: 'SmolLM2 1.7B',
      description: 'HuggingFace\'s tiny model. Extremely fast, good for simple tasks.',
      fileName: 'SmolLM2-1.7B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf',
      sizeBytes: 1000000000,
      paramCount: 1700000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.nonAggressive,
      censorship: ModelCensorship.censored,
      minRamGb: 2,
    ),
    ModelInfo(
      id: 'qwen2.5-3b-q4',
      name: 'Qwen 2.5 3B',
      description: 'Alibaba\'s compact model. Strong multilingual and coding ability.',
      fileName: 'qwen2.5-3b-instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2100000000,
      paramCount: 3000000000,
      quantization: 'Q4_K_M',
      aggressiveness: ModelAggressiveness.nonAggressive,
      censorship: ModelCensorship.censored,
      minRamGb: 4,
    ),
  ];

  static List<ModelInfo> getRecommendedForDevice(int ramGb) {
    return models.where((m) => m.minRamGb <= ramGb).toList()
      ..sort((a, b) => a.minRamGb.compareTo(b.minRamGb));
  }
}
