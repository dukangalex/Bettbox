import 'dart:convert';

/// Turns sing-box JSON, Xray JSON, and share-link subscriptions into a
/// Mihomo YAML document. Clash/Mihomo text is returned unchanged.
/// The original subscription file is only rewritten at import time.
class ImportNormalize {
  static String toMihomo(String raw) {
    final text = raw.replaceFirst('\uFEFF', '').trim();
    if (text.isEmpty || text.contains('age-encryption.org')) return raw;

    final unfolded = _unfold(text);
    if (_isMihomo(unfolded)) return unfolded == text ? raw : unfolded;

    final proxies = _collect(unfolded);
    if (proxies.isEmpty) return raw;
    return _emitDocument(proxies);
  }

  static String _unfold(String text) {
    if (_isMihomo(text) || text.startsWith('{') || text.startsWith('[')) {
      return text;
    }
    if (RegExp(
      r'(?:vmess|vless|trojan|ss|hysteria2|hy2|tuic|anytls)://',
      caseSensitive: false,
    ).hasMatch(text)) {
      return text;
    }
    final decoded = _decodeText(text);
    if (decoded == null) return text;
    final body = decoded.trim();
    if (_isMihomo(body) ||
        body.startsWith('{') ||
        body.contains('://')) {
      return body;
    }
    return text;
  }

