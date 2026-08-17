import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/model_info.dart';

final modelListProvider =
    StateNotifierProvider<ModelListNotifier, List<ModelInfo>>(
  (ref) => ModelListNotifier(),
);

final selectedModelProvider = StateProvider<ModelInfo?>((ref) => null);

class ModelListNotifier extends StateNotifier<List<ModelInfo>> {
  ModelListNotifier() : super([]) {
    _loadModels();
  }

  Future<void> _loadModels() async {
    final dir = await _modelsDirectory();
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.gguf'),
    ).toList();

    final models = files.map((f) {
      final fileName = p.basename(f.path);
      return ModelInfo(
        id: fileName,
        name: fileName.replaceAll('.gguf', ''),
        description: 'Imported model',
        fileName: fileName,
        downloadUrl: '',
        sizeBytes: f.lengthSync(),
        paramCount: 0,
        quantization: 'unknown',
        aggressiveness: ModelAggressiveness.nonAggressive,
        censorship: ModelCensorship.censored,
        minRamGb: 0,
        isDownloaded: true,
        localPath: f.path,
      );
    }).toList();

    state = models;
  }

  Future<Directory> _modelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  Future<void> addModel(ModelInfo model, String localPath) async {
    state = [
      ...state,
      model.copyWith(isDownloaded: true, localPath: localPath),
    ];
  }

  Future<void> removeModel(String modelId) async {
    final model = state.firstWhere((m) => m.id == modelId);
    if (model.localPath != null) {
      final file = File(model.localPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    state = state.where((m) => m.id != modelId).toList();
  }

  Future<void> refresh() async {
    await _loadModels();
  }
}
