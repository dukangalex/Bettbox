/// Runtime config changes for the system options. The saved subscription
/// is not touched. Automatic groups lose DIRECT so a dead node cannot
/// silently fall through. Plain DNS is replaced with encrypted resolvers
/// only when the profile is not already using encrypted DNS.
const explicitChainGroup = '链式落地';

bool dnsServerEncrypted(String server) {
  final value = server.trim().toLowerCase();
  return value.startsWith('https://') ||
      value.startsWith('tls://') ||
      value.startsWith('quic://');
}

void hardenLeakDns(Map<String, dynamic> raw) {
  raw['ipv6'] = false;
  final current = raw['dns'];
  final dns = current is Map
      ? Map<String, dynamic>.from(current)
      : <String, dynamic>{};
  dns['enable'] = true;
  dns['ipv6'] = false;
  final mode = dns['enhanced-mode']?.toString() ?? '';
  if (mode.isEmpty) dns['enhanced-mode'] = 'fake-ip';

  final nameserver = dns['nameserver'];
  final encrypted =
      nameserver is List &&
      nameserver.any((item) => dnsServerEncrypted(item.toString()));
  if (!encrypted) {
    dns['nameserver'] = [
      'https://1.1.1.1/dns-query',
      'https://8.8.8.8/dns-query',
    ];
  }
  final fallback = dns['fallback'];
  if (fallback is! List || fallback.isEmpty) {
    dns['fallback'] = ['tls://1.1.1.1', 'tls://8.8.8.8'];
    dns['fallback-filter'] = {
      'geoip': true,
      'geoip-code': 'CN',
      'ipcidr': ['240.0.0.0/4'],
    };
  }
  if (dns['default-nameserver'] is! List ||
      (dns['default-nameserver'] as List).isEmpty) {
    dns['default-nameserver'] = ['1.1.1.1', '8.8.8.8'];
  }
  if (dns['proxy-server-nameserver'] is! List ||
      (dns['proxy-server-nameserver'] as List).isEmpty) {
    dns['proxy-server-nameserver'] = ['1.1.1.1', '8.8.8.8'];
  }
  raw['dns'] = dns;

  final tun = raw['tun'];
  if (tun is Map) {
    final hijack = tun['dns-hijack'];
    if (hijack is! List || hijack.isEmpty) {
      tun['dns-hijack'] = ['any:53'];
    }
  }
}

void dropAutomaticDirect(Map<String, dynamic> raw) {
  final groups = raw['proxy-groups'];
  if (groups is! List) return;
  for (final group in groups) {
    if (group is! Map) continue;
    final type = group['type']?.toString();
    if (type != 'url-test' && type != 'fallback' && type != 'load-balance') {
      continue;
    }
    final proxies = group['proxies'];
    if (proxies is! List) continue;
    final kept = proxies.where((item) {
      final name = item.toString();
      return name != 'DIRECT' && name != 'REJECT' && name != 'REJECT-DROP';
    }).toList();
    if (kept.isNotEmpty && kept.length != proxies.length) {
      group['proxies'] = kept;
    }
  }
}

/// Inline landing nodes get dialer-proxy. Provider node names, which are
/// not in the file, become a relay group the selectors can choose.
bool applyChainPolicy(
  Map<String, dynamic> raw, {
  required String entry,
  required String landing,
}) {
  final entryName = entry.trim();
  final landingName = landing.trim();
  if (entryName.isEmpty || landingName.isEmpty || entryName == landingName) {
    return false;
  }
  final proxies = raw['proxies'];
  Map? target;
  var hasEntry = false;
  if (proxies is List) {
    for (final proxy in proxies) {
      if (proxy is! Map) continue;
      if (proxy['name']?.toString() == entryName) hasEntry = true;
      if (proxy['name']?.toString() == landingName) target = proxy;
    }
  }
  if (hasEntry && target != null) {
    target['dialer-proxy'] = entryName;
    return true;
  }

  final groups = raw['proxy-groups'];
  final list = groups is List ? groups : <dynamic>[];
  final exists = list.any(
    (group) => group is Map && group['name']?.toString() == explicitChainGroup,
  );
  if (!exists) {
    list.add({
      'name': explicitChainGroup,
      'type': 'relay',
      'proxies': [entryName, landingName],
    });
  }
  for (final group in list) {
    if (group is! Map || group['type']?.toString() != 'select') continue;
    if (group['name']?.toString() == explicitChainGroup) continue;
    final members = group['proxies'];
    if (members is! List || members.contains(explicitChainGroup)) continue;
    members.add(explicitChainGroup);
  }
  raw['proxy-groups'] = list;
  return true;
}
