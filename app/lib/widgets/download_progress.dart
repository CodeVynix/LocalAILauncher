import 'package:flutter/material.dart';
import '../services/download_service.dart';

class DownloadProgressWidget extends StatelessWidget {
  final DownloadProgress progress;
  final VoidCallback onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const DownloadProgressWidget({
    super.key,
    required this.progress,
    required this.onCancel,
    this.onPause,
    this.onResume,
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
              progress.isPaused
                  ? 'Paused'
                  : progress.isCancelled
                      ? 'Cancelled'
                      : progress.speedDisplay,
              style: TextStyle(
                fontSize: 12,
                color: progress.isPaused
                    ? Colors.orange
                    : progress.isCancelled
                        ? Colors.red
                        : Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!progress.isPaused && onPause != null)
              TextButton(
                onPressed: onPause,
                child: const Text(
                  'Pause',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            if (progress.isPaused && onResume != null)
              TextButton(
                onPressed: onResume,
                child: const Text(
                  'Resume',
                  style: TextStyle(color: Colors.green),
                ),
              ),
            TextButton(
              onPressed: onCancel,
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
