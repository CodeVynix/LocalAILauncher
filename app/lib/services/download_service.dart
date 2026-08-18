import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/model_info.dart';
import 'notification_service.dart';

class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final double speedBytesPerSecond;
  final bool isPaused;
  final bool isCancelled;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    this.isPaused = false,
    this.isCancelled = false,
  });

  double get progress =>
      totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;

  String get display =>
      '${(bytesDownloaded / 1048576).toStringAsFixed(1)} MB / ${(totalBytes / 1073741824).toStringAsFixed(2)} GB';

  String get speedDisplay =>
      '${(speedBytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';
}

class DownloadService {
  final Map<String, DownloadTask> _activeTasks = {};
  final Map<String, StreamController<DownloadProgress>> _controllers = {};
  final Map<String, DateTime> _startTime = {};
  final Map<String, int> _bytesAtLastUpdate = {};

  StreamController<DownloadProgress>? getController(String modelId) {
    return _controllers[modelId];
  }

  Future<DownloadProgress> downloadModel(
    ModelInfo model,
    Function(DownloadProgress) onProgress,
  ) async {
    final controller = StreamController<DownloadProgress>.broadcast();
    _controllers[model.id] = controller;

    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final task = DownloadTask(
      url: model.downloadUrl,
      filename: model.fileName,
      directory: 'models',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      requiresWiFi: false,
      retries: 3,
      allowPause: true,
      metaData: model.id,
    );

    _activeTasks[model.id] = task;
    _startTime[model.id] = DateTime.now();
    _bytesAtLastUpdate[model.id] = 0;

    try {
      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          final totalBytes = model.sizeBytes;
          final bytesDownloaded = (progress * totalBytes).toInt();
          final now = DateTime.now();
          final elapsed = now.difference(_startTime[model.id]!).inMilliseconds;
          final prevBytes = _bytesAtLastUpdate[model.id] ?? 0;
          final speed = elapsed > 0
              ? ((bytesDownloaded - prevBytes) * 1000 / elapsed)
              : 0.0;
          _bytesAtLastUpdate[model.id] = bytesDownloaded;

          final dlProgress = DownloadProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
          );
          onProgress(dlProgress);
          controller.add(dlProgress);
        },
        onStatus: (status) {
          if (status == TaskStatus.paused) {
            final pausedProgress = DownloadProgress(
              bytesDownloaded: _bytesAtLastUpdate[model.id] ?? 0,
              totalBytes: model.sizeBytes,
              speedBytesPerSecond: 0,
              isPaused: true,
            );
            onProgress(pausedProgress);
            controller.add(pausedProgress);
          }
        },
      );

      if (result.status == TaskStatus.complete) {
        final finalProgress = DownloadProgress(
          bytesDownloaded: model.sizeBytes,
          totalBytes: model.sizeBytes,
          speedBytesPerSecond: 0,
        );
        onProgress(finalProgress);
        controller.add(finalProgress);
        await controller.close();
        _cleanup(model.id);
        NotificationService.showDownloadComplete(model.name);
        return finalProgress;
      } else if (result.status == TaskStatus.canceled) {
        final cancelProgress = DownloadProgress(
          bytesDownloaded: 0,
          totalBytes: model.sizeBytes,
          speedBytesPerSecond: 0,
          isCancelled: true,
        );
        onProgress(cancelProgress);
        controller.add(cancelProgress);
        await controller.close();
        _cleanup(model.id);
        return cancelProgress;
      } else if (result.status == TaskStatus.paused) {
        final pausedProgress = DownloadProgress(
          bytesDownloaded: _bytesAtLastUpdate[model.id] ?? 0,
          totalBytes: model.sizeBytes,
          speedBytesPerSecond: 0,
          isPaused: true,
        );
        onProgress(pausedProgress);
        controller.add(pausedProgress);
        await controller.close();
        _cleanup(model.id);
        return pausedProgress;
      } else {
        throw Exception('Download failed: ${result.status}');
      }
    } catch (e) {
      await controller.close();
      _cleanup(model.id);
      rethrow;
    }
  }

  void pauseDownload(String modelId) {
    final task = _activeTasks[modelId];
    if (task != null) {
      FileDownloader().pause(task);
    }
  }

  void resumeDownload(String modelId) {
    final task = _activeTasks[modelId];
    if (task != null) {
      FileDownloader().resume(task);
    }
  }

  void cancelDownload() {
    for (final entry in _activeTasks.entries) {
      FileDownloader().cancelTaskWithId(entry.value.taskId);
    }
    for (final controller in _controllers.values) {
      controller.close();
    }
    _activeTasks.clear();
    _controllers.clear();
    _startTime.clear();
    _bytesAtLastUpdate.clear();
  }

  void _cleanup(String modelId) {
    _activeTasks.remove(modelId);
    _controllers.remove(modelId);
    _startTime.remove(modelId);
    _bytesAtLastUpdate.remove(modelId);
  }
}
