class DeviceHardwareInfo {
  final int totalRamBytes;
  final int cpuCores;
  final String cpuModel;
  final String platform;
  final String osVersion;

  const DeviceHardwareInfo({
    required this.totalRamBytes,
    required this.cpuCores,
    required this.cpuModel,
    required this.platform,
    required this.osVersion,
  });

  int get totalRamGb => (totalRamBytes ~/ 1073741824);

  bool get isHighEnd => totalRamGb >= 8 && cpuCores >= 6;
  bool get isMidRange => totalRamGb >= 4 && cpuCores >= 4;
  bool get isLowEnd => totalRamGb < 4 || cpuCores < 4;
}
