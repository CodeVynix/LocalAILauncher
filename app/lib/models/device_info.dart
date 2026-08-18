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

  int get roundedRamGb => _roundToRamTier(totalRamGb);

  String get hardwareTier {
    final gb = roundedRamGb;
    if (gb < 6) return 'Limited';
    if (gb < 12) return 'Good';
    return 'Excellent';
  }

  bool get isHighEnd => roundedRamGb >= 8 && cpuCores >= 6;
  bool get isMidRange => roundedRamGb >= 4 && cpuCores >= 4;
  bool get isLowEnd => roundedRamGb < 4 || cpuCores < 4;

  static int _roundToRamTier(int ramGb) {
    const tiers = [4, 6, 8, 12, 16, 32];
    for (final tier in tiers) {
      if (ramGb <= tier) return tier;
    }
    return 32;
  }
}
