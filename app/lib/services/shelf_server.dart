import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../models/model_info.dart';

class ShelfServerService {
  HttpServer? _server;
  String? _wifiIp;
  final List<ModelInfo> Function() _getModels;
  final List<Map<String, dynamic>> Function() _getChatHistory;
  final Future<void> Function(String message) _onSendMessage;

  ShelfServerService({
    required List<ModelInfo> Function() getModels,
    required List<Map<String, dynamic>> Function() getChatHistory,
    required Future<void> Function(String message) onSendMessage,
  })  : _getModels = getModels,
        _getChatHistory = getChatHistory,
        _onSendMessage = onSendMessage;

  Future<void> start(int port, {String? wifiIp}) async {
    _wifiIp = wifiIp;
    final router = Router();

    router.get('/', _handleIndex);
    router.get('/api/models', _handleModels);
    router.post('/api/chat', _handleChat);
    router.get('/api/chat/history', _handleChatHistory);

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
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
    return null;
  }

  shelf.Response _handleIndex(shelf.Request request) {
    return shelf.Response.ok(
      _webPageHtml,
      headers: {'content-type': 'text/html'},
    );
  }

  shelf.Response _handleModels(shelf.Request request) {
    final models = _getModels();
    return shelf.Response.ok(
      jsonEncode(models.map((m) => {
            'id': m.id,
            'name': m.name,
            'description': m.description,
            'size': m.sizeDisplay,
            'paramCount': m.paramDisplay,
            'quantization': m.quantization,
            'isDownloaded': m.isDownloaded,
            'localPath': m.localPath,
          }).toList()),
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

  static final String _webPageHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Local AI Launcher</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #1a1a2e; color: #eee; }
    .tabs { display: flex; background: #16213e; border-bottom: 2px solid #0f3460; }
    .tab { flex: 1; padding: 12px; text-align: center; cursor: pointer; transition: background 0.2s; }
    .tab:hover { background: #0f3460; }
    .tab.active { background: #0f3460; border-bottom: 2px solid #e94560; }
    .tab-content { display: none; padding: 16px; }
    .tab-content.active { display: block; }
    .chat-container { display: flex; flex-direction: column; height: calc(100vh - 120px); }
    .messages { flex: 1; overflow-y: auto; padding: 16px; }
    .message { margin: 8px 0; padding: 12px; border-radius: 12px; max-width: 80%; }
    .message.user { background: #0f3460; margin-left: auto; }
    .message.assistant { background: #16213e; margin-right: auto; }
    .input-bar { display: flex; gap: 8px; padding: 16px; }
    .input-bar input { flex: 1; padding: 12px; border: 1px solid #0f3460; border-radius: 8px; background: #16213e; color: #eee; }
    .input-bar button { padding: 12px 24px; background: #e94560; color: white; border: none; border-radius: 8px; cursor: pointer; }
    .model-card { background: #16213e; padding: 16px; margin: 8px 0; border-radius: 12px; border: 1px solid #0f3460; }
    .model-card h3 { margin-bottom: 8px; }
    .model-card .meta { font-size: 0.85em; color: #aaa; margin-bottom: 12px; }
    .settings-section { margin: 16px 0; }
    .settings-section label { display: block; margin-bottom: 8px; }
    .settings-section input[type="range"] { width: 100%; }
    .error-banner { background: #e94560; color: white; padding: 16px; border-radius: 8px; margin: 16px; text-align: center; }
  </style>
</head>
<body>
  <div class="tabs">
    <div class="tab active" onclick="switchTab('chat')">Chat</div>
    <div class="tab" onclick="switchTab('download')">Download</div>
    <div class="tab" onclick="switchTab('settings')">Settings</div>
  </div>

  <div id="chat-tab" class="tab-content active">
    <div class="chat-container">
      <div class="messages" id="messages"></div>
      <div class="input-bar">
        <input type="text" id="chatInput" placeholder="Type a message..." onkeypress="if(event.key==='Enter')sendMessage()">
        <button onclick="sendMessage()">Send</button>
      </div>
    </div>
  </div>

  <div id="download-tab" class="tab-content">
    <h2>Available Models</h2>
    <div id="modelList"></div>
  </div>

  <div id="settings-tab" class="tab-content">
    <div class="settings-section">
      <label>Temperature: <span id="tempValue">0.7</span></label>
      <input type="range" min="0" max="1.5" step="0.1" value="0.7" oninput="document.getElementById('tempValue').textContent=this.value">
      <p style="font-size:0.8em;color:#aaa;margin-top:4px">Low = safe/deterministic, High = random/creative</p>
    </div>
  </div>

  <script>
    function switchTab(name) {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
      var idx = name==='chat' ? 1 : (name==='download' ? 2 : 3);
      document.querySelector('.tab:nth-child(' + idx + ')').classList.add('active');
      document.getElementById(name+'-tab').classList.add('active');
      if(name==='download') loadModels();
    }

    async function loadModels() {
      const res = await fetch('/api/models');
      const models = await res.json();
      const el = document.getElementById('modelList');
      if(models.length===0) { el.innerHTML='<p style="color:#aaa">No models available. Use the app to download models.</p>'; return; }
      el.innerHTML = models.map(m => '<div class="model-card"><h3>'+m.name+'</h3><div class="meta">'+m.paramCount+' | '+m.size+' | '+m.quantization+'</div></div>').join('');
    }

    async function sendMessage() {
      const input = document.getElementById('chatInput');
      const msg = input.value.trim();
      if(!msg) return;
      appendMessage('user', msg);
      input.value = '';
      appendMessage('assistant', 'Thinking...');
      await fetch('/api/chat', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({message:msg})});
      setTimeout(loadHistory, 500);
    }

    function appendMessage(role, content) {
      const div = document.createElement('div');
      div.className = 'message ' + role;
      div.textContent = content;
      document.getElementById('messages').appendChild(div);
      div.scrollIntoView({behavior:'smooth'});
    }

    async function loadHistory() {
      const res = await fetch('/api/chat/history');
      const history = await res.json();
      const el = document.getElementById('messages');
      el.innerHTML = '';
      history.forEach(m => appendMessage(m.role, m.content));
    }

    loadHistory();
  </script>
</body>
</html>
''';
}
