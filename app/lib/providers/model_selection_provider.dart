import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/model_info.dart';
import 'model_provider.dart';

const _kSelectedModelIdKey = 'selected_model_id';

/// Persists the selected model ID in shared_preferences and exposes
/// the actively-selected ModelInfo (or null) to the rest of the app.
final selectedModelProvider =
    StateNotifierProvider<SelectedModelNotifier, ModelInfo?>(
  (ref) => SelectedModelNotifier(ref),
);

class SelectedModelNotifier extends StateNotifier<ModelInfo?> {
  final Ref ref;

  SelectedModelNotifier(this.ref) : super(null) {
    _restoreSelection();
    // Listen for changes to the model list so we can auto-select or
    // invalidate the selection when models are added/removed.
    ref.listen<List<ModelInfo>>(modelListProvider, (prev, next) {
      _onModelsChanged(next);
    });
  }

  /// Restore persisted selection from disk. Falls back to auto-selecting
  /// the sole model if exactly one exists, or null otherwise.
  Future<void> _restoreSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kSelectedModelIdKey);

    final models = ref.read(modelListProvider);
    if (models.isEmpty) {
      state = null;
      return;
    }

    if (savedId != null) {
      final match = models.where((m) => m.id == savedId);
      if (match.isNotEmpty) {
        debugPrint('[ModelSelection] Restored persisted model: $savedId');
        state = match.first;
        return;
      }
      debugPrint('[ModelSelection] Persisted model "$savedId" no longer exists');
    }

    // No valid persisted selection — auto-select if exactly one model.
    if (models.length == 1) {
      debugPrint('[ModelSelection] Auto-selected sole model: ${models.first.id}');
      state = models.first;
      await prefs.setString(_kSelectedModelIdKey, models.first.id);
    } else {
      debugPrint(
        '[ModelSelection] ${models.length} models, no persisted selection — '
        'user must choose',
      );
      state = null;
    }
  }

  /// When the model list changes: keep selection if still valid,
  /// auto-select if only one remains, or clear selection.
  void _onModelsChanged(List<ModelInfo> models) {
    if (models.isEmpty) {
      state = null;
      _persistSelection(null);
      return;
    }

    if (state != null) {
      final match = models.where((m) => m.id == state!.id).toList();
      if (match.isNotEmpty) {
        if (match.first.localPath != state!.localPath) {
          state = match.first;
        }
        return;
      }
    }

    // Current selection is gone or was null.
    if (models.length == 1) {
      state = models.first;
      _persistSelection(models.first);
    } else {
      state = null;
      _persistSelection(null);
    }
  }

  /// Manually select a model (from a dropdown, etc.).
  Future<void> selectModel(ModelInfo model) async {
    debugPrint('[ModelSelection] User selected: ${model.id}');
    state = model;
    await _persistSelection(model);
  }

  Future<void> _persistSelection(ModelInfo? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_kSelectedModelIdKey);
    } else {
      await prefs.setString(_kSelectedModelIdKey, model.id);
    }
  }
}
