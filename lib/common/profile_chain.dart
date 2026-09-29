import 'dart:convert';

import 'package:bett_box/common/explicit_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileChain {
  bool enabled;
  String entry;
  String landing;

  ProfileChain({
    this.enabled = false,
    this.entry = '',
    this.landing = '',
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'entry': entry,
    'landing': landing,
  };

  factory ProfileChain.fromJson(Map<String, dynamic> json) {
    return ProfileChain(
      enabled: json['enabled'] == true,
      entry: (json['entry'] ?? '').toString(),
      landing: (json['landing'] ?? '').toString(),
    );
  }
}

/// Per-profile chain. The subscription file itself is not rewritten.
class ProfileChainStore {
  ProfileChainStore._();

  static final instance = ProfileChainStore._();
  static const _key = 'profile_chain_v1';

  final Map<String, ProfileChain> byProfile = {};
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  ProfileChain of(String profileId) {
    return byProfile.putIfAbsent(profileId, ProfileChain.new);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (value is Map) {
          byProfile[key.toString()] = ProfileChain.fromJson(
            value.cast<String, dynamic>(),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final entry in byProfile.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  void apply(Map<String, dynamic> raw, String profileId) {
    final chain = byProfile[profileId];
    if (chain == null || !chain.enabled) return;
    applyChainPolicy(raw, entry: chain.entry, landing: chain.landing);
  }
}