  static bool _isMihomo(String text) {
    return RegExp(
      r'^\s*(proxies|proxy-groups|proxy-providers)\s*:',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(text);
  }

  static List<Map<String, dynamic>> _collect(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final fromJson = _fromJson(decoded);
        if (fromJson.isNotEmpty) return fromJson;
      } catch (_) {}
    }
    return _fromShareText(text);
  }

  static List<Map<String, dynamic>> _fromJson(Object? decoded) {
    if (decoded is List) {
      return _nameAll(decoded.whereType<Map>().map(_fromAnyNode));
    }
    if (decoded is! Map) return const [];
    final map = decoded.cast<String, dynamic>();
    if (map['proxies'] is List) {
      return _nameAll(
        (map['proxies'] as List).whereType<Map>().map((item) {
          final node = Map<String, dynamic>.from(item);
          if (node['type'] == null && node['protocol'] != null) {
            node['type'] = node['protocol'];
          }
          return node;
        }),
      );
    }
    final outbounds = map['outbounds'];
    if (outbounds is! List) return const [];
    final xray = map['routing'] is Map && map['route'] is! Map;
    return _nameAll(
      outbounds.whereType<Map>().map((item) {
        final node = Map<String, dynamic>.from(item);
        if (xray) return _fromXray(node);
        return _fromSingBox(node) ?? _fromXray(node);
      }),
    );
  }

  static List<Map<String, dynamic>> _fromShareText(String text) {
    final matches = RegExp(
      r'(?:vmess|vless|trojan|ss|hysteria2|hy2|tuic|anytls)://[^\s<>"\x27]+',
      caseSensitive: false,
    ).allMatches(text);
    return _nameAll(matches.map((m) => _fromShare(m.group(0)!)).whereType());
  }

  static List<Map<String, dynamic>> _nameAll(
    Iterable<Map<String, dynamic>?> nodes,
  ) {
    final used = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final node in nodes) {
      if (node == null) continue;
      final server = node['server']?.toString() ?? '';
      final port = node['port'];
      if (server.isEmpty || port is! int || port <= 0 || port > 65535) {
        continue;
      }
      final type = node['type']?.toString() ?? '';
      if (type.isEmpty) continue;
      var name = (node['name'] ?? '$server:$port').toString().trim();
      if (name.isEmpty) name = '$server:$port';
      var unique = name;
      var i = 2;
      while (used.contains(unique)) {
        unique = '$name-$i';
        i++;
      }
      used.add(unique);
      node['name'] = unique;
      out.add(node);
    }
    return out;
  }

  static Map<String, dynamic>? _fromAnyNode(Map raw) {
    final node = Map<String, dynamic>.from(raw);
    if (node.containsKey('server_port') || node['tls'] is Map) {
      return _fromSingBox(node);
    }
    if (node['protocol'] != null || node['streamSettings'] != null) {
      return _fromXray(node);
    }
    if (node['type'] != null && node['server'] != null) return node;
    return null;
  }

  static const _skipTypes = {
    'direct',
    'block',
    'reject',
    'dns',
    'selector',
    'urltest',
    'freedom',
    'blackhole',
    'loopback',
  };

  static Map<String, dynamic>? _fromSingBox(Map<String, dynamic> outbound) {
    final type = (outbound['type'] ?? outbound['protocol'] ?? '')
        .toString()
        .toLowerCase();
    if (type.isEmpty || _skipTypes.contains(type)) return null;
    final port = _asInt(outbound['server_port'] ?? outbound['port']);
    final server = (outbound['server'] ?? outbound['address'] ?? '').toString();
    if (server.isEmpty || port == null) return null;
    final node = <String, dynamic>{
      'name': outbound['tag'] ?? outbound['name'] ?? '$server:$port',
      'type': type == 'shadowsocks' ? 'ss' : type,
      'server': server,
      'port': port,
    };
    _copyIf(node, 'password', outbound['password']);
    _copyIf(node, 'uuid', outbound['uuid']);
    _copyIf(node, 'username', outbound['username']);
    if (outbound['method'] != null) node['cipher'] = outbound['method'];
    if (outbound['cipher'] != null) node['cipher'] = outbound['cipher'];
    _copyIf(node, 'alterId', outbound['alter_id'] ?? outbound['alterId']);
    _copyIf(node, 'flow', outbound['flow']);
    _copyIf(node, 'udp', outbound['udp']);
    _copyIf(node, 'up', outbound['up_mbps'] ?? outbound['up']);
    _copyIf(node, 'down', outbound['down_mbps'] ?? outbound['down']);
    if (outbound['obfs'] is Map) {
      final obfs = (outbound['obfs'] as Map).cast<String, dynamic>();
      _copyIf(node, 'obfs', obfs['type']);
      _copyIf(node, 'obfs-password', obfs['password']);
    } else {
      _copyIf(node, 'obfs', outbound['obfs']);
      _copyIf(node, 'obfs-password', outbound['obfs_password']);
    }
    final tls = outbound['tls'];
    if (tls is Map) {
      final tlsMap = tls.cast<String, dynamic>();
      final reality = tlsMap['reality'];
      final realityOn = reality is Map && reality['enabled'] == true;
      if (tlsMap['enabled'] == true || realityOn) node['tls'] = true;
      _copyIf(node, 'sni', tlsMap['server_name'] ?? tlsMap['serverName']);
      if (tlsMap['insecure'] == true) node['skip-cert-verify'] = true;
      if (tlsMap['alpn'] is List && (tlsMap['alpn'] as List).isNotEmpty) {
        node['alpn'] = List<dynamic>.from(tlsMap['alpn'] as List);
      }
      final utls = tlsMap['utls'];
      if (utls is Map && utls['fingerprint'] != null) {
        node['client-fingerprint'] = utls['fingerprint'];
      }
      if (realityOn) {
        final realityMap = (reality as Map).cast<String, dynamic>();
        node['reality-opts'] = {
          'public-key': realityMap['public_key'] ?? realityMap['publicKey'],
          'short-id': realityMap['short_id'] ?? realityMap['shortId'] ?? '',
        };
      }
    }
    final transport = outbound['transport'];
    if (transport is Map) {
      _applyTransport(node, transport.cast<String, dynamic>());
    }
    if (type == 'tuic') {
      _copyIf(
        node,
        'congestion-controller',
        outbound['congestion_control'] ?? outbound['congestion-controller'],
      );
      _copyIf(
        node,
        'udp-relay-mode',
        outbound['udp_relay_mode'] ?? outbound['udp-relay-mode'],
      );
      _copyIf(node, 'reduce-rtt', outbound['zero_rtt_handshake']);
    }
    return node;
  }

  static Map<String, dynamic>? _fromXray(Map<String, dynamic> outbound) {
    final protocol = (outbound['protocol'] ?? outbound['type'] ?? '')
        .toString()
        .toLowerCase();
    if (protocol.isEmpty || _skipTypes.contains(protocol)) return null;
    final settings = outbound['settings'];
    final settingsMap = settings is Map
        ? settings.cast<String, dynamic>()
        : const <String, dynamic>{};
    String server = '';
    int? port;
    String? uuid;
    String? password;
    String? cipher;
    String? flow;
    dynamic alterId;

    final vnext = settingsMap['vnext'];
    if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
      final hop = (vnext.first as Map).cast<String, dynamic>();
      server = (hop['address'] ?? '').toString();
      port = _asInt(hop['port']);
      final users = hop['users'];
      if (users is List && users.isNotEmpty && users.first is Map) {
        final user = (users.first as Map).cast<String, dynamic>();
        uuid = user['id']?.toString();
        password = user['password']?.toString();
        cipher = user['security']?.toString();
        flow = user['flow']?.toString();
        alterId = user['alterId'];
      }
    }
    final servers = settingsMap['servers'];
    if (server.isEmpty &&
        servers is List &&
        servers.isNotEmpty &&
        servers.first is Map) {
      final hop = (servers.first as Map).cast<String, dynamic>();
      server = (hop['address'] ?? '').toString();
      port = _asInt(hop['port']);
      password = hop['password']?.toString();
      cipher = hop['method']?.toString();
    }
    if (server.isEmpty || port == null) return null;
    final node = <String, dynamic>{
      'name': outbound['tag'] ?? outbound['name'] ?? '$server:$port',
      'type': protocol == 'shadowsocks' ? 'ss' : protocol,
      'server': server,
      'port': port,
    };
    _copyIf(node, 'uuid', uuid);
    _copyIf(node, 'password', password);
    _copyIf(node, 'cipher', cipher);
    _copyIf(node, 'flow', flow);
    _copyIf(node, 'alterId', alterId);
    final stream = outbound['streamSettings'] ?? outbound['stream_settings'];
    if (stream is Map) {
      _applyXrayStream(node, stream.cast<String, dynamic>());
    }
    return node;
  }

  static void _applyTransport(
    Map<String, dynamic> node,
    Map<String, dynamic> transport,
  ) {
    final type = transport['type']?.toString();
    if (type == null || type.isEmpty || type == 'tcp') return;
    node['network'] = type == 'http' ? 'h2' : type;
    if (type == 'ws') {
      final opts = <String, dynamic>{'path': transport['path'] ?? '/'};
      if (transport['headers'] is Map) {
        opts['headers'] = transport['headers'];
      }
      node['ws-opts'] = opts;
    } else if (type == 'grpc') {
      node['grpc-opts'] = {
        'grpc-service-name':
            transport['service_name'] ?? transport['serviceName'] ?? '',
      };
    } else if (type == 'http' || type == 'h2') {
      final opts = <String, dynamic>{};
      if (transport['path'] != null) opts['path'] = transport['path'];
      if (transport['host'] is List) opts['host'] = transport['host'];
      if (transport['headers'] is Map) opts['headers'] = transport['headers'];
      node['http-opts'] = opts;
    }
  }

  static void _applyXrayStream(
    Map<String, dynamic> node,
    Map<String, dynamic> stream,
  ) {
    final network = stream['network']?.toString();
    if (network != null && network.isNotEmpty && network != 'tcp') {
      node['network'] = network == 'http' ? 'h2' : network;
    }
    final security = stream['security']?.toString();
    if (security == 'tls' || security == 'reality') node['tls'] = true;
    final tls = stream['tlsSettings'] ?? stream['tls_settings'];
    if (tls is Map) {
      final tlsMap = tls.cast<String, dynamic>();
      _copyIf(node, 'sni', tlsMap['serverName'] ?? tlsMap['server_name']);
      if (tlsMap['allowInsecure'] == true || tlsMap['allow_insecure'] == true) {
        node['skip-cert-verify'] = true;
      }
      if (tlsMap['alpn'] is List) node['alpn'] = tlsMap['alpn'];
      _copyIf(node, 'client-fingerprint', tlsMap['fingerprint']);
    }
    final reality = stream['realitySettings'] ?? stream['reality_settings'];
    if (reality is Map) {
      final realityMap = reality.cast<String, dynamic>();
      node['tls'] = true;
      _copyIf(node, 'sni', realityMap['serverName'] ?? realityMap['server_name']);
      _copyIf(node, 'client-fingerprint', realityMap['fingerprint']);
      node['reality-opts'] = {
        'public-key': realityMap['publicKey'] ?? realityMap['public_key'],
        'short-id': realityMap['shortId'] ?? realityMap['short_id'] ?? '',
      };
    }
    final ws = stream['wsSettings'] ?? stream['ws_settings'];
    if (ws is Map) {
      final wsMap = ws.cast<String, dynamic>();
      final opts = <String, dynamic>{'path': wsMap['path'] ?? '/'};
      if (wsMap['headers'] is Map) opts['headers'] = wsMap['headers'];
      node['ws-opts'] = opts;
      node['network'] = 'ws';
    }
    final grpc = stream['grpcSettings'] ?? stream['grpc_settings'];
    if (grpc is Map) {
      node['network'] = 'grpc';
      node['grpc-opts'] = {
        'grpc-service-name':
            (grpc as Map)['serviceName'] ?? grpc['service_name'] ?? '',
      };
    }
  }

  static Map<String, dynamic>? _fromShare(String link) {
    final lower = link.toLowerCase();
    if (lower.startsWith('vmess://')) return _fromVmess(link);
    if (lower.startsWith('vless://')) return _fromVless(link);
    if (lower.startsWith('trojan://')) return _fromTrojan(link);
    if (lower.startsWith('ss://')) return _fromShadowsocks(link);
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      return _fromHysteria2(link);
    }
    if (lower.startsWith('tuic://')) return _fromTuic(link);
    if (lower.startsWith('anytls://')) return _fromAnyTls(link);
    return null;
  }

  static Map<String, dynamic>? _fromVmess(String link) {
    final payload = link.substring('vmess://'.length).split('#').first;
    final bytes = _decodeTextBytes(payload);
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) return null;
      final map = json.cast<String, dynamic>();
      final server = (map['add'] ?? '').toString();
      final port = _asInt(map['port']);
      if (server.isEmpty || port == null) return null;
      final node = <String, dynamic>{
        'name': map['ps'] ?? '$server:$port',
        'type': 'vmess',
        'server': server,
        'port': port,
        'uuid': map['id'] ?? '',
        'alterId': _asInt(map['aid']) ?? 0,
        'cipher': (map['scy'] ?? 'auto').toString(),
        'udp': true,
      };
      final net = (map['net'] ?? 'tcp').toString();
      if (net.isNotEmpty && net != 'tcp') node['network'] = net;
      final tls = (map['tls'] ?? '').toString();
      if (tls == 'tls' || tls == 'reality') node['tls'] = true;
      _copyIf(node, 'sni', map['sni']);
      _copyIf(node, 'client-fingerprint', map['fp']);
      if (net == 'ws') {
        final headers = <String, dynamic>{};
        if ((map['host'] ?? '').toString().isNotEmpty) {
          headers['Host'] = map['host'];
        }
        node['ws-opts'] = {'path': map['path'] ?? '/', 'headers': headers};
      } else if (net == 'grpc') {
        node['grpc-opts'] = {'grpc-service-name': map['path'] ?? ''};
      }
      return node;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _fromVless(String link) {
    final uri = _parseUri(link);
    if (uri == null || uri.host.isEmpty) return null;
    final node = <String, dynamic>{
      'name': _fragment(uri, '${uri.host}:${uri.port}'),
      'type': 'vless',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'uuid': Uri.decodeComponent(uri.userInfo),
      'udp': true,
    };
    _querySecurity(node, uri);
    _copyIf(node, 'flow', uri.queryParameters['flow']);
    _queryTransport(node, uri);
    return node;
  }

  static Map<String, dynamic>? _fromTrojan(String link) {
    final uri = _parseUri(link);
    if (uri == null || uri.host.isEmpty) return null;
    final node = <String, dynamic>{
      'name': _fragment(uri, '${uri.host}:${uri.port}'),
      'type': 'trojan',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'password': Uri.decodeComponent(uri.userInfo),
      'udp': true,
    };
    _querySecurity(node, uri);
    _queryTransport(node, uri);
    return node;
  }

  static Map<String, dynamic>? _fromShadowsocks(String link) {
    final raw = link.substring('ss://'.length);
    final hash = raw.indexOf('#');
    final name = hash >= 0
        ? Uri.decodeComponent(raw.substring(hash + 1))
        : '';
    final body = hash >= 0 ? raw.substring(0, hash) : raw;
    String decoded;
    if (body.contains('@')) {
      final at = body.lastIndexOf('@');
      final user = _decodeText(body.substring(0, at)) ?? body.substring(0, at);
      decoded = '$user@${body.substring(at + 1)}';
    } else {
      final text = _decodeText(body.split('?').first);
      if (text == null || !text.contains('@')) return null;
      decoded = text;
    }
    final at = decoded.lastIndexOf('@');
    final user = decoded.substring(0, at);
    final hostport = decoded.substring(at + 1).split('?').first;
    final colon = user.indexOf(':');
    final hostColon = hostport.lastIndexOf(':');
    if (colon <= 0 || hostColon <= 0) return null;
    final port = _asInt(hostport.substring(hostColon + 1));
    if (port == null) return null;
    return {
      'name': name.isEmpty ? hostport : name,
      'type': 'ss',
      'server': hostport.substring(0, hostColon),
      'port': port,
      'cipher': user.substring(0, colon),
      'password': user.substring(colon + 1),
      'udp': true,
    };
  }

  static Map<String, dynamic>? _fromHysteria2(String link) {
    final uri = _parseUri(link.replaceFirst(RegExp(r'^hy2://', caseSensitive: false), 'hysteria2://'));
    if (uri == null || uri.host.isEmpty) return null;
    final node = <String, dynamic>{
      'name': _fragment(uri, '${uri.host}:${uri.port}'),
      'type': 'hysteria2',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'password': Uri.decodeComponent(uri.userInfo),
    };
    _copyIf(node, 'sni', uri.queryParameters['sni']);
    if (uri.queryParameters['insecure'] == '1' ||
        uri.queryParameters['insecure'] == 'true') {
      node['skip-cert-verify'] = true;
    }
    _copyIf(node, 'obfs', uri.queryParameters['obfs']);
    _copyIf(node, 'obfs-password', uri.queryParameters['obfs-password']);
    final alpn = uri.queryParameters['alpn'];
    if (alpn != null && alpn.isNotEmpty) node['alpn'] = alpn.split(',');
    return node;
  }

  static Map<String, dynamic>? _fromTuic(String link) {
    final uri = _parseUri(link);
    if (uri == null || uri.host.isEmpty) return null;
    final user = Uri.decodeComponent(uri.userInfo);
    final split = user.split(':');
    final node = <String, dynamic>{
      'name': _fragment(uri, '${uri.host}:${uri.port}'),
      'type': 'tuic',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'uuid': split.first,
      'password': split.length > 1 ? split.sublist(1).join(':') : '',
    };
    _copyIf(node, 'sni', uri.queryParameters['sni']);
    _copyIf(
      node,
      'congestion-controller',
      uri.queryParameters['congestion_control'] ??
          uri.queryParameters['congestion-controller'],
    );
    _copyIf(
      node,
      'udp-relay-mode',
      uri.queryParameters['udp_relay_mode'] ??
          uri.queryParameters['udp-relay-mode'],
    );
    final alpn = uri.queryParameters['alpn'];
    if (alpn != null && alpn.isNotEmpty) node['alpn'] = alpn.split(',');
    return node;
  }

  static Map<String, dynamic>? _fromAnyTls(String link) {
    final uri = _parseUri(link);
    if (uri == null || uri.host.isEmpty) return null;
    final node = <String, dynamic>{
      'name': _fragment(uri, '${uri.host}:${uri.port}'),
      'type': 'anytls',
      'server': uri.host,
      'port': uri.hasPort ? uri.port : 443,
      'password': Uri.decodeComponent(uri.userInfo),
    };
    _querySecurity(node, uri);
    return node;
  }

  static void _querySecurity(Map<String, dynamic> node, Uri uri) {
    final security = (uri.queryParameters['security'] ?? '').toLowerCase();
    if (security == 'tls' || security == 'reality') node['tls'] = true;
    _copyIf(node, 'sni', uri.queryParameters['sni']);
    _copyIf(node, 'client-fingerprint', uri.queryParameters['fp']);
    if (uri.queryParameters['allowInsecure'] == '1' ||
        uri.queryParameters['insecure'] == '1') {
      node['skip-cert-verify'] = true;
    }
    final alpn = uri.queryParameters['alpn'];
    if (alpn != null && alpn.isNotEmpty) node['alpn'] = alpn.split(',');
    if (security == 'reality') {
      node['tls'] = true;
      node['reality-opts'] = {
        'public-key': uri.queryParameters['pbk'] ?? '',
        'short-id': uri.queryParameters['sid'] ?? '',
      };
    }
  }

  static void _queryTransport(Map<String, dynamic> node, Uri uri) {
    final type = (uri.queryParameters['type'] ?? '').toLowerCase();
    if (type.isEmpty || type == 'tcp') return;
    node['network'] = type;
    if (type == 'ws') {
      final headers = <String, dynamic>{};
      final host = uri.queryParameters['host'];
      if (host != null && host.isNotEmpty) headers['Host'] = host;
      node['ws-opts'] = {
        'path': uri.queryParameters['path'] ?? '/',
        'headers': headers,
      };
    } else if (type == 'grpc') {
      node['grpc-opts'] = {
        'grpc-service-name': uri.queryParameters['serviceName'] ??
            uri.queryParameters['path'] ??
            '',
      };
    }
  }

  static String _emitDocument(List<Map<String, dynamic>> proxies) {
    final names = proxies.map((p) => p['name'].toString()).toList();
    final buf = StringBuffer();
    buf.writeln('proxies:');
    for (final proxy in proxies) {
      _writeMap(buf, proxy, 0, dash: true);
    }
    buf.writeln('proxy-groups:');
    _writeMap(buf, {
      'name': 'PROXY',
      'type': 'select',
      'proxies': [...names, 'DIRECT'],
    }, 0, dash: true);
    buf.writeln('rules:');
    buf.writeln('  - MATCH,PROXY');
    return buf.toString();
  }

  static void _writeMap(
    StringBuffer buf,
    Map<String, dynamic> map,
    int indent, {
    bool dash = false,
  }) {
    final pad = '  ' * indent;
    var first = true;
    map.forEach((key, value) {
      if (value == null) return;
      final prefix = first && dash ? '$pad- ' : '$pad  ';
      first = false;
      if (value is Map) {
        buf.writeln('$prefix$key:');
        _writeMap(buf, value.cast<String, dynamic>(), indent + 1);
      } else if (value is List) {
        if (value.isEmpty) {
          buf.writeln('$prefix$key: []');
          return;
        }
        if (value.every((item) => item is! Map && item is! List)) {
          buf.writeln('$prefix$key:');
          for (final item in value) {
            buf.writeln('${'  ' * (indent + 2)}- ${_scalar(item)}');
          }
        } else {
          buf.writeln('$prefix$key:');
          for (final item in value) {
            if (item is Map) {
              _writeMap(buf, item.cast<String, dynamic>(), indent + 1, dash: true);
            }
          }
        }
      } else {
        buf.writeln('$prefix$key: ${_scalar(value)}');
      }
    });
  }

  static String _scalar(Object? value) {
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) {
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    final text = value?.toString() ?? '';
    if (RegExp(r'''[:#{}[\],&*!|>'"%@`]|^\s|\s$|\n''').hasMatch(text) ||
        text.isEmpty ||
        RegExp(
          r'^(true|false|null|~)$',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(r'^-?\d').hasMatch(text)) {
      return '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }
    return text;
  }

  static void _copyIf(Map<String, dynamic> node, String key, Object? value) {
    if (value == null) return;
    if (value is String && value.isEmpty) return;
    node[key] = value;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static Uri? _parseUri(String link) {
    try {
      return Uri.parse(link);
    } catch (_) {
      return null;
    }
  }

  static String _fragment(Uri uri, String fallback) {
    if (uri.fragment.isEmpty) return fallback;
    return Uri.decodeComponent(uri.fragment);
  }

  static String? _decodeText(String input) {
    final bytes = _decodeTextBytes(input);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static List<int>? _decodeTextBytes(String input) {
    var text = input.trim().replaceAll(RegExp(r'\s'), '');
    if (text.isEmpty ||
        !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(text)) {
      return null;
    }
    text = text.replaceAll('-', '+').replaceAll('_', '/');
    final mod = text.length % 4;
    if (mod == 1) return null;
    if (mod > 0) text = text.padRight(text.length + (4 - mod), '=');
    try {
      return base64Decode(text);
    } catch (_) {
      return null;
    }
  }
}
