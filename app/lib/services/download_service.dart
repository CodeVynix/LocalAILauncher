import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/model_info.dart';

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
  http.Client? _currentClient;
  bool _isPaused = false;
  bool _isCancelled = false;
  final Map<String, StreamController<DownloadProgress>> _controllers = {};

  StreamController<DownloadProgress>? getController(String modelId) {
    return _controllers[modelId];
  }

  Future<DownloadProgress> downloadModel(
    ModelInfo model,
    Function(DownloadProgress) onProgress,
  ) async {
    final controller = StreamController<DownloadProgress>.broadcast();
    _controllers[model.id] = controller;
    _currentClient = http.Client();
    _isPaused = false;
    _isCancelled = false;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(appDir.path, 'models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final filePath = p.join(modelsDir.path, model.fileName);
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(model.downloadUrl));
      final response = await _currentClient!.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? model.sizeBytes;
      int bytesDownloaded = 0;
      int speedBytes = 0;
      final stopwatch = Stopwatch()..start();
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        if (_isCancelled) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return DownloadProgress(
            bytesDownloaded: 0,
            totalBytes: totalBytes,
            speedBytesPerSecond: 0,
            isCancelled: true,
          );
        }

        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isCancelled) {
            await sink.close();
            if (await file.exists()) await file.delete();
            return DownloadProgress(
              bytesDownloaded: 0,
              totalBytes: totalBytes,
              speedBytesPerSecond: 0,
              isCancelled: true,
            );
          }
        }

        sink.add(chunk);
        bytesDownloaded += chunk.length;
        speedBytes += chunk.length;

        if (stopwatch.elapsedMilliseconds >= 1000) {
          final speed = speedBytes * 1000 / stopwatch.elapsedMilliseconds;
          final progress = DownloadProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
          );
          onProgress(progress);
          controller.add(progress);
          speedBytes = 0;
          stopwatch.reset();
          stopwatch.start();
        }
      }

      await sink.close();

      final finalProgress = DownloadProgress(
        bytesDownloaded: bytesDownloaded,
        totalBytes: totalBytes,
        speedBytesPerSecond: 0,
      );
      onProgress(finalProgress);
      controller.add(finalProgress);
      await controller.close();
      _controllers.remove(model.id);

      return finalProgress;
    } catch (e) {
      rethrow;
    } finally {
      _currentClient?.close();
    }
  }

  void pauseDownload() {
    _isPaused = true;
  }

  void resumeDownload() {
    _isPaused = false;
  }

  void cancelDownload() {
    _isCancelled = true;
    _isPaused = false;
    _currentClient?.close();
  }
}
