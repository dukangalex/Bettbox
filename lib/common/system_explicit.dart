import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Runtime policy applied after the profile, the script, and the built-in
/// network overrides. Off by default so existing profiles keep their behavior.
class SystemExplicitOptions {
  bool leak;
  bool privacy;
  bool chinaDirect;
  bool strictRoute;
  bool chain;
  bool adapt;
  String entry;
  String landing;

  SystemExplicitOptions({
    this.leak = false,
    this.privacy = false,
    this.chinaDirect = false,
    this.strictRoute = false,
    this.chain = false,
    this.adapt = false,
    this.entry = '',
    this.landing = '',
  });

  bool get anyEnabled =>
      leak || privacy || chinaDirect || strictRoute || chain;

  Map<String, dynamic> toJson() => {
    'leak': leak,
    'privacy': privacy,
    'chinaDirect': chinaDirect,
    'strictRoute': strictRoute,
    'chain': chain,
    'adapt': adapt,
    'entry': entry,
    'landing': landing,
  };

  factory SystemExplicitOptions.fromJson(Map<String, dynamic> json) {
    return SystemExplicitOptions(
      leak: json['leak'] == true,
      privacy: json['privacy'] == true,
      chinaDirect: json['chinaDirect'] == true,
      strictRoute: json['strictRoute'] == true,
      chain: json['chain'] == true,
      adapt: json['adapt'] == true,
      entry: (json['entry'] ?? '').toString(),
      landing: (json['landing'] ?? '').toString(),
    );
  }
}

class SystemExplicitStore {
  SystemExplicitStore._();

  static final instance = SystemExplicitStore._();
  static const _key = 'system_explicit_v1';

  SystemExplicitOptions value = SystemExplicitOptions();
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        value = SystemExplicitOptions.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value.toJson()));
  }

  /// Highest priority. Does not rewrite the saved subscription.
  void apply(Map<String, dynamic> raw) {
    if (!value.anyEnabled) return;
    final rules = <dynamic>[];
    if (value.leak) {
      raw['ipv6'] = false;
      final dns = raw['dns'];
      if (dns is Map) dns['ipv6'] = false;
      final tun = raw['tun'];
      if (tun is Map) {
        final hijack = tun['dns-hijack'];
        if (hijack is! List || hijack.isEmpty) {
          tun['dns-hijack'] = ['any:53'];
        }
      }
      rules.add('AND,((NETWORK,UDP),(DST-PORT,3478)),REJECT');
      rules.add('IP-CIDR6,::/0,REJECT,no-resolve');
    }
    if (value.privacy) {
      rules.add('AND,((NETWORK,UDP),(DST-PORT,5353)),REJECT');
      rules.add('AND,((NETWORK,UDP),(DST-PORT,5355)),REJECT');
      rules.add('AND,((NETWORK,UDP),(DST-PORT,1900)),REJECT');
    }
    if (value.chinaDirect) {
      rules.add('GEOSITE,geolocation-cn,DIRECT');
      rules.add('GEOIP,CN,DIRECT,no-resolve');
    }
    if (value.strictRoute) {
      final tun = raw['tun'];
      if (tun is Map) tun['strict-route'] = true;
    }
    _applyChain(raw);
    final existing = raw['rules'];
    if (existing is List) rules.addAll(existing);
    raw['rules'] = rules;
  }

  void _applyChain(Map<String, dynamic> raw) {
    if (!value.chain) return;
    final entry = value.entry.trim();
    final landing = value.landing.trim();
    if (entry.isEmpty || landing.isEmpty || entry == landing) return;
    final proxies = raw['proxies'];
    if (proxies is! List) return;
    Map? target;
    var hasEntry = false;
    for (final proxy in proxies) {
      if (proxy is! Map) continue;
      if (proxy['name']?.toString() == entry) hasEntry = true;
      if (proxy['name']?.toString() == landing) target = proxy;
    }
    if (hasEntry && target != null) {
      target['dialer-proxy'] = entry;
    }
  }

  String notificationLabel(String profileLabel) {
    if (value.privacy) return 'Bettbox';
    return profileLabel;
  }
}
