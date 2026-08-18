import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import '../models/device_info.dart';

class DeviceService {
  static const _channel = MethodChannel('com.localailauncher/device_info');

  static Future<DeviceHardwareInfo> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      // physicalRamSize is in megabytes (from ActivityManager.MemoryInfo.totalMem / 1MB)
      // Convert to bytes for consistency with DeviceHardwareInfo.totalRamBytes
      final ramBytes = androidInfo.physicalRamSize * 1048576;
      return DeviceHardwareInfo(
        totalRamBytes: ramBytes,
        cpuCores: Platform.numberOfProcessors,
        cpuModel: androidInfo.model,
        platform: 'android',
        osVersion: androidInfo.version.release,
      );
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      final ramBytes = await _getIosRamBytes();
      return DeviceHardwareInfo(
        totalRamBytes: ramBytes,
        cpuCores: Platform.numberOfProcessors,
        cpuModel: iosInfo.model,
        platform: 'ios',
        osVersion: iosInfo.systemVersion,
      );
    }

    return DeviceHardwareInfo(
      totalRamBytes: 0,
      cpuCores: Platform.numberOfProcessors,
      cpuModel: Platform.operatingSystem,
      platform: Platform.operatingSystem,
      osVersion: '',
    );
  }

  static Future<int> _getIosRamBytes() async {
    try {
      final result = await _channel.invokeMethod<int>('getPhysicalRamBytes');
      return result ?? 0;
    } on PlatformException {
      return 0;
    }
  }
}
