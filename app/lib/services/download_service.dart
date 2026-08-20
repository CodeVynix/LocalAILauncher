import 'dart:async';
import 'package:background_downloader/background_downloader.dart';
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
  final Map<String, DateTime> _lastUpdateTime = {};
  final Map<String, int> _lastBytes = {};
  final Map<String, double> _smoothedSpeed = {};

  StreamController<DownloadProgress>? getController(String modelId) {
    return _controllers[modelId];
  }

  Future<DownloadProgress> downloadModel(
    ModelInfo model,
    Function(DownloadProgress) onProgress,
  ) async {
    final controller = StreamController<DownloadProgress>.broadcast();
    _controllers[model.id] = controller;

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
    _lastUpdateTime[model.id] = DateTime.now();
    _lastBytes[model.id] = 0;
    _smoothedSpeed[model.id] = 0.0;

    try {
      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          final totalBytes = model.sizeBytes;
          var bytesDownloaded = (progress * totalBytes).toInt();
          final now = DateTime.now();

          // Clamp against known state to handle out-of-order callbacks
          final lastBytes = _lastBytes[model.id] ?? 0;
          if (bytesDownloaded < lastBytes && progress > 0) {
            bytesDownloaded = lastBytes;
          }
          if (bytesDownloaded < 0) bytesDownloaded = 0;
          if (bytesDownloaded > totalBytes) bytesDownloaded = totalBytes;
          final deltaBytes = bytesDownloaded > lastBytes
              ? bytesDownloaded - lastBytes
              : 0;
          _lastBytes[model.id] = bytesDownloaded;

          final lastTime = _lastUpdateTime[model.id] ?? now;
          final deltaMs = now.difference(lastTime).inMilliseconds;
          if (deltaMs > 0) {
            final instantSpeed = deltaBytes * 1000.0 / deltaMs;
            final alpha = 0.3;
            final prevSmoothed = _smoothedSpeed[model.id] ?? 0.0;
            _smoothedSpeed[model.id] =
                alpha * instantSpeed + (1.0 - alpha) * prevSmoothed;
          }
          _lastUpdateTime[model.id] = now;

          final dlProgress = DownloadProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speedBytesPerSecond: _smoothedSpeed[model.id]!,
          );
          onProgress(dlProgress);
          controller.add(dlProgress);
        },
        onStatus: (status) {
          if (status == TaskStatus.paused) {
            final pausedProgress = DownloadProgress(
              bytesDownloaded: _lastBytes[model.id] ?? 0,
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
        // Do NOT cleanup — keep task in _activeTasks so resume can find it.
        // The controller is also kept alive so resume can re-drive progress.
        return DownloadProgress(
          bytesDownloaded: _lastBytes[model.id] ?? 0,
          totalBytes: model.sizeBytes,
          speedBytesPerSecond: 0,
          isPaused: true,
        );
      } else {
        await controller.close();
        _cleanup(model.id);
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
    _lastUpdateTime.clear();
    _lastBytes.clear();
    _smoothedSpeed.clear();
  }

  void _cleanup(String modelId) {
    _activeTasks.remove(modelId);
    _controllers.remove(modelId);
    _lastUpdateTime.remove(modelId);
    _lastBytes.remove(modelId);
    _smoothedSpeed.remove(modelId);
  }
}
