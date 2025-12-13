// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_dropdown_menu.dart';
import 'package:stelliberty/ui/common/modern_dropdown_button.dart';
import 'package:stelliberty/ui/common/modern_text_field.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';
import 'package:stelliberty/ui/widgets/modern_toast.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/clash/providers/service_provider.dart';
import 'package:stelliberty/clash/core/service_state.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/utils/logger.dart';

// 虚拟网卡网络栈类型枚举
enum TunStack {
  mixed('mixed', 'Mixed'),
  gvisor('gvisor', 'gVisor'),
  system('system', 'System');

  const TunStack(this.value, this.displayName);

  final String value;
  final String displayName;

  static TunStack fromString(String value) {
    for (final stack in TunStack.values) {
      if (stack.value == value) return stack;
    }
    return TunStack.mixed;
  }
}

// 虚拟网卡模式配置卡片组件
class TunConfigCard extends StatefulWidget {
  const TunConfigCard({super.key});

  @override
  State<TunConfigCard> createState() => _TunConfigCardState();
}

class _TunConfigCardState extends State<TunConfigCard> {
  // 加载状态
  bool _isLoading = true;

  // 虚拟网卡模式配置
  TunStack _tunStack = TunStack.mixed;
  final TextEditingController _tunDeviceController = TextEditingController();
  bool _tunAutoRoute = true;
  bool _tunAutoDetectInterface = true;
  bool _tunStrictRoute = true;
  final TextEditingController _tunMtuController = TextEditingController();
  final TextEditingController _tunDnsHijackController = TextEditingController();
  bool _tunAutoRedirect = false;
  final TextEditingController _tunRouteExcludeAddressController =
      TextEditingController();
  bool _tunDisableIcmpForwarding = false;

  // 错误状态
  String? _tunMtuError;

  // 保存状态
  bool _isSaving = false;

  bool _isHoveringOnTunStackMenu = false;

  @override
  void initState() {
    super.initState();
    // 延迟加载配置，先显示骨架屏
    Future.delayed(Duration.zero, () {
      _loadConfig();
      // 100ms 后隐藏骨架屏
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    });
  }

  @override
  void dispose() {
    _tunDeviceController.dispose();
    _tunMtuController.dispose();
    _tunDnsHijackController.dispose();
    _tunRouteExcludeAddressController.dispose();
    super.dispose();
  }

  // 加载虚拟网卡配置
  void _loadConfig() {
    if (!mounted) return;

    setState(() {
      _tunStack = TunStack.fromString(ClashManager.instance.tunStack);
      _tunDeviceController.text = ClashManager.instance.tunDevice;
      _tunAutoRoute = ClashManager.instance.isTunAutoRouteEnabled;
      _tunAutoDetectInterface =
          ClashManager.instance.isTunAutoDetectInterfaceEnabled;
      _tunStrictRoute = ClashManager.instance.isTunStrictRouteEnabled;
      _tunMtuController.text = ClashManager.instance.tunMtu.toString();
      _tunDnsHijackController.text = ClashManager.instance.tunDnsHijack.join(
        '，',
      );
      _tunAutoRedirect = ClashManager.instance.isTunAutoRedirectEnabled;
      _tunRouteExcludeAddressController.text = ClashManager
          .instance
          .tunRouteExcludeAddress
          .join('，');
      _tunDisableIcmpForwarding =
          ClashManager.instance.isTunIcmpForwardingDisabled;
    });
  }

  // 验证 MTU 值
  String? _validateMtu(String value) {
    if (value.isEmpty) {
      return context.translate.tunConfig.mtuError;
    }

    final mtu = int.tryParse(value);
    if (mtu == null) {
      return context.translate.tunConfig.mtuInvalid;
    }

    if (mtu < 1280 || mtu > 9000) {
      return context.translate.tunConfig.mtuRange;
    }

    return null;
  }

