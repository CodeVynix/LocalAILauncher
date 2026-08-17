import 'package:flutter/material.dart';
import '../services/download_service.dart';

class DownloadProgressWidget extends StatelessWidget {
  final DownloadProgress progress;
  final VoidCallback onCancel;

  const DownloadProgressWidget({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress.progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress.display,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              progress.speedDisplay,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }
}
