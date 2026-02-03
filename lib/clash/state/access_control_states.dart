// 应用访问控制状态定义：描述 VPN 分应用代理配置。
// 仅 Android 平台支持。

// 访问控制模式
enum AccessControlMode {
  // 禁用：所有应用都走 VPN
  disabled,

  // 白名单：仅列表中的应用走 VPN
  whitelist,

  // 黑名单：列表中的应用不走 VPN
  blacklist,
}

// 访问控制模式扩展方法
extension AccessControlModeExtension on AccessControlMode {
  // 转换为 Android 端常量值
  int toAndroidValue() {
    switch (this) {
      case AccessControlMode.disabled:
        return 0;
      case AccessControlMode.whitelist:
        return 1;
      case AccessControlMode.blacklist:
        return 2;
    }
  }

  // 从 Android 端常量值转换
  static AccessControlMode fromAndroidValue(int value) {
    switch (value) {
      case 1:
        return AccessControlMode.whitelist;
      case 2:
        return AccessControlMode.blacklist;
      default:
        return AccessControlMode.disabled;
    }
  }
}

// 已安装应用信息
class AppInfo {
  final String packageName;
  final String label;
  final bool isSystem;
  final bool hasInternet;

  const AppInfo({
    required this.packageName,
    required this.label,
    required this.isSystem,
    required this.hasInternet,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      packageName: json['packageName'] as String? ?? '',
      label: json['label'] as String? ?? '',
      isSystem: json['isSystem'] as bool? ?? false,
      hasInternet: json['hasInternet'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'label': label,
      'isSystem': isSystem,
      'hasInternet': hasInternet,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppInfo && other.packageName == packageName;
  }

  @override
  int get hashCode => packageName.hashCode;
}

// 访问控制配置
class AccessControlConfig {
  final AccessControlMode mode;
  final Set<String> selectedPackages;

  const AccessControlConfig({
    this.mode = AccessControlMode.disabled,
    this.selectedPackages = const {},
  });

  AccessControlConfig copyWith({
    AccessControlMode? mode,
    Set<String>? selectedPackages,
  }) {
    return AccessControlConfig(
      mode: mode ?? this.mode,
      selectedPackages: selectedPackages ?? this.selectedPackages,
    );
  }

  // 是否启用访问控制
  bool get isEnabled => mode != AccessControlMode.disabled;

  // 从 JSON 反序列化
  factory AccessControlConfig.fromJson(Map<String, dynamic> json) {
    final modeValue = json['mode'] as int? ?? 0;
    final packages = json['selectedPackages'] as List<dynamic>? ?? [];
    return AccessControlConfig(
      mode: AccessControlModeExtension.fromAndroidValue(modeValue),
      selectedPackages: packages.map((e) => e as String).toSet(),
    );
  }

  // 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.toAndroidValue(),
      'selectedPackages': selectedPackages.toList(),
    };
  }
}