  // 统一保存文本输入配置
  Future<void> _saveConfig() async {
    if (_isSaving) return;

    // 验证 MTU 值
    final mtuError = _validateMtu(_tunMtuController.text);
    if (mtuError != null) {
      setState(() => _tunMtuError = mtuError);
      return;
    }
    setState(() => _tunMtuError = null);

    setState(() => _isSaving = true);

    try {
      // 保存设备名称
      final deviceName = _tunDeviceController.text.trim();
      if (deviceName.isNotEmpty) {
        ClashManager.instance.setTunDevice(deviceName);
      }

      // 保存 MTU
      final mtu = int.parse(_tunMtuController.text);
      ClashManager.instance.setTunMtu(mtu);

      // 保存 DNS 劫持列表
      final hijackList = _tunDnsHijackController.text
          .split('，')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      ClashManager.instance.setTunDnsHijack(hijackList);

      // 保存排除路由地址列表
      final addressList = _tunRouteExcludeAddressController.text
          .split('，')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      ClashManager.instance.setTunRouteExcludeAddress(addressList);

      if (mounted) {
        ModernToast.success(context, context.translate.tunConfig.saveSuccess);
      }
    } catch (e) {
      Logger.error('保存 TUN 配置失败: $e');
      if (mounted) {
        ModernToast.error(
          context,
          context.translate.tunConfig.saveFailed.replaceAll(
            '{error}',
            e.toString(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // 骨架屏占位 UI
  Widget _buildSkeleton(ThemeData theme) {
    final skeletonColor = theme.colorScheme.surfaceContainerHighest.withAlpha(
      100,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 服务模式安装
        Container(
          height: 72,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 16),
        // 网络栈 + 设备名称 + MTU
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 16),
        // 开关选项（自动路由、自动检测、严格路由）
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 16),
        // DNS 劫持 + 排除路由 + 禁用 ICMP
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    return ModernFeatureCard(
      isSelected: false,
      onTap: () {},
      enableHover: false,
      enableTap: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              const Icon(Icons.vpn_lock),
              const SizedBox(
                width: ModernFeatureCardSpacing.featureIconToTextSpacing,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.translate.clashFeatures.tunMode.title,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    context.translate.clashFeatures.tunMode.subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // 加载中显示骨架屏
          if (_isLoading)
            _buildSkeleton(theme)
          else
            ..._buildRealContent(context, theme),
        ],
      ),
    );
  }

  // 真实内容
  List<Widget> _buildRealContent(BuildContext context, ThemeData theme) {
    return [
      // ========== 服务模式安装（第一行） ==========
      Consumer<ServiceStateManager>(
        builder: (context, stateManager, _) {
          final serviceProvider = context.read<ServiceProvider>();
          final isServiceModeInstalled = stateManager.isServiceModeInstalled;
          final isServiceModeProcessing = stateManager.isServiceModeProcessing;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate.tunConfig.serviceMode,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isServiceModeInstalled
                          ? context.translate.tunConfig.serviceInstalled
                          : context.translate.tunConfig.serviceNotInstalled,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isServiceModeInstalled
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              ModernSwitch(
                value: isServiceModeInstalled,
                onChanged: isServiceModeProcessing
                    ? null
                    : (value) async {
                        if (value) {
                          // 安装服务
                          final success = await serviceProvider
                              .installService();
                          if (mounted) {
                            if (success) {
                              ModernToast.success(
                                context,
                                context
                                    .translate
                                    .tunConfig
                                    .serviceInstallSuccess,
                              );
                            } else {
                              // 显示详细错误信息（可能包含多行）
                              final errorMsg =
                                  serviceProvider.lastOperationError ??
                                  context
                                      .translate
                                      .tunConfig
                                      .serviceInstallFailed;
                              ModernToast.error(context, errorMsg);
                            }
                            serviceProvider.clearLastOperationResult();
                          }
                        } else {
                          // 卸载服务
                          final success = await serviceProvider
                              .uninstallService();
                          if (mounted) {
                            if (success) {
                              ModernToast.success(
                                context,
                                context
                                    .translate
                                    .tunConfig
                                    .serviceUninstallSuccess,
                              );
                            } else {
                              // 显示详细错误信息（可能包含多行）
                              final errorMsg =
                                  serviceProvider.lastOperationError ??
                                  context
                                      .translate
                                      .tunConfig
                                      .serviceUninstallFailed;
                              ModernToast.error(context, errorMsg);
                            }
                            serviceProvider.clearLastOperationResult();
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),

      const SizedBox(height: 16),
      Divider(color: Colors.grey.withValues(alpha: 0.2)),
      const SizedBox(height: 16),

      // 网络栈选择
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate.clashFeatures.tunMode.networkStack,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringOnTunStackMenu = true),
            onExit: (_) => setState(() => _isHoveringOnTunStackMenu = false),
            child: ModernDropdownMenu<TunStack>(
              items: TunStack.values,
              selectedItem: _tunStack,
              onSelected: (stack) {
                setState(() => _tunStack = stack);
                ClashManager.instance.setTunStack(stack.value);
              },
              itemToString: (stack) => stack.displayName,
              child: CustomDropdownButton(
                text: _tunStack.displayName,
                isHovering: _isHoveringOnTunStackMenu,
              ),
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      // 虚拟网卡名称
      Row(
        children: [
          Text(
            context.translate.clashFeatures.tunMode.deviceName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          SizedBox(
            width: 150,
            child: ModernTextField(
              controller: _tunDeviceController,
              hintText: 'Mihomo',
              height: 36,
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      // MTU 值
      Row(
        children: [
          Text(
            context.translate.clashFeatures.tunMode.mtu,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          SizedBox(
            width: 100,
            child: ModernTextField(
              controller: _tunMtuController,
              keyboardType: TextInputType.number,
              hintText: '1500',
              height: 36,
              errorText: _tunMtuError,
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      // 自动路由
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate.clashFeatures.tunMode.autoRoute,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ModernSwitch(
            value: _tunAutoRoute,
            onChanged: (value) {
              setState(() => _tunAutoRoute = value);
              ClashManager.instance.setTunAutoRoute(value);
            },
          ),
        ],
      ),

      const SizedBox(height: 12),

      // 自动检测接口
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate.clashFeatures.tunMode.autoDetectInterface,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ModernSwitch(
            value: _tunAutoDetectInterface,
            onChanged: (value) {
              setState(() => _tunAutoDetectInterface = value);
              ClashManager.instance.setTunAutoDetectInterface(value);
            },
          ),
        ],
      ),

      const SizedBox(height: 12),

      // 严格路由
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate.clashFeatures.tunMode.strictRoute,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ModernSwitch(
            value: _tunStrictRoute,
            onChanged: (value) {
              setState(() => _tunStrictRoute = value);
              ClashManager.instance.setTunStrictRoute(value);
            },
          ),
        ],
      ),

      const SizedBox(height: 16),

      // DNS 劫持
      Row(
        children: [
          Text(
            context.translate.clashFeatures.tunMode.dnsHijack,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          SizedBox(
            width: 200,
            child: ModernTextField(
              controller: _tunDnsHijackController,
              hintText: 'any:53, tcp://any:53',
              height: 36,
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      // 自动重定向 (Linux only)
      if (Platform.isLinux) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.translate.clashFeatures.tunMode.autoRedirect,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.translate.clashFeatures.tunMode.autoRedirectDesc,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ModernSwitch(
              value: _tunAutoRedirect,
              onChanged: (value) {
                setState(() => _tunAutoRedirect = value);
                ClashManager.instance.setTunAutoRedirect(value);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],

      // 排除路由地址
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.translate.clashFeatures.tunMode.routeExcludeAddress,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context
                      .translate
                      .clashFeatures
                      .tunMode
                      .routeExcludeAddressDesc,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 200,
            child: ModernTextField(
              controller: _tunRouteExcludeAddressController,
              hintText: '172.20.0.0/16',
              height: 36,
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),

      // ICMP 转发（正向表述，开关打开=启用，关闭=禁用）
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.translate.clashFeatures.tunMode.icmpForwarding,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context.translate.clashFeatures.tunMode.icmpForwardingDesc,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ModernSwitch(
            // 反转显示：内部存储的是 disable，UI 显示的是 enable
            value: !_tunDisableIcmpForwarding,
            onChanged: (value) {
              // 反转存储：UI 的 enable 转换为内部的 disable
              setState(() => _tunDisableIcmpForwarding = !value);
              ClashManager.instance.setTunDisableIcmpForwarding(!value);
            },
          ),
        ],
      ),

      const SizedBox(height: 16),

      // 保存按钮
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveConfig,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(
              _isSaving
                  ? context.translate.tunConfig.saving
                  : context.translate.common.save,
            ),
          ),
        ],
      ),
    ];
  }
}
