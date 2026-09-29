import 'package:bett_box/common/path_guard.dart';
import 'package:bett_box/common/system_explicit.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SystemExplicitView extends ConsumerStatefulWidget {
  const SystemExplicitView({super.key});

  @override
  ConsumerState<SystemExplicitView> createState() => _SystemExplicitViewState();
}

class _SystemExplicitViewState extends ConsumerState<SystemExplicitView> {
  var _ready = false;
  var _note = '';

  @override
  void initState() {
    super.initState();
    _note = PathGuard.instance.note.value;
    PathGuard.instance.note.addListener(_onNote);
    SystemExplicitStore.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    PathGuard.instance.note.removeListener(_onNote);
    super.dispose();
  }

  void _onNote() {
    if (!mounted) return;
    setState(() => _note = PathGuard.instance.note.value);
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _t(String zh, String en) => _zh ? zh : en;

  Future<void> _commit() async {
    await SystemExplicitStore.instance.save();
    if (mounted) setState(() {});
    globalState.appController.updateClashConfigDebounce();
    await PathGuard.instance.sync(
      running: globalState.isStart,
      change: (group, proxy) => globalState.appController.changeProxy(
        groupName: group,
        proxyName: proxy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    final value = SystemExplicitStore.instance.value;
    return generateListView(
      generateSection(
        title: _t(
          '写在脚本和配置之后，只在开启时生效，不改订阅原文。',
          'Applied after scripts and the profile. Off leaves the profile unchanged.',
        ),
        items: [
          ListItem.switchItem(
            title: Text(_t('自适应通路', 'Adaptive path')),
            subtitle: Text(
              _t(
                '发出数据却收不到回包时会立刻复查。只切换正在走流量的手动组。连续两次、并且换过探测地址仍测不通，才换节点，并放开旧节点上卡住的连接。自动测速组不再把直连当作失败后的退路。不改订阅。',
                'If traffic stalls, check immediately and only switch the manual group carrying it. Two failures on different check addresses are required, then stuck connections are released. Automatic groups can no longer fall back to direct. The subscription is not edited.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.adapt,
              onChanged: (on) {
                value.adapt = on;
                _commit();
              },
            ),
          ),
          ListItem(
            title: Text(_t('最近一次切换', 'Last switch')),
            subtitle: Text(
              _note.isEmpty ? _t('还没有切换', 'None yet') : _note,
            ),
          ),
          ListItem.switchItem(
            title: Text(_t('防隐私', 'Privacy')),
            subtitle: Text(
              _t(
                '通知不显示配置名，并阻断局域网发现。',
                'Hides the profile name in notifications and blocks local discovery.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.privacy,
              onChanged: (on) {
                value.privacy = on;
                _commit();
              },
            ),
          ),
          ListItem.switchItem(
            title: Text(_t('中国直连', 'China direct')),
            subtitle: Text(
              _t(
                '中国域名和地址走直连。这不是 QUIC 的「排除国内」。',
                'Chinese domains and addresses go direct. This is not the QUIC domestic exception.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.chinaDirect,
              onChanged: (on) {
                value.chinaDirect = on;
                _commit();
              },
            ),
          ),
        ],
      ),
    );
  }
}
