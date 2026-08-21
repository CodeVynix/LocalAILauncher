import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../models/model_info.dart';
import '../models/device_info.dart';
import '../services/download_service.dart';
import '../services/recommended_models.dart';

class ShelfServerService {
  HttpServer? _server;
  String? _wifiIp;
  final List<ModelInfo> Function() _getModels;
  final List<Map<String, dynamic>> Function() _getChatHistory;
  final Future<void> Function(String message) _onSendMessage;
  final Future<DeviceHardwareInfo> Function()? _getDeviceInfo;
  final List<ModelInfo> Function(int ramGb)? _getRecommendedModels;
  final Future<DownloadProgress> Function(
    ModelInfo model,
    Function(DownloadProgress) onProgress,
  )? _onDownloadModel;
  final Future<bool> Function(String path, String fileName)?
      _onImportGguf;
  final void Function(String modelId)? _onPauseDownload;
  final void Function(String modelId)? _onResumeDownload;
  final void Function(String modelId)? _onCancelDownload;

  ShelfServerService({
    required List<ModelInfo> Function() getModels,
    required List<Map<String, dynamic>> Function() getChatHistory,
    required Future<void> Function(String message) onSendMessage,
    Future<DeviceHardwareInfo> Function()? getDeviceInfo,
    List<ModelInfo> Function(int ramGb)? getRecommendedModels,
    Future<DownloadProgress> Function(
      ModelInfo model,
      Function(DownloadProgress) onProgress,
    )? onDownloadModel,
    Future<bool> Function(String path, String fileName)? onImportGguf,
    void Function(String modelId)? onPauseDownload,
    void Function(String modelId)? onResumeDownload,
    void Function(String modelId)? onCancelDownload,
  })  : _getModels = getModels,
        _getChatHistory = getChatHistory,
        _onSendMessage = onSendMessage,
        _getDeviceInfo = getDeviceInfo,
        _getRecommendedModels = getRecommendedModels,
        _onDownloadModel = onDownloadModel,
        _onImportGguf = onImportGguf,
        _onPauseDownload = onPauseDownload,
        _onResumeDownload = onResumeDownload,
        _onCancelDownload = onCancelDownload;

  Future<void> start(int port, {String? wifiIp}) async {
    _wifiIp = wifiIp;
    final router = Router();

    router.get('/', _handleIndex);
    router.get('/api/models', _handleModels);
    router.post('/api/chat', _handleChat);
    router.get('/api/chat/history', _handleChatHistory);

    // New endpoints
    router.get('/api/device-info', _handleDeviceInfo);
    router.get('/api/recommended-models', _handleRecommendedModels);
    router.post('/api/download-model', _handleDownloadModel);
    router.get('/api/download-progress/<modelId>', _handleDownloadProgress);
    router.post('/api/pause-download', _handlePauseDownload);
    router.post('/api/resume-download', _handleResumeDownload);
    router.post('/api/cancel-download', _handleCancelDownload);
    router.post('/api/import-gguf', _handleImportGguf);

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    // Health check: confirm the server is actually accepting connections
    // before returning to the caller, so the URL is only displayed after
    // the server is proven reachable.
    await _healthCheck(_server!.port);
  }

