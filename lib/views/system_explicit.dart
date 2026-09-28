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

  @override
  void initState() {
    super.initState();
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
    _entry.dispose();
    _landing.dispose();
    super.dispose();
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _t(String zh, String en) => _zh ? zh : en;

  Future<void> _commit() async {
    await SystemExplicitStore.instance.save();
    if (mounted) setState(() {});
    globalState.appController.updateClashConfigDebounce();
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
            title: Text(_t('防泄漏', 'Leak protection')),
            subtitle: Text(
              _t(
                '关闭 IPv6，劫持 DNS，阻断 STUN。已有的 IPv6 与 QUIC 开关保持原样。',
                'Disables IPv6, hijacks DNS, and rejects STUN. Existing IPv6 and QUIC switches stay as they are.',
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
                '落地节点经由入口节点连出。名称必须是配置里的节点名。',
                'The landing node dials through the entry node. Both names must exist in the profile.',
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
