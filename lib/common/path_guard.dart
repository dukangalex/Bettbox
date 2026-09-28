import 'dart:async';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/constant.dart';
import 'package:bett_box/common/path_score.dart';
import 'package:bett_box/common/print.dart';
import 'package:bett_box/common/system_explicit.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/common.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/foundation.dart';

typedef PathSwitch = Future<void> Function(String groupName, String proxyName);

class _Memory {
  int streak = 0;
  int? latencyMs;
  DateTime? coolUntil;
}

/// While the core is running, probes the node each manual group is using.
/// Two failures in a row move that group to another node that still answers.
/// It never selects DIRECT, and it does not rewrite the subscription.
class PathGuard {
  PathGuard._();

  static final instance = PathGuard._();

  final note = ValueNotifier<String>('');
  final Map<String, _Memory> _memory = {};
  final Map<String, DateTime> _switchedAt = {};

  Timer? _timer;
  PathSwitch? _change;
  var _busy = false;

  Future<void> sync({
    required bool running,
    required PathSwitch change,
  }) async {
    _change = change;
    await SystemExplicitStore.instance.ensureLoaded();
    final want = running && SystemExplicitStore.instance.value.adapt;
    if (!want) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_tick());
    });
  }

  Future<void> _tick() async {
    if (_busy || _change == null) return;
    if (!globalState.isStart || !SystemExplicitStore.instance.value.adapt) {
      return;
    }
    _busy = true;
    try {
      final groups = await clashCore.getProxiesGroups();
      final selectors = groups
          .where(
            (group) =>
                group.type == GroupType.Selector && group.hidden != true,
          )
          .take(4);
      for (final group in selectors) {
        await _heal(group.name, group.now ?? '', group.all, group.testUrl);
      }
    } catch (e) {
      commonPrint.log('通路检查失败: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _heal(
    String groupName,
    String current,
    List<Proxy> members,
    String? testUrl,
  ) async {
    if (current.isEmpty || reservedPathNames.contains(current)) return;
    final samples = <PathSample>[];
    String? currentType;
    for (final member in members) {
      final name = member.name;
      final type = member.type;
      if (name == current) currentType = type;
      final memory = _memory[name];
      samples.add(
        PathSample(
          name: name,
          type: type,
          streak: memory?.streak ?? 0,
          latencyMs: memory?.latencyMs,
          coolUntil: memory?.coolUntil,
        ),
      );
    }
    if (currentType == null || !isLeafPath(currentType)) return;

    final url = (testUrl != null && testUrl.isNotEmpty)
        ? testUrl
        : _testUrl();
    final delay = await _probe(current, url);
    final now = DateTime.now();
    _remember(current, delay, now);
    if (!pathUnhealthy(_memory[current]?.streak ?? 0)) return;

    final last = _switchedAt[groupName];
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }

    final ranked = rankAlternates(
      current: current,
      nodes: samples,
      now: now,
    );
    for (final name in ranked.take(3)) {
      final candidateDelay = await _probe(name, url);
      _remember(name, candidateDelay, DateTime.now());
      if (candidateDelay == null) continue;
      await _change!(groupName, name);
      _switchedAt[groupName] = DateTime.now();
      final text = '通路切换：$groupName  $current → $name';
      note.value = text;
      commonPrint.log(text);
      return;
    }
    note.value = '通路保持：$groupName 仍使用 $current，暂无可用替换';
  }

  Future<int?> _probe(String name, String url) async {
    try {
      final delay = await clashCore
          .getDelay(url, name)
          .timeout(const Duration(seconds: 8));
      final value = delay.value;
      if (value == null || value <= 0 || value > 8000) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  void _remember(String name, int? delay, DateTime now) {
    final memory = _memory.putIfAbsent(name, _Memory.new);
    if (delay == null) {
      memory.streak += 1;
      memory.coolUntil = pathCooldown(memory.streak, now);
      return;
    }
    memory.streak = 0;
    memory.latencyMs = delay;
    memory.coolUntil = null;
  }

  String _testUrl() {
    final configured = globalState.config.appSetting.testUrl;
    if (configured.isEmpty) return defaultTestUrl;
    return configured;
  }
}
