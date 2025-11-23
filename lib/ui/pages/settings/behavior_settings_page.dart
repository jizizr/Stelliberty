import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/services/auto_start_service.dart';
import 'package:stelliberty/storage/preferences.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/utils/logger.dart';
import 'package:stelliberty/ui/widgets/setting/lazy_mode_card.dart';

// 应用行为设置页面
class BehaviorSettingsPage extends StatefulWidget {
  const BehaviorSettingsPage({super.key});

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  final _scrollController = ScrollController();

  // 直接从 AppPreferences 获取初始值
  bool _autoStartEnabled = AppPreferences.instance.getAutoStartEnabled();
  bool _silentStartEnabled = AppPreferences.instance.getSilentStartEnabled();
  bool _minimizeToTray = AppPreferences.instance.getMinimizeToTray();
  bool _appLogEnabled = AppPreferences.instance.getAppLogEnabled();

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 BehaviorSettingsPage');
    // 异步查询真实状态并更新
    _refreshStatus();
  }

  // 从 Rust 端刷新真实状态
  Future<void> _refreshStatus() async {
    final status = await AutoStartService.instance.getStatus();
    if (!mounted) return;

    setState(() {
      _autoStartEnabled = status;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context, listen: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 自定义标题栏
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    provider.switchView(ContentView.settingsOverview),
              ),
              const SizedBox(width: 8),
              Text(
                context.translate.behavior.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        // 可滚动内容
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 3.0, 5.0), // 统一滚动条边距
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 开机自启动卡片
                    _buildSwitchCard(
                      icon: Icons.power_settings_new_outlined,
                      title: context.translate.behavior.autoStartTitle,
                      subtitle: context.translate.behavior.autoStartDescription,
                      value: _autoStartEnabled,
                      onChanged: _updateAutoStartSetting,
                    ),

                    const SizedBox(height: 16),

                    // 静默启动卡片
                    _buildSwitchCard(
                      icon: Icons.visibility_off_outlined,
                      title: context.translate.behavior.silentStartTitle,
                      subtitle:
                          context.translate.behavior.silentStartDescription,
                      value: _silentStartEnabled,
                      onChanged: _updateSilentStartSetting,
                    ),

                    const SizedBox(height: 16),

                    // 最小化到托盘卡片
                    _buildSwitchCard(
                      icon: Icons.remove_circle_outline,
                      title: context.translate.behavior.minimizeToTrayTitle,
                      subtitle:
                          context.translate.behavior.minimizeToTrayDescription,
                      value: _minimizeToTray,
                      onChanged: _updateMinimizeToTraySetting,
                    ),

                    const SizedBox(height: 16),

                    // 应用日志卡片
                    _buildSwitchCard(
                      icon: Icons.description_outlined,
                      title: context.translate.behavior.appLogTitle,
                      subtitle: context.translate.behavior.appLogDescription,
                      value: _appLogEnabled,
                      onChanged: _updateAppLogSetting,
                    ),

                    const SizedBox(height: 16),

                    // 懒惰模式卡片
                    const LazyModeCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建带开关的卡片
  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ModernFeatureCard(
      isSelected: false,
      onTap: () {}, // 禁用整个卡片的点击
      enableHover: true,
      enableTap: false, // 禁用点击交互，只允许开关本身触发
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧图标和标题
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(153),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // 右侧开关
            ModernSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  // 更新开机自启动设置
  Future<void> _updateAutoStartSetting(bool value) async {
    // 乐观更新 UI
    setState(() {
      _autoStartEnabled = value;
    });

    final success = await AutoStartService.instance.setStatus(value);
    if (success) return;

    // 设置失败，恢复旧值
    if (!mounted) return;

    setState(() {
      _autoStartEnabled = !value;
    });
  }

  // 更新静默启动设置
  Future<void> _updateSilentStartSetting(bool value) async {
    // 更新 UI 和持久化
    setState(() {
      _silentStartEnabled = value;
    });

    await AppPreferences.instance.setSilentStartEnabled(value);

    Logger.info('静默启动已${value ? '启用' : '禁用'}');
  }

  // 更新最小化到托盘设置
  Future<void> _updateMinimizeToTraySetting(bool value) async {
    // 更新 UI 和持久化
    setState(() {
      _minimizeToTray = value;
    });

    await AppPreferences.instance.setMinimizeToTray(value);

    Logger.info('最小化到托盘已${value ? '启用' : '禁用'}');
  }

  // 更新应用日志设置
  Future<void> _updateAppLogSetting(bool value) async {
    final oldValue = _appLogEnabled;
    // 更新 UI
    setState(() {
      _appLogEnabled = value;
    });

    try {
      await AppPreferences.instance.setAppLogEnabled(value);
      Logger.info('应用日志已${value ? '启用' : '禁用'}');
    } catch (e) {
      // 持久化失败，回滚 UI 状态
      setState(() {
        _appLogEnabled = oldValue;
      });
      Logger.error('保存应用日志设置失败: $e');
    }
  }
}
