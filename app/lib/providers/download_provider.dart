import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download_service.dart';

final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService();
});
