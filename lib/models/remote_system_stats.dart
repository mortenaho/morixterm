class RemoteSystemStats {
  const RemoteSystemStats({
    required this.cpuUsedTicks,
    required this.cpuTotalTicks,
    required this.memTotalKb,
    required this.memAvailableKb,
    required this.diskTotalKb,
    required this.diskUsedKb,
    required this.diskMount,
  });

  final int cpuUsedTicks;
  final int cpuTotalTicks;
  final int memTotalKb;
  final int memAvailableKb;
  final int diskTotalKb;
  final int diskUsedKb;
  final String diskMount;

  int get memUsedKb => (memTotalKb - memAvailableKb).clamp(0, memTotalKb);

  int get memFreeKb => memAvailableKb.clamp(0, memTotalKb);

  int get diskFreeKb => (diskTotalKb - diskUsedKb).clamp(0, diskTotalKb);

  double? get memFraction =>
      memTotalKb <= 0 ? null : (memUsedKb / memTotalKb).clamp(0.0, 1.0);

  double? get diskFraction =>
      diskTotalKb <= 0 ? null : (diskUsedKb / diskTotalKb).clamp(0.0, 1.0);

  /// CPU percent from two consecutive samples of `/proc/stat` counters.
  double? cpuPercentSince(RemoteSystemStats? previous) {
    if (previous == null) return null;
    final usedDelta = cpuUsedTicks - previous.cpuUsedTicks;
    final totalDelta = cpuTotalTicks - previous.cpuTotalTicks;
    if (totalDelta <= 0 || usedDelta < 0) return null;
    return ((usedDelta / totalDelta) * 100).clamp(0.0, 100.0);
  }
}
