import 'dart:convert';

import 'package:bett_box/common/explicit_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime policy applied after the profile, the script, and the built-in
/// network overrides. Off by default so existing profiles keep their behavior.
class SystemExplicitOptions {
  bool privacy;
  bool chinaDirect;
  bool adapt;

  SystemExplicitOptions({
    this.privacy = false,
    this.chinaDirect = false,
    this.adapt = false,
  });

  bool get anyEnabled => privacy || chinaDirect;

  Map<String, dynamic> toJson() => {
    'privacy': privacy,
    'chinaDirect': chinaDirect,
    'adapt': adapt,
  };

  factory SystemExplicitOptions.fromJson(Map<String, dynamic> json) {
    return SystemExplicitOptions(
      privacy: json['privacy'] == true,
      chinaDirect: json['chinaDirect'] == true,
      adapt: json['adapt'] == true,
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
    if (value.privacy) {
      rules.add('AND,((NETWORK,UDP),(DST-PORT,5353)),REJECT');
      rules.add('AND,((NETWORK,UDP),(DST-PORT,5355)),REJECT');
      rules.add('AND,((NETWORK,UDP),(DST-PORT,1900)),REJECT');
    }
    if (value.chinaDirect) {
      rules.add('GEOSITE,geolocation-cn,DIRECT');
      rules.add('GEOIP,CN,DIRECT,no-resolve');
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
