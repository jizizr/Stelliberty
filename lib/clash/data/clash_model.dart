// 代理组信息
class ProxyGroup {
  final String name;
  final String type; // Selector、URLTest、Fallback、LoadBalance
  final String? now; // 当前选中的节点
  final List<String> all; // 所有可用节点
  final bool hidden; // 是否隐藏

  ProxyGroup({
    required this.name,
    required this.type,
    this.now,
    required this.all,
    this.hidden = false,
  });

  factory ProxyGroup.fromJson(String name, Map<String, dynamic> json) {
    return ProxyGroup(
      name: name,
      type: json['type'] ?? '',
      now: json['now'],
      all: List<String>.from(json['all'] ?? []),
      hidden: json['hidden'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'now': now,
      'all': all,
      'hidden': hidden,
    };
  }

  ProxyGroup copyWith({
    String? name,
    String? type,
    String? now,
    List<String>? all,
    bool? hidden,
  }) {
    return ProxyGroup(
      name: name ?? this.name,
      type: type ?? this.type,
      now: now ?? this.now,
      all: all ?? this.all,
      hidden: hidden ?? this.hidden,
    );
  }
}

// 代理节点信息
class ProxyNode {
  final String name;
  final String type; // Shadowsocks、VMess、Trojan 等
  final int? delay; // 延迟（ms）
  final String? server;
  final int? port;

  ProxyNode({
    required this.name,
    required this.type,
    this.delay,
    this.server,
    this.port,
  });

  factory ProxyNode.fromJson(String name, Map<String, dynamic> json) {
    return ProxyNode(
      name: name,
      type: json['type'] ?? '',
      delay: json['delay'],
      server: json['server'],
      port: json['port'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'delay': delay,
      'server': server,
      'port': port,
    };
  }

  ProxyNode copyWith({
    String? name,
    String? type,
    int? delay,
    String? server,
    int? port,
  }) {
    return ProxyNode(
      name: name ?? this.name,
      type: type ?? this.type,
      delay: delay ?? this.delay,
      server: server ?? this.server,
      port: port ?? this.port,
    );
  }

  // 判断是否是代理组
  bool get isGroup {
    final lowerType = type.toLowerCase();
    return lowerType == 'selector' ||
        lowerType == 'urltest' ||
        lowerType == 'fallback' ||
        lowerType == 'loadbalance' ||
        lowerType == 'relay' ||
        lowerType == 'load-balance' ||
        lowerType == 'select';
  }

  // 判断是否是实际节点
  bool get isProxy {
    final lowerType = type.toLowerCase();
    return lowerType == 'shadowsocks' ||
        lowerType == 'shadowsocksr' ||
        lowerType == 'vmess' ||
        lowerType == 'trojan' ||
        lowerType == 'snell' ||
        lowerType == 'http' ||
        lowerType == 'https' ||
        lowerType == 'socks5' ||
        lowerType == 'socks' ||
        lowerType == 'vless' ||
        lowerType == 'hysteria' ||
        lowerType == 'hysteria2' ||
        lowerType == 'tuic' ||
        lowerType == 'wireguard' ||
        lowerType == 'ss' ||
        lowerType == 'ssr';
  }

  // 获取延迟显示文本
  String get delayText {
    if (delay == null) {
      return '-';
    }
    return delay.toString();
  }

  // 获取延迟颜色（用于 UI 展示）
  String get delayColor {
    if (delay == null || delay! < 0) {
      return 'grey';
    } else if (delay! < 100) {
      return 'green';
    } else if (delay! < 300) {
      return 'orange';
    } else {
      return 'red';
    }
  }
}

// 虚拟网卡模式配置
class TunConfig {
  final bool enable; // 是否启用虚拟网卡模式
  final String stack; // 网络栈：gvisor、mixed、system
  final String device; // 虚拟网卡名称
  final bool autoRoute; // 自动路由
  final bool autoDetectInterface; // 自动检测接口
  final List<String> dnsHijack; // DNS 劫持列表
  final bool strictRoute; // 严格路由
  final int mtu; // 最大传输单元

  const TunConfig({
    this.enable = false,
    this.stack = 'gvisor',
    this.device = 'Mihomo',
    this.autoRoute = true,
    this.autoDetectInterface = true,
    this.dnsHijack = const ['any:53'],
    this.strictRoute = false,
    this.mtu = 1500,
  });

  Map<String, dynamic> toJson() {
    return {
      'enable': enable,
      'stack': stack,
      'device': device,
      'auto-route': autoRoute,
      'auto-detect-interface': autoDetectInterface,
      'dns-hijack': dnsHijack,
      'strict-route': strictRoute,
      'mtu': mtu,
    };
  }

  factory TunConfig.fromJson(Map<String, dynamic> json) {
    return TunConfig(
      enable: json['enable'] ?? false,
      stack: json['stack'] ?? 'gvisor',
      device: json['device'] ?? 'Mihomo',
      autoRoute: json['auto-route'] ?? true,
      autoDetectInterface: json['auto-detect-interface'] ?? true,
      dnsHijack:
          (json['dns-hijack'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['any:53'],
      strictRoute: json['strict-route'] ?? false,
      mtu: json['mtu'] ?? 1500,
    );
  }

  TunConfig copyWith({
    bool? enable,
    String? stack,
    String? device,
    bool? autoRoute,
    bool? autoDetectInterface,
    List<String>? dnsHijack,
    bool? strictRoute,
    int? mtu,
  }) {
    return TunConfig(
      enable: enable ?? this.enable,
      stack: stack ?? this.stack,
      device: device ?? this.device,
      autoRoute: autoRoute ?? this.autoRoute,
      autoDetectInterface: autoDetectInterface ?? this.autoDetectInterface,
      dnsHijack: dnsHijack ?? this.dnsHijack,
      strictRoute: strictRoute ?? this.strictRoute,
      mtu: mtu ?? this.mtu,
    );
  }
}
