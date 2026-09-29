import 'dart:convert';

import 'package:bett_box/common/explicit_policy.dart';
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

  void apply(Map<String, dynamic> raw) {
    if (value.adapt) dropAutomaticDirect(raw);
    if (!value.anyEnabled) return;
    final rules = <dynamic>[];
    if (value.leak) {
      hardenLeakDns(raw);
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
    if (value.chain) {
      applyChainPolicy(raw, entry: value.entry, landing: value.landing);
    }
    final existing = raw['rules'];
    if (existing is List) rules.addAll(existing);
    raw['rules'] = rules;
  }

  String notificationLabel(String profileLabel) {
    if (value.privacy) return 'Bettbox';
    return profileLabel;
  }
}