  Future<void> _healthCheck(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
    } catch (e) {
      // Server claimed to start but is not reachable — tear it down
      await _server?.close();
      _server = null;
      throw StateError(
          'Server started but is not accepting connections on port $port: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _wifiIp = null;
  }

  bool get isRunning => _server != null;

  String? get url {
    if (_server == null) return null;
    final port = _server!.port;
    if (_wifiIp != null && _wifiIp!.isNotEmpty) {
      return 'http://$_wifiIp:$port';
    }
    return 'http://127.0.0.1:$port';
  }

  // ── Existing endpoints ──

  shelf.Response _handleIndex(shelf.Request request) {
    return shelf.Response.ok(
      _webPageHtml,
      headers: {'content-type': 'text/html'},
    );
  }

  shelf.Response _handleModels(shelf.Request request) {
    final models = _getModels();
    return shelf.Response.ok(
      jsonEncode(models.map((m) => _modelToJson(m)).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleChat(shelf.Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final message = json['message'] as String? ?? '';

    if (message.isEmpty) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'Message is required'}),
          headers: {'content-type': 'application/json'});
    }

    await _onSendMessage(message);
    return shelf.Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'content-type': 'application/json'});
  }

  shelf.Response _handleChatHistory(shelf.Request request) {
    final history = _getChatHistory();
    return shelf.Response.ok(
      jsonEncode(history),
      headers: {'content-type': 'application/json'},
    );
  }

  // ── New endpoints ──

  Future<shelf.Response> _handleDeviceInfo(shelf.Request request) async {
    if (_getDeviceInfo == null) {
      return shelf.Response.ok(jsonEncode({'error': 'Not available'}),
          headers: {'content-type': 'application/json'});
    }
    try {
      final info = await _getDeviceInfo();
      return shelf.Response.ok(
        jsonEncode({
          'cpuModel': info.cpuModel,
          'roundedRamGb': info.roundedRamGb,
          'hardwareTier': info.hardwareTier,
          'cpuCores': info.cpuCores,
          'platform': info.platform,
          'osVersion': info.osVersion,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return shelf.Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<shelf.Response> _handleRecommendedModels(
      shelf.Request request) async {
    if (_getDeviceInfo == null || _getRecommendedModels == null) {
      return shelf.Response.ok(jsonEncode([]),
          headers: {'content-type': 'application/json'});
    }
    try {
      final info = await _getDeviceInfo();
      final models = _getRecommendedModels(info.roundedRamGb);
      return shelf.Response.ok(
        jsonEncode(models.map((m) => _modelToJson(m)).toList()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return shelf.Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: {'content-type': 'application/json'});
    }
  }

  // Track in-flight web downloads: modelId -> latest progress
  final Map<String, DownloadProgress> _webDownloadProgress = {};

  Future<shelf.Response> _handleDownloadModel(
      shelf.Request request) async {
    if (_onDownloadModel == null) {
      return shelf.Response.ok(
          jsonEncode({'error': 'Download not available'}),
          headers: {'content-type': 'application/json'});
    }
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modelId = json['modelId'] as String?;

    if (modelId == null || modelId.isEmpty) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'modelId is required'}),
          headers: {'content-type': 'application/json'});
    }

    // Search downloaded models first, then the full recommended catalog
    final downloadedModels = _getModels();
    ModelInfo? model;
    try {
      model = downloadedModels.firstWhere((m) => m.id == modelId);
    } catch (_) {
      // Not in downloaded list — search the full recommended catalog
      final catalogMatch =
          RecommendedModels.models.where((m) => m.id == modelId);
      if (catalogMatch.isNotEmpty) {
        model = catalogMatch.first;
      }
    }

    if (model == null) {
      return shelf.Response.notFound(
          jsonEncode({'error': 'Model not found: $modelId'}),
          headers: {'content-type': 'application/json'});
    }

    if (model.isDownloaded) {
      return shelf.Response.ok(
          jsonEncode({'status': 'already_downloaded'}),
          headers: {'content-type': 'application/json'});
    }

    // Start download in background, track progress
    _webDownloadProgress[modelId] = DownloadProgress(
      bytesDownloaded: 0,
      totalBytes: model.sizeBytes,
      speedBytesPerSecond: 0,
    );

    // Fire and forget — the web UI polls /api/download-progress/:modelId
    _onDownloadModel(model, (progress) {
      _webDownloadProgress[modelId] = progress;
    }).then((result) {
      _webDownloadProgress[modelId] = result;
    }).catchError((e) {
      _webDownloadProgress.remove(modelId);
    });

    return shelf.Response.ok(jsonEncode({'status': 'started'}),
        headers: {'content-type': 'application/json'});
  }

  shelf.Response _handleDownloadProgress(
      shelf.Request request, String modelId) {
    final progress = _webDownloadProgress[modelId];
    if (progress == null) {
      return shelf.Response.ok(
          jsonEncode({'status': 'not_found'}),
          headers: {'content-type': 'application/json'});
    }
    return shelf.Response.ok(
      jsonEncode({
        'bytesDownloaded': progress.bytesDownloaded,
        'totalBytes': progress.totalBytes,
        'progress': progress.progress,
        'speedBytesPerSecond': progress.speedBytesPerSecond,
        'speedDisplay': progress.speedDisplay,
        'display': progress.display,
        'isPaused': progress.isPaused,
        'isCancelled': progress.isCancelled,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<shelf.Response> _handlePauseDownload(
      shelf.Request request) async {
    if (_onPauseDownload == null) {
      return shelf.Response.ok(
          jsonEncode({'error': 'Pause not available'}),
          headers: {'content-type': 'application/json'});
    }
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modelId = json['modelId'] as String?;
    if (modelId == null || modelId.isEmpty) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'modelId is required'}),
          headers: {'content-type': 'application/json'});
    }
    _onPauseDownload(modelId);
    return shelf.Response.ok(jsonEncode({'status': 'paused'}),
        headers: {'content-type': 'application/json'});
  }

  Future<shelf.Response> _handleResumeDownload(
      shelf.Request request) async {
    if (_onResumeDownload == null) {
      return shelf.Response.ok(
          jsonEncode({'error': 'Resume not available'}),
          headers: {'content-type': 'application/json'});
    }
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modelId = json['modelId'] as String?;
    if (modelId == null || modelId.isEmpty) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'modelId is required'}),
          headers: {'content-type': 'application/json'});
    }
    _onResumeDownload(modelId);
    return shelf.Response.ok(jsonEncode({'status': 'resumed'}),
        headers: {'content-type': 'application/json'});
  }

  Future<shelf.Response> _handleCancelDownload(
      shelf.Request request) async {
    if (_onCancelDownload == null) {
      return shelf.Response.ok(
          jsonEncode({'error': 'Cancel not available'}),
          headers: {'content-type': 'application/json'});
    }
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modelId = json['modelId'] as String?;
    if (modelId == null || modelId.isEmpty) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'modelId is required'}),
          headers: {'content-type': 'application/json'});
    }
    _onCancelDownload(modelId);
    _webDownloadProgress.remove(modelId);
    return shelf.Response.ok(jsonEncode({'status': 'cancelled'}),
        headers: {'content-type': 'application/json'});
  }

  Future<shelf.Response> _handleImportGguf(
      shelf.Request request) async {
    if (_onImportGguf == null) {
      return shelf.Response.ok(jsonEncode({'error': 'Import not available'}),
          headers: {'content-type': 'application/json'});
    }

    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('multipart/form-data')) {
      return shelf.Response.badRequest(
          body: jsonEncode({'error': 'Expected multipart/form-data'}),
          headers: {'content-type': 'application/json'});
    }

    try {
      final boundary =
          contentType.split('boundary=').last.split(';').first.trim();

      final bytes = await request.read().fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      // Extract filename from Content-Disposition header
      final bodyStr = String.fromCharCodes(bytes);
      final fileNameMatch =
          RegExp(r'filename="([^"]+)"').firstMatch(bodyStr);
      if (fileNameMatch == null) {
        return shelf.Response.badRequest(
            body: jsonEncode({'error': 'No file provided'}),
            headers: {'content-type': 'application/json'});
      }
      final fileName = fileNameMatch.group(1)!;

      // Find the data region: after the first \r\n\r\n (end of headers)
      final headerEndBytes = [0x0D, 0x0A, 0x0D, 0x0A];
      int dataStart = -1;
      for (int i = 0; i < bytes.length - 3; i++) {
        if (bytes[i] == headerEndBytes[0] &&
            bytes[i + 1] == headerEndBytes[1] &&
            bytes[i + 2] == headerEndBytes[2] &&
            bytes[i + 3] == headerEndBytes[3]) {
          dataStart = i + 4;
          break;
        }
      }
      if (dataStart == -1) {
        return shelf.Response.badRequest(
            body: jsonEncode({'error': 'Invalid multipart data'}),
            headers: {'content-type': 'application/json'});
      }

      // Find closing boundary: "--<boundary>--"
      final closingBoundary = '--$boundary--';
      final closingBytes = closingBoundary.codeUnits;
      int dataEnd = bytes.length;
      for (int i = dataStart; i <= bytes.length - closingBytes.length; i++) {
        bool match = true;
        for (int j = 0; j < closingBytes.length; j++) {
          if (bytes[i + j] != closingBytes[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          dataEnd = i;
          break;
        }
      }

      // Strip trailing \r\n if present
      if (dataEnd > dataStart &&
          bytes[dataEnd - 2] == 0x0D &&
          bytes[dataEnd - 1] == 0x0A) {
        dataEnd -= 2;
      }

      final fileBytes = bytes.sublist(dataStart, dataEnd);

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(fileBytes);

      final success = await _onImportGguf(tempFile.path, fileName);
      await tempFile.delete();

      if (success) {
        return shelf.Response.ok(jsonEncode({'status': 'imported'}),
            headers: {'content-type': 'application/json'});
      } else {
        return shelf.Response.badRequest(
            body: 'Invalid GGUF file',
            headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      return shelf.Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: {'content-type': 'application/json'});
    }
  }

  // ── Helpers ──

  Map<String, dynamic> _modelToJson(ModelInfo m) => {
        'id': m.id,
        'name': m.name,
        'description': m.description,
        'size': m.sizeDisplay,
        'sizeBytes': m.sizeBytes,
        'paramCount': m.paramDisplay,
        'quantization': m.quantization,
        'aggressiveness': m.aggressiveness.name,
        'censorship': m.censorship.name,
        'isDownloaded': m.isDownloaded,
        'localPath': m.localPath,
      };

  // ── Web UI HTML/CSS/JS ──

  static final String _webPageHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Local AI Launcher</title>
  <style>
    :root {
      --md-primary: #D0BCFF;
      --md-on-primary: #381E72;
      --md-primary-container: #4F378B;
      --md-on-primary-container: #EADDFF;
      --md-secondary: #CCC2DC;
      --md-on-secondary: #332D41;
      --md-secondary-container: #4A4458;
      --md-on-secondary-container: #E8DEF8;
      --md-tertiary: #EFB8C8;
      --md-surface: #141218;
      --md-on-surface: #E6E0E9;
      --md-on-surface-variant: #CAC4D0;
      --md-surface-container-lowest: #0F0D13;
      --md-surface-container-low: #1D1B20;
      --md-surface-container: #211F26;
      --md-surface-container-high: #2B2930;
      --md-surface-container-highest: #36343B;
      --md-outline: #938F99;
      --md-outline-variant: #49454F;
      --md-error: #F2B8B5;
      --md-error-container: #8C1D18;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: var(--md-surface);
      color: var(--md-on-surface);
      min-height: 100vh;
    }

    /* ── Tabs ── */
    .tabs {
      display: flex;
      background: var(--md-surface-container);
      border-bottom: 1px solid var(--md-outline-variant);
    }
    .tab {
      flex: 1;
      padding: 14px 12px;
      text-align: center;
      cursor: pointer;
      transition: background 0.2s, color 0.2s;
      font-size: 14px;
      font-weight: 500;
      color: var(--md-on-surface-variant);
      border-bottom: 2px solid transparent;
    }
    .tab:hover { background: var(--md-surface-container-high); color: var(--md-on-surface); }
    .tab.active {
      color: var(--md-primary);
      border-bottom-color: var(--md-primary);
    }
    .tab-content { display: none; padding: 0; }
    .tab-content.active { display: block; }

    /* ── Chat ── */
    .chat-container { display: flex; flex-direction: column; height: calc(100vh - 52px); }
    .messages { flex: 1; overflow-y: auto; padding: 16px; }
    .message {
      margin: 4px 0; padding: 10px 16px; border-radius: 16px;
      max-width: 75%; line-height: 1.5; font-size: 14px;
      word-wrap: break-word;
    }
    .message.user {
      background: var(--md-primary); color: var(--md-on-primary);
      margin-left: auto; border-bottom-right-radius: 4px;
    }
    .message.assistant {
      background: var(--md-surface-container-highest); color: var(--md-on-surface);
      margin-right: auto; border-bottom-left-radius: 4px;
    }
    .empty-chat {
      flex: 1; display: flex; align-items: center; justify-content: center;
      color: var(--md-on-surface-variant); font-size: 15px;
    }
    .input-bar {
      display: flex; gap: 8px; padding: 12px 16px;
      background: var(--md-surface-container);
      border-top: 1px solid var(--md-outline-variant);
    }
    .input-bar input {
      flex: 1; padding: 12px 16px;
      border: 1px solid var(--md-outline); border-radius: 28px;
      background: var(--md-surface-container-low); color: var(--md-on-surface);
      font-size: 14px; outline: none; transition: border-color 0.2s;
    }
    .input-bar input:focus { border-color: var(--md-primary); }
    .input-bar input::placeholder { color: var(--md-on-surface-variant); }
    .send-btn {
      width: 48px; height: 48px; border-radius: 24px; border: none;
      background: var(--md-primary); color: var(--md-on-primary);
      cursor: pointer; display: flex; align-items: center; justify-content: center;
      transition: background 0.2s;
    }
    .send-btn:hover { background: #B69DF8; }
    .send-btn svg { width: 22px; height: 22px; fill: currentColor; }

    /* ── Error state (no model) ── */
    .error-state {
      flex: 1; display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      padding: 24px; text-align: center;
    }
    .error-state .error-icon {
      width: 64px; height: 64px; border-radius: 50%;
      background: var(--md-error-container); color: var(--md-error);
      display: flex; align-items: center; justify-content: center;
      margin-bottom: 16px; font-size: 32px;
    }
    .error-state .error-msg {
      font-size: 18px; color: var(--md-on-surface); margin-bottom: 24px;
      line-height: 1.4;
    }
    .error-state .error-btn {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 12px 24px; border-radius: 20px; border: none;
      background: var(--md-primary); color: var(--md-on-primary);
      font-size: 14px; font-weight: 600; cursor: pointer;
      transition: background 0.2s;
    }
    .error-state .error-btn:hover { background: #B69DF8; }
    .error-state .error-btn svg { width: 18px; height: 18px; fill: currentColor; }

    /* ── Download Tab ── */
    .dl-section { padding: 0; }
    .dl-tabs {
      display: flex; background: var(--md-surface-container);
      border-bottom: 1px solid var(--md-outline-variant);
    }
    .dl-tab {
      flex: 1; padding: 12px; text-align: center; cursor: pointer;
      font-size: 13px; font-weight: 500; color: var(--md-on-surface-variant);
      border-bottom: 2px solid transparent; transition: all 0.2s;
    }
    .dl-tab:hover { color: var(--md-on-surface); }
    .dl-tab.active { color: var(--md-primary); border-bottom-color: var(--md-primary); }
    .dl-tab-content { display: none; padding: 12px; }
    .dl-tab-content.active { display: block; }

    .device-bar {
      display: flex; align-items: center; gap: 10px;
      padding: 12px 16px; background: var(--md-surface-container);
      border-bottom: 1px solid var(--md-outline-variant);
      font-size: 13px; font-weight: 600; color: var(--md-on-surface);
    }
    .device-bar .icon { color: var(--md-on-surface-variant); }
    .model-card {
      background: var(--md-surface-container); padding: 16px; margin: 8px 12px;
      border-radius: 12px; border: 1px solid var(--md-outline-variant);
      transition: border-color 0.2s;
    }
    .model-card:hover { border-color: var(--md-primary); }
    .model-card h3 { font-size: 15px; margin-bottom: 6px; color: var(--md-on-surface); }
    .model-card .desc { font-size: 13px; color: var(--md-on-surface-variant); margin-bottom: 8px; }
    .model-card .chips { display: flex; gap: 6px; margin-bottom: 8px; flex-wrap: wrap; }
    .model-card .meta { font-size: 12px; color: var(--md-on-surface-variant); margin-bottom: 10px; opacity: 0.7; }
    .chip {
      padding: 3px 10px; border-radius: 12px;
      font-size: 11px; font-weight: 600; color: #fff;
    }
    .chip-aggressive { background: #EF6C00; }
    .chip-nonaggressive { background: #1565C0; }
    .chip-uncensored { background: #C62828; }
    .chip-censored { background: #2E7D32; }
    .chip-tier {
      padding: 2px 8px; border-radius: 10px;
      font-size: 11px; font-weight: 700; color: #fff;
    }
    .tier-limited { background: #EF6C00; }
    .tier-good { background: #1565C0; }
    .tier-excellent { background: #2E7D32; }

    .btn {
      padding: 10px 20px; border: none; border-radius: 20px;
      cursor: pointer; font-weight: 600; font-size: 13px;
      transition: background 0.2s; width: 100%;
    }
    .btn-download { background: var(--md-primary); color: var(--md-on-primary); }
    .btn-download:hover { background: #B69DF8; }
    .btn-download:disabled { background: var(--md-surface-container-high); color: var(--md-on-surface-variant); cursor: default; }
    .btn-downloaded { background: #2E7D32; color: #fff; cursor: default; }
    .badge-downloaded {
      display: inline-flex; align-items: center; gap: 4px;
      padding: 6px 14px; border-radius: 16px;
      background: #2E7D32; color: #fff;
      font-size: 12px; font-weight: 600;
    }
    .badge-downloaded svg { width: 14px; height: 14px; fill: currentColor; }

    .dl-controls {
      display: flex; gap: 8px; margin-top: 8px;
    }
    .dl-controls button {
      flex: 1; padding: 8px 12px; border: none; border-radius: 16px;
      cursor: pointer; font-weight: 600; font-size: 12px;
      transition: background 0.2s;
    }
    .btn-pause { background: var(--md-primary); color: var(--md-on-primary); }
    .btn-pause:hover { background: #B69DF8; }
    .btn-resume { background: var(--md-primary); color: var(--md-on-primary); }
    .btn-resume:hover { background: #B69DF8; }
    .btn-cancel { background: var(--md-error); color: #fff; }
    .btn-cancel:hover { background: #D32F2F; }

    .progress-bar {
      height: 6px; background: var(--md-surface-container-lowest);
      border-radius: 3px; overflow: hidden; margin: 8px 0;
    }
    .progress-fill { height: 100%; background: var(--md-primary); transition: width 0.3s; }
    .progress-info {
      display: flex; justify-content: space-between;
      font-size: 12px; color: var(--md-on-surface-variant);
    }

    /* ── Settings ── */
    .settings { padding: 16px; }
    .hw-section { margin-bottom: 20px; }
    .hw-section h3 {
      font-size: 17px; font-weight: 700; margin-bottom: 12px;
      color: var(--md-on-surface);
    }
    .hw-row {
      display: flex; align-items: center; gap: 10px;
      margin-bottom: 10px; font-size: 14px; color: var(--md-on-surface);
    }
    .hw-icon { width: 20px; text-align: center; color: var(--md-on-surface-variant); }
    .temp-slider { width: 100%; margin: 8px 0; accent-color: var(--md-primary); }
    .temp-labels {
      display: flex; justify-content: space-between;
      font-size: 12px; color: var(--md-on-surface-variant); opacity: 0.7;
    }
    .server-toggle {
      display: flex; align-items: center; justify-content: space-between;
      padding: 12px 0; color: var(--md-on-surface);
    }
    .url-box {
      margin-top: 10px; padding: 12px; border-radius: 12px;
      background: var(--md-surface-container-low);
      border: 1px solid var(--md-outline-variant);
      font-family: monospace; font-weight: 700; font-size: 14px;
      color: var(--md-primary);
    }

    /* ── Import ── */
    .import-zone {
      border: 2px dashed var(--md-outline-variant); border-radius: 12px;
      padding: 40px 20px; text-align: center; margin: 12px;
      cursor: pointer; transition: border-color 0.2s;
    }
    .import-zone:hover { border-color: var(--md-primary); }
    .import-zone input { display: none; }
    .import-zone .icon { font-size: 48px; color: var(--md-on-surface-variant); margin-bottom: 12px; }
    .import-zone .label { font-size: 15px; margin-bottom: 8px; color: var(--md-on-surface); }
    .import-zone .sublabel { font-size: 13px; color: var(--md-on-surface-variant); }

    .snackbar {
      position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
      padding: 12px 24px; border-radius: 12px; font-size: 14px; font-weight: 600;
      color: #fff; z-index: 100; animation: fadeIn 0.3s;
    }
    .snackbar-success { background: #2E7D32; }
    .snackbar-error { background: #C62828; }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateX(-50%) translateY(10px); }
      to   { opacity: 1; transform: translateX(-50%) translateY(0); }
    }
  </style>
</head>
<body>
  <div class="tabs">
    <div class="tab active" onclick="switchTab('chat')">Chat</div>
    <div class="tab" onclick="switchTab('download')">Download</div>
    <div class="tab" onclick="switchTab('settings')">Settings</div>
  </div>

  <!-- ── Chat Tab ── -->
  <div id="chat-tab" class="tab-content active">
    <div class="chat-container">
      <div id="chatErrorState" class="error-state" style="display:none">
        <div class="error-icon">&#9888;</div>
        <div class="error-msg">Error: No local model detected, download one.</div>
        <button class="error-btn" onclick="switchTab('download')">
          <svg viewBox="0 0 24 24"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
          Go to Download
        </button>
      </div>
      <div id="chatMessagesWrap">
        <div class="empty-chat" id="emptyChat">Start a conversation</div>
        <div class="messages" id="messages"></div>
      </div>
      <div class="input-bar" id="chatInputBar">
        <input type="text" id="chatInput" placeholder="Type a message..." onkeypress="if(event.key==='Enter')sendMessage()">
        <button class="send-btn" onclick="sendMessage()" aria-label="Send">
          <svg viewBox="0 0 24 24"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
        </button>
      </div>
    </div>
  </div>

  <!-- ── Download Tab ── -->
  <div id="download-tab" class="tab-content">
    <div class="dl-section">
      <div class="device-bar" id="deviceBar">
        <span class="icon">&#9432;</span>
        <span id="deviceInfo">Loading device info...</span>
      </div>
      <div class="dl-tabs">
        <div class="dl-tab active" onclick="switchDlTab('recommended')">Recommended</div>
        <div class="dl-tab" onclick="switchDlTab('import')">Import Custom</div>
      </div>
      <div id="recommended-tab" class="dl-tab-content active">
        <div id="modelList"></div>
      </div>
      <div id="import-tab" class="dl-tab-content">
        <div class="import-zone" onclick="document.getElementById('ggufInput').click()">
          <div class="icon">&#128194;</div>
          <div class="label">Import a custom GGUF model</div>
          <div class="sublabel">Select a .gguf file from your device.<br>File will be validated before import.</div>
          <input type="file" id="ggufInput" accept=".gguf" onchange="uploadGguf(this)">
        </div>
      </div>
    </div>
  </div>

  <!-- ── Settings Tab ── -->
  <div id="settings-tab" class="tab-content">
    <div class="settings">
      <div class="hw-section">
        <h3>Device Hardware</h3>
        <div class="hw-row"><span class="hw-icon">&#128187;</span><span id="hwCpu">Loading...</span></div>
        <div class="hw-row">
          <span class="hw-icon">&#128189;</span>
          <span id="hwRam">Loading...</span>
          <span id="hwTier"></span>
        </div>
        <div class="hw-row"><span class="hw-icon">&#128190;</span><span id="hwStorage">Loading...</span></div>
      </div>
      <div class="hw-section">
        <h3>Temperature</h3>
        <div id="tempValue" style="font-size:14px;color:var(--md-on-surface-variant);margin-bottom:4px">Current: 0.7</div>
        <input type="range" class="temp-slider" min="0" max="1.5" step="0.1" value="0.7"
          oninput="document.getElementById('tempValue').textContent='Current: '+parseFloat(this.value).toFixed(1)">
        <div class="temp-labels">
          <span>0.0 — Safe / Deterministic</span>
          <span>1.5 — Random / Creative</span>
        </div>
      </div>
      <div class="hw-section" id="serverInfoSection" style="display:none">
        <h3>Web Server</h3>
        <div class="url-box" id="serverUrl"></div>
      </div>
    </div>
  </div>

  <script>
    /* ── Model availability state ── */
    var _hasDownloadedModel = false;
    var _downloadTabRendered = false;

    /* ── Tab switching ── */
    function switchTab(name) {
      document.querySelectorAll('.tab').forEach(function(t) { t.classList.remove('active'); });
      document.querySelectorAll('.tab-content').forEach(function(t) { t.classList.remove('active'); });
      var idx = name === 'chat' ? 0 : (name === 'download' ? 1 : 2);
      document.querySelectorAll('.tab')[idx].classList.add('active');
      document.getElementById(name + '-tab').classList.add('active');
      if (name === 'download') {
        loadDeviceInfo();
        if (!_downloadTabRendered || Object.keys(activePolls).length === 0) {
          loadRecommendedModels();
          _downloadTabRendered = true;
        }
      }
      if (name === 'settings') loadDeviceInfo();
      if (name === 'chat') refreshChatState();
    }

    function switchDlTab(name) {
      document.querySelectorAll('.dl-tab').forEach(function(t) { t.classList.remove('active'); });
      document.querySelectorAll('.dl-tab-content').forEach(function(t) { t.classList.remove('active'); });
      var idx = name === 'recommended' ? 0 : 1;
      document.querySelectorAll('.dl-tab')[idx].classList.add('active');
      document.getElementById(name + '-tab').classList.add('active');
    }

    /* ── Snackbar ── */
    function showSnackbar(msg, type) {
      var el = document.createElement('div');
      el.className = 'snackbar snackbar-' + type;
      el.textContent = msg;
      document.body.appendChild(el);
      setTimeout(function() { el.remove(); }, 3000);
    }

    /* ── Device Info ── */
    async function loadDeviceInfo() {
      try {
        var res = await fetch('/api/device-info');
        var info = await res.json();
        if (info.error) return;
        document.getElementById('hwCpu').textContent = info.cpuModel || 'Unknown CPU';
        document.getElementById('hwRam').textContent = 'RAM: ' + info.roundedRamGb + 'GB';
        var tierEl = document.getElementById('hwTier');
        tierEl.innerHTML = '<span class="chip-tier tier-' + info.hardwareTier.toLowerCase() + '">' + info.hardwareTier + '</span>';
        document.getElementById('hwStorage').textContent = 'Platform: ' + info.platform + ' ' + info.osVersion;
        document.getElementById('deviceInfo').textContent =
          'Device: ' + info.roundedRamGb + 'GB RAM (' + info.hardwareTier + '), ' + info.cpuCores + ' CPU cores';
      } catch (e) { console.error('Failed to load device info', e); }
    }

    /* ── Chat state / model check ── */
    async function refreshChatState() {
      try {
        var res = await fetch('/api/models');
        var models = await res.json();
        _hasDownloadedModel = models.some(function(m) { return m.isDownloaded; });
        updateChatUI();
      } catch (e) {
        console.error('Failed to check models', e);
        _hasDownloadedModel = false;
        updateChatUI();
      }
    }

    function updateChatUI() {
      var errEl = document.getElementById('chatErrorState');
      var msgWrap = document.getElementById('chatMessagesWrap');
      var inputBar = document.getElementById('chatInputBar');
      if (_hasDownloadedModel) {
        errEl.style.display = 'none';
        msgWrap.style.display = '';
        inputBar.style.display = '';
      } else {
        errEl.style.display = '';
        msgWrap.style.display = 'none';
        inputBar.style.display = 'none';
      }
    }

    /* ── Recommended Models ── */
    var activePolls = {};
    var _savedDownloadHTML = '';
    async function loadRecommendedModels() {
      try {
        var res = await fetch('/api/recommended-models');
        var models = await res.json();
        var el = document.getElementById('modelList');
        if (!models.length) {
          el.innerHTML = '<p style="color:var(--md-on-surface-variant);padding:16px">No recommended models for your device.</p>';
          return;
        }
        _savedDownloadHTML = el.innerHTML;
        el.innerHTML = models.map(function(m) { return renderModelCard(m); }).join('');
      } catch (e) { console.error('Failed to load models', e); }
    }

    function renderModelCard(m) {
      var chips =
        '<span class="chip chip-' + m.aggressiveness + '">' +
          (m.aggressiveness === 'aggressive' ? 'Aggressive' : 'Non-aggressive') +
        '</span>' +
        '<span class="chip chip-' + m.censorship + '">' +
          (m.censorship === 'uncensored' ? 'Uncensored' : 'Censored') +
        '</span>';
      var meta = m.paramCount + ' params \u00B7 ' + m.size + ' \u00B7 ' + m.quantization;
      var btn = m.isDownloaded
        ? '<span class="badge-downloaded"><svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>Downloaded</span>'
        : '<button class="btn btn-download" onclick="startDownload(\'' + m.id + '\', this)">Download</button>';
      return '<div class="model-card" id="card-' + m.id + '">' +
        '<h3>' + m.name + '</h3>' +
        '<div class="chips">' + chips + '</div>' +
        '<div class="desc">' + m.description + '</div>' +
        '<div class="meta">' + meta + '</div>' +
        '<div id="progress-' + m.id + '"></div>' +
        btn +
        '</div>';
    }

    /* ── Download ── */
    async function startDownload(modelId, btnEl) {
      btnEl.disabled = true;
      btnEl.textContent = 'Starting...';
      try {
        var res = await fetch('/api/download-model', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ modelId: modelId })
        });
        var data = await res.json();
        if (data.status === 'already_downloaded') {
          btnEl.textContent = '';
          btnEl.outerHTML = '<span class="badge-downloaded"><svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>Downloaded</span>';
          return;
        }
        if (data.error) {
          btnEl.disabled = false;
          btnEl.textContent = 'Download';
          showSnackbar(data.error, 'error');
          return;
        }
        var progEl = document.getElementById('progress-' + modelId);
        progEl.innerHTML =
          '<div class="progress-bar"><div class="progress-fill" id="fill-' + modelId + '" style="width:0%"></div></div>' +
          '<div class="progress-info">' +
            '<span id="prog-text-' + modelId + '">0.0 MB / 0.00 GB</span>' +
            '<span id="prog-speed-' + modelId + '">0.0 MB/s</span>' +
          '</div>' +
          '<div class="dl-controls" id="controls-' + modelId + '">' +
            '<button class="btn-pause" id="pauseBtn-' + modelId + '" onclick="pauseDownload(\'' + modelId + '\')">Pause</button>' +
            '<button class="btn-cancel" onclick="cancelDownload(\'' + modelId + '\')">Cancel</button>' +
          '</div>';
        btnEl.textContent = 'Downloading...';
        btnEl.disabled = true;
        pollProgress(modelId, btnEl);
      } catch (e) {
        btnEl.disabled = false;
        btnEl.textContent = 'Download';
        showSnackbar('Download failed: ' + (e.message || e), 'error');
      }
    }

    function pollProgress(modelId, btnEl) {
      if (activePolls[modelId]) return;
      activePolls[modelId] = setInterval(async function() {
        try {
          var res = await fetch('/api/download-progress/' + modelId);
          var p = await res.json();
          if (p.status === 'not_found') { stopPoll(modelId); return; }
          var fill = document.getElementById('fill-' + modelId);
          var txt = document.getElementById('prog-text-' + modelId);
          var spd = document.getElementById('prog-speed-' + modelId);
          var ctrl = document.getElementById('controls-' + modelId);
          if (fill) fill.style.width = (p.progress * 100).toFixed(1) + '%';
          if (txt) txt.textContent = p.display;
          if (spd) spd.textContent = p.speedDisplay;
          if (ctrl) {
            var pauseBtn = document.getElementById('pauseBtn-' + modelId);
            if (p.isPaused) {
              ctrl.innerHTML =
                '<button class="btn-resume" onclick="resumeDownload(\'' + modelId + '\')">Resume</button>' +
                '<button class="btn-cancel" onclick="cancelDownload(\'' + modelId + '\')">Cancel</button>';
            } else {
              ctrl.innerHTML =
                '<button class="btn-pause" id="pauseBtn-' + modelId + '" onclick="pauseDownload(\'' + modelId + '\')">Pause</button>' +
                '<button class="btn-cancel" onclick="cancelDownload(\'' + modelId + '\')">Cancel</button>';
            }
          }
          if (p.isCancelled) {
            stopPoll(modelId);
            var card = document.getElementById('card-' + modelId);
            if (card) {
              var progEl = document.getElementById('progress-' + modelId);
              if (progEl) progEl.innerHTML = '';
              var btnArea = card.querySelector('.btn-cancel, .badge-downloaded');
              if (btnArea && btnArea.parentElement) {
                btnArea.outerHTML = '<button class="btn btn-download" onclick="startDownload(\'' + modelId + '\', this)">Download</button>';
              }
            }
          }
          if (!p.isPaused && p.progress >= 1.0) {
            stopPoll(modelId);
            var card = document.getElementById('card-' + modelId);
            if (card) {
              var progEl = document.getElementById('progress-' + modelId);
              if (progEl) progEl.innerHTML = '';
              var dlBtn = card.querySelector('.btn-download, .btn-downloaded');
              if (dlBtn) dlBtn.outerHTML = '<span class="badge-downloaded"><svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>Downloaded</span>';
            }
            showSnackbar(modelId.replace(/-/g, ' ') + ' is ready to use', 'success');
          }
        } catch (e) { stopPoll(modelId); }
      }, 500);
    }

    function stopPoll(modelId) {
      if (activePolls[modelId]) {
        clearInterval(activePolls[modelId]);
        delete activePolls[modelId];
      }
    }

    /* ── Download controls ── */
    async function pauseDownload(modelId) {
      try {
        await fetch('/api/pause-download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ modelId: modelId })
        });
      } catch (e) { console.error('Pause failed', e); }
    }

    async function resumeDownload(modelId) {
      try {
        await fetch('/api/resume-download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ modelId: modelId })
        });
      } catch (e) { console.error('Resume failed', e); }
    }

    async function cancelDownload(modelId) {
      try {
        await fetch('/api/cancel-download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ modelId: modelId })
        });
      } catch (e) { console.error('Cancel failed', e); }
    }

    /* ── GGUF Import ── */
    async function uploadGguf(input) {
      var file = input.files[0];
      if (!file) return;
      var formData = new FormData();
      formData.append('file', file);
      try {
        showSnackbar('Validating and importing ' + file.name + '...', 'success');
        var res = await fetch('/api/import-gguf', { method: 'POST', body: formData });
        var data = await res.json();
        if (data.status === 'imported') {
          showSnackbar('Model imported successfully', 'success');
          loadRecommendedModels();
        } else {
          showSnackbar(data.error || 'Import failed', 'error');
        }
      } catch (e) {
        showSnackbar('Import failed: ' + e.message, 'error');
      }
      input.value = '';
    }

    /* ── Chat ── */
    async function sendMessage() {
      var input = document.getElementById('chatInput');
      var msg = input.value.trim();
      if (!msg) return;
      appendMessage('user', msg);
      input.value = '';
      var thinking = appendMessage('assistant', 'Thinking...');
      try {
        await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: msg })
        });
      } catch (e) { /* server handles it */ }
      setTimeout(loadHistory, 500);
    }

    function appendMessage(role, content) {
      var div = document.createElement('div');
      div.className = 'message ' + role;
      div.textContent = content;
      var container = document.getElementById('messages');
      container.appendChild(div);
      div.scrollIntoView({ behavior: 'smooth' });
      return div;
    }

    async function loadHistory() {
      try {
        var res = await fetch('/api/chat/history');
        var history = await res.json();
        var el = document.getElementById('messages');
        el.innerHTML = '';
        if (history.length === 0) {
          document.getElementById('emptyChat').style.display = '';
        } else {
          document.getElementById('emptyChat').style.display = 'none';
          history.forEach(function(m) { appendMessage(m.role, m.content); });
        }
      } catch (e) { console.error('Failed to load history', e); }
    }

    /* ── Init ── */
    refreshChatState();
    loadHistory();
  </script>
</body>
</html>
''';
}
