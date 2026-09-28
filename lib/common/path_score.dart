/// Decides when a selected node should be replaced.
/// Never returns DIRECT or another group. A cooled-down node stays out
/// until its cooldown ends, then it can be tried again.
class PathSample {
  final String name;
  final String type;
  final int streak;
  final int? latencyMs;
  final DateTime? coolUntil;

  const PathSample({
    required this.name,
    required this.type,
    this.streak = 0,
    this.latencyMs,
    this.coolUntil,
  });
}

const reservedPathNames = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
  'GLOBAL',
};

const groupPathTypes = {
  'Selector',
  'URLTest',
  'Fallback',
  'LoadBalance',
  'Relay',
  'Compatible',
};

bool isLeafPath(String type) => !groupPathTypes.contains(type);

bool pathUnhealthy(int streak) => streak >= 2;

DateTime? pathCooldown(int streak, DateTime now) {
  if (streak >= 2) return now.add(const Duration(minutes: 3));
  return null;
}

/// Lowest recent latency first. Untested nodes come after nodes that
/// have succeeded. Cooled-down and non-leaf names are omitted.
List<String> rankAlternates({
  required String current,
  required List<PathSample> nodes,
  required DateTime now,
}) {
  final usable = <PathSample>[];
  for (final node in nodes) {
    if (node.name == current || reservedPathNames.contains(node.name)) {
      continue;
    }
    if (!isLeafPath(node.type)) continue;
    final cool = node.coolUntil;
    if (cool != null && cool.isAfter(now)) continue;
    usable.add(node);
  }
  usable.sort((a, b) {
    final aLat = a.latencyMs;
    final bLat = b.latencyMs;
    if (aLat == null && bLat != null) return 1;
    if (aLat != null && bLat == null) return -1;
    if (aLat != null && bLat != null && aLat != bLat) {
      return aLat.compareTo(bLat);
    }
    return a.streak.compareTo(b.streak);
  });
  return usable.map((node) => node.name).toList();
}
