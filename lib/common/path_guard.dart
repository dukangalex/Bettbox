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
  final ProbeBoard _probes = ProbeBoard();

  Timer? _timer;
  Timer? _fast;
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
      _fast?.cancel();
      _timer = null;
      _fast = null;
      return;
    }
    if (_timer != null) return;
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_tick());
    });
    _fast = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_wakeIfStalled());
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

    final now = DateTime.now();
    final delay = await _confirm(current, _urls(testUrl, now), now);
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
    final urls = _urls(testUrl, now);
    for (final name in ranked.take(3)) {
      final candidateDelay = await _confirm(name, urls, DateTime.now());
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

  Future<void> _wakeIfStalled() async {
    if (_busy || !globalState.isStart) return;
    try {
      if (await _trafficStalled()) unawaited(_tick());
    } catch (_) {}
  }

  Future<bool> _trafficStalled() async {
    final list = await clashCore.getConnections();
    final now = DateTime.now();
    var stalled = 0;
    for (final item in list) {
      if (item.metadata.network != 'tcp') continue;
      if (item.chains.any(reservedPathNames.contains)) continue;
      if (now.difference(item.start) < const Duration(seconds: 12)) continue;
      if (item.upload > 0 && item.download == 0) stalled++;
    }
    return stalled >= 3;
  }

  List<String> _urls(String? groupUrl, DateTime now) {
    final preferred = (groupUrl != null && groupUrl.isNotEmpty)
        ? groupUrl
        : _testUrl();
    return _probes.order(
      preferred: preferred,
      presets: presetTestUrls,
      now: now,
    );
  }

  /// One answering address is enough. Two different addresses must fail
  /// before the node itself is treated as down.
  Future<int?> _confirm(String name, List<String> urls, DateTime now) async {
    if (urls.isEmpty) return null;
    final checking = _probes.isRetired(urls.first, now) ? urls.take(1) : urls.take(2);
    final missed = <String>[];
    for (final url in checking) {
      final delay = await _probe(name, url);
      if (delay != null) {
        _probes.succeed(url);
        for (final missedUrl in missed) {
          if (_probes.missWhileNodeLived(missedUrl, now)) {
            commonPrint.log('探测地址暂停使用：$missedUrl');
            note.value = '探测地址已换掉，节点继续使用';
          }
        }
        return delay;
      }
      missed.add(url);
    }
    return null;
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
