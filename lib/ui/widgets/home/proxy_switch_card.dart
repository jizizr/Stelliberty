import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/providers/access_control_provider.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/providers/subscription_provider.dart';
import 'package:stelliberty/ui/widgets/home/base_card.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 系统代理卡片：提供系统代理开关能力。
// 同步状态到核心与界面。
class ProxySwitchCard extends StatelessWidget {
  const ProxySwitchCard({super.key});

  // 获取启动按钮背景色
  // 夜间主题时添加黑色 25% 遮罩
  Color _getStartButtonColor(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    if (isDark) {
      // 夜间主题：在主色上叠加 25% 黑色遮罩
      return Color.alphaBlend(
        Colors.black.withValues(alpha: 0.25),
        primaryColor,
      );
    }
    return primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final trans = context.translate;

    if (Platform.isAndroid) {
      return Consumer3<
        ClashProvider,
        SubscriptionProvider,
        AccessControlProvider
      >(
        builder:
            (
              context,
              clashProvider,
              subscriptionProvider,
              accessControlProvider,
              child,
            ) {
              final isVpnEnabled = clashProvider.isAndroidVpnEnabled;
              final configPath = subscriptionProvider
                  .getSubscriptionConfigPath();
              final accessControl = accessControlProvider.config;

              return BaseCard(
                icon: Icons.vpn_lock,
                title: trans.home.vpn_mode_switch,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isVpnEnabled ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isVpnEnabled
                            ? trans.home.vpn_enabled
                            : trans.home.vpn_disabled,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isVpnEnabled ? Colors.green : Colors.grey,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        if (isVpnEnabled) {
                          await clashProvider.stopAndroidVpn();
                        } else {
                          await clashProvider.startAndroidVpn(
                            configPath: configPath,
                            accessControl: accessControl,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isVpnEnabled
                            ? Colors.red.shade400
                            : _getStartButtonColor(context),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: Text(
                        isVpnEnabled
                            ? trans.home.disable_vpn
                            : trans.home.enable_vpn,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
      );
    }

    return Selector<ClashProvider, ({bool isCoreRunning, bool isProxyEnabled})>(
      selector: (_, provider) => (
        isCoreRunning: provider.isCoreRunning,
        isProxyEnabled: provider.isSystemProxyEnabled,
      ),
      builder: (context, state, child) {
        final isCoreRunning = state.isCoreRunning;
        final isProxyEnabled = state.isProxyEnabled;

        return BaseCard(
          icon: Icons.shield_outlined,
          title: trans.proxy.proxy_control,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isProxyEnabled ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isProxyEnabled ? trans.proxy.running : trans.proxy.stopped,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isProxyEnabled ? Colors.green : Colors.grey,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 代理开关按钮
              ElevatedButton(
                onPressed: !isCoreRunning
                    ? null
                    : () async {
                        final provider = context.read<ClashProvider>();
                        if (isProxyEnabled) {
                          await provider.disableSystemProxy();
                        } else {
                          await provider.enableSystemProxy();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isProxyEnabled
                      ? Colors.red.shade400
                      : _getStartButtonColor(context),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(
                  isProxyEnabled
                      ? trans.proxy.stop_proxy
                      : trans.proxy.start_proxy,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
