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
  final _entry = TextEditingController();
  final _landing = TextEditingController();
  var _ready = false;
  var _note = '';

  @override
  void initState() {
    super.initState();
    _note = PathGuard.instance.note.value;
    PathGuard.instance.note.addListener(_onNote);
    SystemExplicitStore.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      final value = SystemExplicitStore.instance.value;
      _entry.text = value.entry;
      _landing.text = value.landing;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    PathGuard.instance.note.removeListener(_onNote);
    _entry.dispose();
    _landing.dispose();
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
            title: Text(_t('防泄漏', 'Leak protection')),
            subtitle: Text(
              _t(
                '关闭 IPv6，劫持 53 端口。明文 DNS 会改成加密解析，国内地址被污染时改走加密备用。已经在用加密 DNS 的配置保持原样。阻断 STUN。',
                'Disables IPv6 and hijacks port 53. Plain DNS is replaced with encrypted resolvers, and poisoned domestic answers fall over to encrypted backup. Existing encrypted DNS is left alone. Blocks STUN.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.leak,
              onChanged: (on) {
                value.leak = on;
                _commit();
              },
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
          ListItem.switchItem(
            title: Text(_t('严格路由', 'Strict route')),
            subtitle: Text(
              _t(
                '开启后强制严格路由，覆盖配置、脚本和网络页里的关闭状态。',
                'When on, forces strict route over the profile, scripts, and the network switch.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.strictRoute,
              onChanged: (on) {
                value.strictRoute = on;
                _commit();
              },
            ),
          ),
          ListItem.switchItem(
            title: Text(_t('链式代理', 'Chain')),
            subtitle: Text(
              _t(
                '落地节点经由入口节点连出。配置里写明的节点直接套上入口。只存在于订阅提供器里的节点，会生成可选策略组「链式落地」。',
                'The landing node dials through the entry. Inline nodes are linked directly. Nodes that only exist in a provider become a selectable group named 链式落地.',
              ),
            ),
            delegate: SwitchDelegate(
              value: value.chain,
              onChanged: (on) {
                value.chain = on;
                _commit();
              },
            ),
          ),
          if (value.chain) ...[
            ListItem.input(
              title: Text(_t('入口节点', 'Entry')),
              subtitle: Text(
                _entry.text.isEmpty ? _t('节点名称', 'Node name') : _entry.text,
              ),
              delegate: InputDelegate(
                title: _t('入口节点', 'Entry'),
                value: _entry.text,
                onChanged: (text) {
                  value.entry = text ?? '';
                  _entry.text = value.entry;
                  _commit();
                },
              ),
            ),
            ListItem.input(
              title: Text(_t('落地节点', 'Landing')),
              subtitle: Text(
                _landing.text.isEmpty
                    ? _t('节点名称', 'Node name')
                    : _landing.text,
              ),
              delegate: InputDelegate(
                title: _t('落地节点', 'Landing'),
                value: _landing.text,
                onChanged: (text) {
                  value.landing = text ?? '';
                  _landing.text = value.landing;
                  _commit();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
