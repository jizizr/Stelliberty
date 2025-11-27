import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/ui/widgets/home/base_card.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 代理控制卡片
//
// 提供系统代理开关功能
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
    final clashProvider = context.watch<ClashProvider>();
    final clashManager = context.watch<ClashManager>();
    final isRunning = clashProvider.isRunning;
    final isProxyEnabled = clashManager.isSystemProxyEnabled;
    final isLoading = clashProvider.isLoading;

    return BaseCard(
      icon: Icons.shield_outlined,
      title: context.translate.proxy.proxyControl,
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
          Text(
            isProxyEnabled
                ? context.translate.proxy.running
                : context.translate.proxy.stopped,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isProxyEnabled ? Colors.green : Colors.grey,
              fontSize: 13,
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
            onPressed: (isLoading || !isRunning)
                ? null
                : () async {
                    try {
                      if (isProxyEnabled) {
                        await clashProvider.disableSystemProxy();
                      } else {
                        await clashProvider.enableSystemProxy();
                      }
                    } catch (e) {
                      // 错误已经在 Provider 中记录
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
                  ? context.translate.proxy.stopProxy
                  : context.translate.proxy.startProxy,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
