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
  final Map<String, double> _lastProgressRatio = {};

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
    _lastProgressRatio[model.id] = 0.0;

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
          _lastBytes[model.id] = bytesDownloaded;

          // Store the authoritative progress ratio from the package.
          // This is always fresh from background_downloader's own state
          // and is used as the source of truth at pause time.
          _lastProgressRatio[model.id] = progress;

          final lastTime = _lastUpdateTime[model.id] ?? now;
          final deltaMs = now.difference(lastTime).inMilliseconds;
          if (deltaMs > 0) {
            final instantSpeed =
                (bytesDownloaded - lastBytes) * 1000.0 / deltaMs;
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
            // Use the authoritative progress ratio from background_downloader
            // to compute the paused byte position. This avoids a race where
            // onStatus fires before the final onProgress tick has updated
            // _lastBytes, which would show 0.0 MB to the user.
            final totalBytes = model.sizeBytes;
            final ratio = _lastProgressRatio[model.id] ?? 0.0;
            final pausedBytes = (ratio * totalBytes).toInt();
            final pausedProgress = DownloadProgress(
              bytesDownloaded: pausedBytes,
              totalBytes: totalBytes,
              speedBytesPerSecond: 0,
              isPaused: true,
            );
            onProgress(pausedProgress);
            controller.add(pausedProgress);
          }
        },
      );

      final totalBytes = model.sizeBytes;

      if (result.status == TaskStatus.complete) {
        final finalProgress = DownloadProgress(
          bytesDownloaded: totalBytes,
          totalBytes: totalBytes,
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
          totalBytes: totalBytes,
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
        // Use the authoritative progress ratio for the paused byte position.
        final ratio = _lastProgressRatio[model.id] ?? 0.0;
        final pausedBytes = (ratio * totalBytes).toInt();
        return DownloadProgress(
          bytesDownloaded: pausedBytes,
          totalBytes: totalBytes,
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
    _lastProgressRatio.clear();
  }

  void _cleanup(String modelId) {
    _activeTasks.remove(modelId);
    _controllers.remove(modelId);
    _lastUpdateTime.remove(modelId);
    _lastBytes.remove(modelId);
    _smoothedSpeed.remove(modelId);
    _lastProgressRatio.remove(modelId);
  }
}
