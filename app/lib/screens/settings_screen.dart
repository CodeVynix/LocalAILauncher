import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../providers/settings_provider.dart';
import '../providers/model_provider.dart';
import '../services/shelf_server.dart';
import '../services/device_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  ShelfServerService? _serverService;
  String _hardwareTier = 'Unknown';
  int _roundedRamGb = 0;

  @override
  void initState() {
    super.initState();
    _serverService = ShelfServerService(
      getModels: () => ref.read(modelListProvider),
      getChatHistory: () => [],
      onSendMessage: (msg) async {},
    );
    _loadHardwareInfo();
  }

  Future<void> _loadHardwareInfo() async {
    final info = await DeviceService.getDeviceInfo();
    setState(() {
      _hardwareTier = info.hardwareTier;
      _roundedRamGb = info.roundedRamGb;
    });
  }

  void _toggleWebServer(bool enabled) async {
    if (enabled) {
      try {
        final wifiIp = await NetworkInfo().getWifiIP();
        if (wifiIp == null || wifiIp.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'WiFi not connected. The server will be accessible at 0.0.0.0:8080 only on this device.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        await _serverService!.start(8080, wifiIp: wifiIp);
        ref.read(settingsProvider.notifier).setWebServerEnabled(true);
        ref.read(settingsProvider.notifier).setWebServerUrl(
              _serverService!.url ?? '',
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start server: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      await _serverService!.stop();
      ref.read(settingsProvider.notifier).setWebServerEnabled(false);
      ref.read(settingsProvider.notifier).setWebServerUrl('');
    }
  }

  void _deleteModel(String modelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: const Text('Are you sure you want to delete this model?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(modelListProvider.notifier).removeModel(modelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final models = ref.watch(modelListProvider);
    final selectedModel = ref.watch(selectedModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildHardwareSection(),
          const Divider(),
          _buildTemperatureSection(settings),
          const Divider(),
          _buildWebServerSection(settings),
          const Divider(),
          _buildModelManagementSection(models, selectedModel),
        ],
      ),
    );
  }

  Widget _buildHardwareSection() {
    final Color tierColor;
    switch (_hardwareTier) {
      case 'Excellent':
        tierColor = Colors.green;
        break;
      case 'Good':
        tierColor = Colors.blue;
        break;
      default:
        tierColor = Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Device Hardware',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.memory, size: 20),
              const SizedBox(width: 8),
              Text(
                'RAM: ${_roundedRamGb}GB',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tierColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _hardwareTier,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended models are filtered based on your device capabilities.',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureSection(SettingsState settings) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Temperature',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Current: ${settings.temperature.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.grey),
          ),
          Slider(
            value: settings.temperature,
            min: 0.0,
            max: 1.5,
            divisions: 30,
            label: settings.temperature.toStringAsFixed(1),
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setTemperature(value);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0.0 - Safe/Deterministic',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
              Text(
                '1.5 - Random/Creative',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebServerSection(SettingsState settings) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Local Web Server',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Start local web server'),
            subtitle: const Text(
              'Serve the app as a webpage on your local network',
            ),
            value: settings.webServerEnabled,
            onChanged: _toggleWebServer,
          ),
          if (settings.webServerEnabled && settings.webServerUrl.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings.webServerUrl,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelManagementSection(
    List models,
    dynamic selectedModel,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Downloaded Models',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (models.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No models downloaded yet.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...models.map((model) => ListTile(
                  title: Text(model.name),
                  subtitle: Text(model.sizeDisplay),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedModel?.id == model.id)
                        const Icon(Icons.check_circle, color: Colors.green)
                      else
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () {
                            ref.read(selectedModelProvider.notifier).state =
                                model;
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => _deleteModel(model.id),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverService?.stop();
    super.dispose();
  }
}
