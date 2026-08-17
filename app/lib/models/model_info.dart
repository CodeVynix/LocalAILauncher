enum ModelAggressiveness { aggressive, nonAggressive }
enum ModelCensorship { censored, uncensored }

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final int paramCount;
  final String quantization;
  final ModelAggressiveness aggressiveness;
  final ModelCensorship censorship;
  final int minRamGb;
  final bool isDownloaded;
  final String? localPath;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.paramCount,
    required this.quantization,
    required this.aggressiveness,
    required this.censorship,
    required this.minRamGb,
    this.isDownloaded = false,
    this.localPath,
  });

  String get sizeDisplay {
    if (sizeBytes >= 1073741824) {
      return '${(sizeBytes / 1073741824).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / 1048576).toStringAsFixed(0)} MB';
  }

  String get paramDisplay {
    if (paramCount >= 1000000000) {
      return '${(paramCount / 1000000000).toStringAsFixed(1)}B';
    }
    return '${(paramCount / 1000000).toStringAsFixed(0)}M';
  }

  ModelInfo copyWith({
    bool? isDownloaded,
    String? localPath,
  }) {
    return ModelInfo(
      id: id,
      name: name,
      description: description,
      fileName: fileName,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
      paramCount: paramCount,
      quantization: quantization,
      aggressiveness: aggressiveness,
      censorship: censorship,
      minRamGb: minRamGb,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localPath: localPath ?? this.localPath,
    );
  }
}
