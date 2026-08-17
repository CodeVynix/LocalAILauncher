import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/device_info.dart';

class DeviceService {
  static Future<DeviceHardwareInfo> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return DeviceHardwareInfo(
        totalRamBytes: androidInfo.physicalRamSize,
        cpuCores: Platform.numberOfProcessors,
        cpuModel: androidInfo.model,
        platform: 'android',
        osVersion: androidInfo.version.release,
      );
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return DeviceHardwareInfo(
        totalRamBytes: 0,
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
}
