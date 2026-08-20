import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../models/model_info.dart';
import '../models/device_info.dart';
import '../services/download_service.dart';

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
  })  : _getModels = getModels,
        _getChatHistory = getChatHistory,
        _onSendMessage = onSendMessage,
        _getDeviceInfo = getDeviceInfo,
        _getRecommendedModels = getRecommendedModels,
        _onDownloadModel = onDownloadModel,
        _onImportGguf = onImportGguf;

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
      return shelf.Response.badRequest(body: 'Message is required');
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
      return shelf.Response.internalServerError(body: '$e');
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
      return shelf.Response.internalServerError(body: '$e');
    }
  }

  // Track in-flight web downloads: modelId -> latest progress
  final Map<String, DownloadProgress> _webDownloadProgress = {};

  Future<shelf.Response> _handleDownloadModel(
      shelf.Request request) async {
    if (_onDownloadModel == null) {
      return shelf.Response.ok(jsonEncode({'error': 'Download not available'}),
          headers: {'content-type': 'application/json'});
    }
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final modelId = json['modelId'] as String?;

    if (modelId == null || modelId.isEmpty) {
      return shelf.Response.badRequest(body: 'modelId is required');
    }

    // Find the model in the recommended or all models list
    final allModels = _getModels();
    ModelInfo? model;
    try {
      model = allModels.firstWhere((m) => m.id == modelId);
    } catch (_) {
      return shelf.Response.notFound('Model not found: $modelId');
    }

    if (model.isDownloaded) {
      return shelf.Response.ok(jsonEncode({'status': 'already_downloaded'}),
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

  Future<shelf.Response> _handleImportGguf(
      shelf.Request request) async {
    if (_onImportGguf == null) {
      return shelf.Response.ok(jsonEncode({'error': 'Import not available'}),
          headers: {'content-type': 'application/json'});
    }

    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('multipart/form-data')) {
      return shelf.Response.badRequest(body: 'Expected multipart/form-data');
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
        return shelf.Response.badRequest(body: 'No file provided');
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
        return shelf.Response.badRequest(body: 'Invalid multipart data');
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
      return shelf.Response.internalServerError(body: '$e');
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
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      min-height: 100vh;
    }
    .tabs {
      display: flex;
      background: #16213e;
      border-bottom: 2px solid #0f3460;
    }
    .tab {
      flex: 1;
      padding: 14px 12px;
      text-align: center;
      cursor: pointer;
      transition: background 0.2s, border-color 0.2s;
      font-size: 14px;
      font-weight: 500;
      color: #8892a4;
      border-bottom: 2px solid transparent;
    }
    .tab:hover { background: #0f3460; color: #ccc; }
    .tab.active {
      background: #0f3460;
      color: #e94560;
      border-bottom-color: #e94560;
    }
    .tab-content { display: none; padding: 0; }
    .tab-content.active { display: block; }

    /* ── Chat ── */
    .chat-container { display: flex; flex-direction: column; height: calc(100vh - 52px); }
    .messages { flex: 1; overflow-y: auto; padding: 16px; }
    .message { margin: 8px 0; padding: 12px 16px; border-radius: 16px; max-width: 80%; line-height: 1.5; }
    .message.user { background: #0f3460; margin-left: auto; border-bottom-right-radius: 4px; }
    .message.assistant { background: #16213e; margin-right: auto; border-bottom-left-radius: 4px; border: 1px solid #0f3460; }
    .input-bar { display: flex; gap: 8px; padding: 12px 16px; background: #16213e; border-top: 1px solid #0f3460; }
    .input-bar input {
      flex: 1; padding: 12px 16px;
      border: 1px solid #0f3460; border-radius: 24px;
      background: #1a1a2e; color: #e0e0e0; font-size: 14px;
    }
    .input-bar input:focus { outline: none; border-color: #e94560; }
    .input-bar button {
      padding: 12px 24px; background: #e94560; color: white;
      border: none; border-radius: 24px; cursor: pointer; font-weight: 600;
      transition: background 0.2s;
    }
    .input-bar button:hover { background: #d63851; }

    /* ── Download ── */
    .dl-section { padding: 0; }
    .dl-tabs { display: flex; background: #16213e; border-bottom: 1px solid #0f3460; }
    .dl-tab {
      flex: 1; padding: 12px; text-align: center; cursor: pointer;
      font-size: 13px; font-weight: 500; color: #8892a4;
      border-bottom: 2px solid transparent; transition: all 0.2s;
    }
    .dl-tab:hover { color: #ccc; }
    .dl-tab.active { color: #e94560; border-bottom-color: #e94560; }
    .dl-tab-content { display: none; padding: 12px; }
    .dl-tab-content.active { display: block; }

    .device-bar {
      display: flex; align-items: center; gap: 10px;
      padding: 12px 16px; background: #16213e; border-bottom: 1px solid #0f3460;
      font-size: 13px; font-weight: 600;
    }
    .model-card {
      background: #16213e; padding: 16px; margin: 8px 12px;
      border-radius: 12px; border: 1px solid #0f3460;
      transition: border-color 0.2s;
    }
    .model-card:hover { border-color: #e94560; }
    .model-card h3 { font-size: 15px; margin-bottom: 6px; color: #fff; }
    .model-card .desc { font-size: 13px; color: #8892a4; margin-bottom: 8px; }
    .model-card .chips { display: flex; gap: 6px; margin-bottom: 8px; flex-wrap: wrap; }
    .model-card .meta { font-size: 12px; color: #667; margin-bottom: 10px; }
    .chip {
      padding: 3px 10px; border-radius: 12px;
      font-size: 11px; font-weight: 600; color: #fff;
    }
    .chip-aggressive { background: #e67e22; }
    .chip-non-aggressive { background: #2980b9; }
    .chip-uncensored { background: #c0392b; }
    .chip-censored { background: #27ae60; }
    .chip-tier {
      padding: 2px 8px; border-radius: 10px;
      font-size: 11px; font-weight: 700; color: #fff;
    }
    .tier-limited { background: #e67e22; }
    .tier-good { background: #2980b9; }
    .tier-excellent { background: #27ae60; }

    .btn {
      padding: 8px 20px; border: none; border-radius: 8px;
      cursor: pointer; font-weight: 600; font-size: 13px;
      transition: background 0.2s; width: 100%;
    }
    .btn-download { background: #e94560; color: #fff; }
    .btn-download:hover { background: #d63851; }
    .btn-download:disabled { background: #555; color: #888; cursor: default; }
    .btn-downloaded { background: #27ae60; color: #fff; cursor: default; }
    .btn-cancel { background: transparent; color: #e94560; border: 1px solid #e94560; margin-top: 6px; }

    .progress-bar { height: 6px; background: #0f3460; border-radius: 3px; overflow: hidden; margin: 8px 0; }
    .progress-fill { height: 100%; background: #e94560; transition: width 0.3s; }
    .progress-info { display: flex; justify-content: space-between; font-size: 12px; color: #8892a4; }

    /* ── Settings ── */
    .settings { padding: 16px; }
    .hw-section { margin-bottom: 20px; }
    .hw-section h3 { font-size: 17px; font-weight: 700; margin-bottom: 12px; color: #fff; }
    .hw-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; font-size: 14px; }
    .hw-icon { width: 20px; text-align: center; color: #8892a4; }
    .temp-slider { width: 100%; margin: 8px 0; accent-color: #e94560; }
    .temp-labels { display: flex; justify-content: space-between; font-size: 12px; color: #667; }
    .server-toggle { display: flex; align-items: center; justify-content: space-between; padding: 12px 0; }
    .toggle-switch {
      width: 48px; height: 26px; border-radius: 13px;
      background: #555; position: relative; cursor: pointer; transition: background 0.3s;
    }
    .toggle-switch.on { background: #e94560; }
    .toggle-switch::after {
      content: ''; position: absolute; width: 22px; height: 22px;
      border-radius: 50%; background: #fff; top: 2px; left: 2px; transition: transform 0.3s;
    }
    .toggle-switch.on::after { transform: translateX(22px); }
    .url-box {
      margin-top: 10px; padding: 12px; border-radius: 8px;
      background: #0f3460; font-family: monospace; font-weight: 700; font-size: 14px;
    }

    /* ── Import ── */
    .import-zone {
      border: 2px dashed #0f3460; border-radius: 12px;
      padding: 40px 20px; text-align: center; margin: 12px;
      cursor: pointer; transition: border-color 0.2s;
    }
    .import-zone:hover { border-color: #e94560; }
    .import-zone input { display: none; }
    .import-zone .icon { font-size: 48px; color: #667; margin-bottom: 12px; }
    .import-zone .label { font-size: 15px; margin-bottom: 8px; }
    .import-zone .sublabel { font-size: 13px; color: #667; }
    .snackbar {
      position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
      padding: 12px 24px; border-radius: 8px; font-size: 14px; font-weight: 600;
      color: #fff; z-index: 100; animation: fadeIn 0.3s;
    }
    .snackbar-success { background: #27ae60; }
    .snackbar-error { background: #c0392b; }
    @keyframes fadeIn { from { opacity: 0; transform: translateX(-50%) translateY(10px); } to { opacity: 1; transform: translateX(-50%) translateY(0); } }
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
      <div class="messages" id="messages"></div>
      <div class="input-bar">
        <input type="text" id="chatInput" placeholder="Type a message..." onkeypress="if(event.key==='Enter')sendMessage()">
        <button onclick="sendMessage()">Send</button>
      </div>
    </div>
  </div>

  <!-- ── Download Tab ── -->
  <div id="download-tab" class="tab-content">
    <div class="dl-section">
      <div class="device-bar" id="deviceBar">
        <span>&#9432;</span>
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
        <div id="tempValue" style="font-size:14px;color:#8892a4;margin-bottom:4px">Current: 0.7</div>
        <input type="range" class="temp-slider" min="0" max="1.5" step="0.1" value="0.7"
          oninput="document.getElementById('tempValue').textContent='Current: '+parseFloat(this.value).toFixed(1)">
        <div class="temp-labels">
          <span>0.0 - Safe/Deterministic</span>
          <span>1.5 - Random/Creative</span>
        </div>
      </div>
      <div class="hw-section">
        <h3>Local Web Server</h3>
        <div class="server-toggle">
          <span>Serve the app as a webpage on your local network</span>
          <div class="toggle-switch on" onclick="this.classList.toggle('on')"></div>
        </div>
        <div class="url-box" id="serverUrl" style="display:none"></div>
      </div>
    </div>
  </div>

  <script>
    // ── Tab switching ──
    function switchTab(name) {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
      var idx = name==='chat' ? 0 : (name==='download' ? 1 : 2);
      document.querySelectorAll('.tab')[idx].classList.add('active');
      document.getElementById(name+'-tab').classList.add('active');
      if(name==='download') { loadDeviceInfo(); loadRecommendedModels(); }
      if(name==='settings') loadDeviceInfo();
    }

    function switchDlTab(name) {
      document.querySelectorAll('.dl-tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.dl-tab-content').forEach(t => t.classList.remove('active'));
      var idx = name==='recommended' ? 0 : 1;
      document.querySelectorAll('.dl-tab')[idx].classList.add('active');
      document.getElementById(name+'-tab').classList.add('active');
    }

    // ── Snackbar ──
    function showSnackbar(msg, type) {
      var el = document.createElement('div');
      el.className = 'snackbar snackbar-' + type;
      el.textContent = msg;
      document.body.appendChild(el);
      setTimeout(() => el.remove(), 3000);
    }

    // ── Device Info ──
    async function loadDeviceInfo() {
      try {
        var res = await fetch('/api/device-info');
        var info = await res.json();
        if(info.error) return;
        document.getElementById('hwCpu').textContent = info.cpuModel || 'Unknown CPU';
        document.getElementById('hwRam').textContent = 'RAM: ' + info.roundedRamGb + 'GB';
        var tierEl = document.getElementById('hwTier');
        tierEl.innerHTML = '<span class="chip-tier tier-' + info.hardwareTier.toLowerCase() + '">' + info.hardwareTier + '</span>';
        document.getElementById('hwStorage').textContent = 'Platform: ' + info.platform + ' ' + info.osVersion;
        document.getElementById('deviceInfo').textContent =
          'Device: ' + info.roundedRamGb + 'GB RAM (' + info.hardwareTier + '), ' + info.cpuCores + ' CPU cores';
      } catch(e) { console.error('Failed to load device info', e); }
    }

    // ── Recommended Models ──
    var activePolls = {};
    async function loadRecommendedModels() {
      try {
        var res = await fetch('/api/recommended-models');
        var models = await res.json();
        var el = document.getElementById('modelList');
        if(!models.length) { el.innerHTML='<p style="color:#667;padding:16px">No recommended models for your device.</p>'; return; }
        el.innerHTML = models.map(m => renderModelCard(m)).join('');
      } catch(e) { console.error('Failed to load models', e); }
    }

    function renderModelCard(m) {
      var chips = '<span class="chip chip-' + m.aggressiveness + '">' +
        (m.aggressiveness==='aggressive'?'Aggressive':'Non-aggressive') + '</span>' +
        '<span class="chip chip-' + m.censorship + '">' +
        (m.censorship==='uncensored'?'Uncensored':'Censored') + '</span>';
      var meta = m.paramCount + ' | ' + m.size + ' | ' + m.quantization;
      var btn = m.isDownloaded
        ? '<button class="btn btn-downloaded" disabled>Downloaded</button>'
        : '<button class="btn btn-download" onclick="startDownload(\'' + m.id + '\', this)">Download</button>';
      return '<div class="model-card" id="card-' + m.id + '">' +
        '<h3>' + m.name + '</h3>' +
        '<div class="chips">' + chips + '</div>' +
        '<div class="desc">' + m.description + '</div>' +
        '<div class="meta">' + meta + '</div>' +
        '<div id="progress-' + m.id + '"></div>' +
        btn + '</div>';
    }

    // ── Download ──
    async function startDownload(modelId, btnEl) {
      btnEl.disabled = true;
      btnEl.textContent = 'Starting...';
      try {
        var res = await fetch('/api/download-model', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({modelId: modelId})
        });
        var data = await res.json();
        if(data.status === 'already_downloaded') {
          btnEl.textContent = 'Downloaded';
          btnEl.className = 'btn btn-downloaded';
          return;
        }
        if(data.error) {
          btnEl.disabled = false;
          btnEl.textContent = 'Download';
          showSnackbar(data.error, 'error');
          return;
        }
        // Show progress bar and start polling
        var progEl = document.getElementById('progress-' + modelId);
        progEl.innerHTML = '<div class="progress-bar"><div class="progress-fill" id="fill-' + modelId + '" style="width:0%"></div></div>' +
          '<div class="progress-info"><span id="prog-text-' + modelId + '">0.0 MB / 0.00 GB</span>' +
          '<span id="prog-speed-' + modelId + '">0.0 MB/s</span></div>';
        btnEl.textContent = 'Downloading...';
        pollProgress(modelId, btnEl);
      } catch(e) {
        btnEl.disabled = false;
        btnEl.textContent = 'Download';
        showSnackbar('Download failed', 'error');
      }
    }

    function pollProgress(modelId, btnEl) {
      if(activePolls[modelId]) return;
      activePolls[modelId] = setInterval(async () => {
        try {
          var res = await fetch('/api/download-progress/' + modelId);
          var p = await res.json();
          if(p.status === 'not_found') { stopPoll(modelId); return; }
          var fill = document.getElementById('fill-' + modelId);
          var txt = document.getElementById('prog-text-' + modelId);
          var spd = document.getElementById('prog-speed-' + modelId);
          if(fill) fill.style.width = (p.progress * 100).toFixed(1) + '%';
          if(txt) txt.textContent = p.display;
          if(spd) spd.textContent = p.speedDisplay;
          if(p.isCancelled) { stopPoll(modelId); btnEl.textContent = 'Download'; btnEl.disabled = false; }
          if(!p.isPaused && p.progress >= 1.0) {
            stopPoll(modelId);
            btnEl.textContent = 'Downloaded';
            btnEl.className = 'btn btn-downloaded';
            var progEl = document.getElementById('progress-' + modelId);
            if(progEl) progEl.innerHTML = '';
            showSnackbar(modelId.replace(/-/g,' ') + ' is ready to use', 'success');
          }
        } catch(e) { stopPoll(modelId); }
      }, 500);
    }

    function stopPoll(modelId) {
      if(activePolls[modelId]) { clearInterval(activePolls[modelId]); delete activePolls[modelId]; }
    }

    // ── GGUF Import ──
    async function uploadGguf(input) {
      var file = input.files[0];
      if(!file) return;
      var formData = new FormData();
      formData.append('file', file);
      try {
        showSnackbar('Validating and importing ' + file.name + '...', 'success');
        var res = await fetch('/api/import-gguf', {method: 'POST', body: formData});
        var data = await res.json();
        if(data.status === 'imported') {
          showSnackbar('Model imported successfully', 'success');
          loadRecommendedModels();
        } else {
          showSnackbar(data.error || 'Import failed', 'error');
        }
      } catch(e) {
        showSnackbar('Import failed: ' + e.message, 'error');
      }
      input.value = '';
    }

    // ── Chat ──
    async function sendMessage() {
      var input = document.getElementById('chatInput');
      var msg = input.value.trim();
      if(!msg) return;
      appendMessage('user', msg);
      input.value = '';
      appendMessage('assistant', 'Thinking...');
      await fetch('/api/chat', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({message:msg})});
      setTimeout(loadHistory, 500);
    }

    function appendMessage(role, content) {
      var div = document.createElement('div');
      div.className = 'message ' + role;
      div.textContent = content;
      document.getElementById('messages').appendChild(div);
      div.scrollIntoView({behavior:'smooth'});
    }

    async function loadHistory() {
      try {
        var res = await fetch('/api/chat/history');
        var history = await res.json();
        var el = document.getElementById('messages');
        el.innerHTML = '';
        history.forEach(m => appendMessage(m.role, m.content));
      } catch(e) { console.error('Failed to load history', e); }
    }

    // ── Init ──
    loadHistory();
  </script>
</body>
</html>
''';
}
