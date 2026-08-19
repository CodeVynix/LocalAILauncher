import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/model_info.dart';
import '../models/device_info.dart';
import '../services/device_service.dart';
import '../services/recommended_models.dart';
import '../services/download_service.dart';
import '../services/gguf_validator.dart';
import '../services/notification_service.dart';
import '../providers/model_provider.dart';
import '../widgets/model_card.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DeviceHardwareInfo? _deviceInfo;
  List<ModelInfo> _recommendedModels = [];
  final DownloadService _downloadService = DownloadService();
  String? _downloadingModelId;
  DownloadProgress? _currentProgress;
  bool _notificationPermissionRequested = false;
  bool _isStartingDownload = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final info = await DeviceService.getDeviceInfo();
    setState(() {
      _deviceInfo = info;
      _recommendedModels = RecommendedModels.getRecommendedForDevice(
        info.roundedRamGb,
      );
    });
  }

  Future<void> _downloadModel(ModelInfo model) async {
    if (_isStartingDownload || _downloadingModelId != null) return;

    if (!_notificationPermissionRequested) {
      _notificationPermissionRequested = true;
      NotificationService.requestNotificationPermission();
    }

    setState(() {
      _isStartingDownload = true;
      _downloadingModelId = model.id;
      _currentProgress = null;
    });

    try {
      final result = await _downloadService.downloadModel(
        model,
        (progress) {
          setState(() => _currentProgress = progress);
        },
      );

      if (result.bytesDownloaded > 0 &&
          !result.isCancelled &&
          !result.isPaused) {
        final modelsDir = await _getModelsDirectory();
        final localPath = '${modelsDir.path}/${model.fileName}';
        final downloadedFile = File(localPath);
        if (await downloadedFile.exists()) {
          await ref
              .read(modelListProvider.notifier)
              .addModel(model, localPath);
        }
      }

      if (!result.isPaused) {
        setState(() {
          _downloadingModelId = null;
          _currentProgress = null;
        });
      }
    } finally {
      setState(() => _isStartingDownload = false);
    }
  }

  void _pauseModelDownload() {
    if (_downloadingModelId != null) {
      _downloadService.pauseDownload(_downloadingModelId!);
    }
  }

  void _resumeModelDownload() {
    if (_downloadingModelId == null) return;
    _downloadService.resumeDownload(_downloadingModelId!);
  }

  void _cancelModelDownload() {
    _downloadService.cancelDownload();
    setState(() {
      _downloadingModelId = null;
      _currentProgress = null;
    });
  }

  Future<void> _importCustomModel() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );

    if (result != null) {
      final path = result.path;
      if (path == null) return;
      final validation = await GgufValidator.validateFile(path);

      if (!validation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid GGUF file: ${validation.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final fileName = path.split('/').last;
      final modelsDir = await _getModelsDirectory();
      final localPath = '${modelsDir.path}/$fileName';
      final srcFile = File(path);
      await srcFile.copy(localPath);

      final model = ModelInfo(
        id: fileName,
        name: fileName.replaceAll('.gguf', ''),
        description: 'Custom imported model',
        fileName: fileName,
        downloadUrl: '',
        sizeBytes: srcFile.lengthSync(),
        paramCount: 0,
        quantization: 'unknown',
        aggressiveness: ModelAggressiveness.nonAggressive,
        censorship: ModelCensorship.censored,
        minRamGb: 0,
      );

      await ref.read(modelListProvider.notifier).addModel(model, localPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model imported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Models'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Recommended'),
            Tab(text: 'Import Custom'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRecommendedTab(),
          _buildImportTab(),
        ],
      ),
    );
  }

  Widget _buildRecommendedTab() {
    if (_deviceInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Device: ${_deviceInfo!.roundedRamGb}GB RAM (${_deviceInfo!.hardwareTier}), ${_deviceInfo!.cpuCores} CPU cores',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _recommendedModels.isEmpty
              ? const Center(
                  child: Text(
                    'No recommended models for your device.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _recommendedModels.length,
                  itemBuilder: (context, index) {
                    final model = _recommendedModels[index];
                    final isDownloading = _downloadingModelId == model.id;
                    return ModelCard(
                      model: model,
                      isDownloading: isDownloading,
                      progress: isDownloading ? _currentProgress : null,
                      onDownload: () => _downloadModel(model),
                      onPause: isDownloading &&
                              _currentProgress != null &&
                              !_currentProgress!.isPaused
                          ? _pauseModelDownload
                          : null,
                      onResume: isDownloading &&
                              _currentProgress != null &&
                              _currentProgress!.isPaused
                          ? _resumeModelDownload
                          : null,
                      onCancel: _cancelModelDownload,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.file_upload_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Import a custom GGUF model',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a .gguf file from your device.\nFile will be validated before import.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importCustomModel,
            icon: const Icon(Icons.folder_open),
            label: const Text('Select GGUF File'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
