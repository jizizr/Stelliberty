import 'package:flutter/material.dart';
import 'package:stelliberty/storage/clash_preferences.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 懒惰模式配置卡片 - 适配应用行为页面风格
class LazyModeCard extends StatefulWidget {
  const LazyModeCard({super.key});

  @override
  State<LazyModeCard> createState() => _LazyModeCardState();
}

class _LazyModeCardState extends State<LazyModeCard> {
  bool _lazyMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final prefs = ClashPreferences.instance;
    setState(() {
      _lazyMode = prefs.getLazyMode();
    });
  }

  Future<void> _toggleLazyMode(bool value) async {
    final previousValue = _lazyMode;
    setState(() {
      _lazyMode = value;
    });

    try {
      await ClashPreferences.instance.setLazyMode(value);
      Logger.info('懒惰模式已${value ? '启用' : '禁用'}');
    } catch (e) {
      // 持久化失败，回滚 UI 状态
      setState(() {
        _lazyMode = previousValue;
      });
      Logger.error('保存懒惰模式设置失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModernFeatureCard(
      isSelected: false,
      onTap: () {}, // 禁用整个卡片的点击
      isHoverEnabled: true,
      isTapEnabled: false, // 禁用点击交互，只允许开关本身触发
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧图标
          const Icon(Icons.bedtime_rounded),
          const SizedBox(
            width: ModernFeatureCardSpacing.featureIconToTextSpacing,
          ),
          // 中间标题和描述（Expanded 确保自适应宽度）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context
                      .translate
                      .clash_features
                      .system_integration
                      .lazy_mode
                      .title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  context
                      .translate
                      .clash_features
                      .system_integration
                      .lazy_mode
                      .subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(153),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧开关
          ModernSwitch(value: _lazyMode, onChanged: _toggleLazyMode),
        ],
      ),
    );
  }
}
