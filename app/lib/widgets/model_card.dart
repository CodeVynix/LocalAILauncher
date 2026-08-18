import 'package:flutter/material.dart';
import '../models/model_info.dart';
import '../services/download_service.dart';
import 'download_progress.dart';

class ModelCard extends StatelessWidget {
  final ModelInfo model;
  final bool isDownloading;
  final DownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const ModelCard({
    super.key,
    required this.model,
    this.isDownloading = false,
    this.progress,
    required this.onDownload,
    required this.onCancel,
    this.onPause,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: model.aggressiveness == ModelAggressiveness.aggressive
                        ? Colors.orange
                        : Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.aggressiveness == ModelAggressiveness.aggressive
                        ? 'Aggressive'
                        : 'Non-aggressive',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: model.censorship == ModelCensorship.uncensored
                        ? Colors.red
                        : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.censorship == ModelCensorship.uncensored
                        ? 'Uncensored'
                        : 'Censored',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              model.description,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                _buildChip('${model.paramDisplay} params'),
                _buildChip(model.sizeDisplay),
                _buildChip(model.quantization),
              ],
            ),
            const SizedBox(height: 12),
            if (isDownloading && progress != null)
              DownloadProgressWidget(
                progress: progress!,
                onPause: onPause,
                onResume: onResume,
                onCancel: onCancel,
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: model.isDownloaded ? null : onDownload,
                  child: Text(
                    model.isDownloaded ? 'Downloaded' : 'Download',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
