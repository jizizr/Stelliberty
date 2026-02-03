import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/atomic/platform_helper.dart';
import 'package:stelliberty/clash/providers/access_control_provider.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/state/access_control_states.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/constants/spacing.dart';
import 'package:stelliberty/ui/widgets/modern_toast.dart';

// 应用访问控制设置页面
// 仅 Android 平台可用
class AccessControlSettingsPage extends StatefulWidget {
  const AccessControlSettingsPage({super.key});

  @override
  State<AccessControlSettingsPage> createState() =>
      _AccessControlSettingsPageState();
}

class _AccessControlSettingsPageState extends State<AccessControlSettingsPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 加载应用列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AccessControlProvider>();
      if (provider.installedApps.isEmpty) {
        provider.loadInstalledApps();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 显示 VPN 重启提示（如果 VPN 正在运行）
  void _showRestartHintIfNeeded() {
    final clashProvider = context.read<ClashProvider>();
    if (clashProvider.isAndroidVpnEnabled) {
      final trans = context.translate;
      ModernToast.info(trans.access_control.restart_vpn_hint);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentProvider = Provider.of<ContentProvider>(
      context,
      listen: false,
    );
    final trans = context.translate;

    // 非 Android 平台不显示
    if (!PlatformHelper.isMobile) {
      return Center(child: Text(trans.access_control.title));
    }

    return Consumer<AccessControlProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => contentProvider.switchView(
                      ContentView.settingsClashFeatures,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trans.access_control.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: Padding(
                padding: SpacingConstants.scrollbarPadding,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16 - SpacingConstants.scrollbarRightCompensation,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 模式选择
                      _buildModeSelector(context, provider, trans),
                      const SizedBox(height: 16),
                      // 白名单为空警告
                      if (provider.mode == AccessControlMode.whitelist &&
                          provider.selectedCount == 0)
                        _buildWarningBanner(
                          context,
                          trans.access_control.whitelist_empty_warning,
                        ),
                      // 应用列表（仅在非禁用模式下显示）
                      if (provider.mode != AccessControlMode.disabled) ...[
                        _buildAppListSection(context, provider, trans),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 构建模式选择器
  Widget _buildModeSelector(
    BuildContext context,
    AccessControlProvider provider,
    Translations trans,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModeCard(
          context: context,
          icon: Icons.block_outlined,
          title: trans.access_control.mode_disabled,
          subtitle: trans.access_control.mode_disabled_desc,
          isSelected: provider.mode == AccessControlMode.disabled,
          onTap: () {
            provider.updateMode(AccessControlMode.disabled);
            _showRestartHintIfNeeded();
          },
        ),
        const SizedBox(height: 8),
        _buildModeCard(
          context: context,
          icon: Icons.check_circle_outline,
          title: trans.access_control.mode_whitelist,
          subtitle: trans.access_control.mode_whitelist_desc,
          isSelected: provider.mode == AccessControlMode.whitelist,
          onTap: () {
            provider.updateMode(AccessControlMode.whitelist);
            _showRestartHintIfNeeded();
          },
        ),
        const SizedBox(height: 8),
        _buildModeCard(
          context: context,
          icon: Icons.cancel_outlined,
          title: trans.access_control.mode_blacklist,
          subtitle: trans.access_control.mode_blacklist_desc,
          isSelected: provider.mode == AccessControlMode.blacklist,
          onTap: () {
            provider.updateMode(AccessControlMode.blacklist);
            _showRestartHintIfNeeded();
          },
        ),
      ],
    );
  }

  // 构建模式卡片
  Widget _buildModeCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ModernFeatureCard(
      isSelected: isSelected,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(
            width: ModernFeatureCardSpacing.featureIconToTextSpacing,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
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
          ),
          if (isSelected)
            Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }

  // 构建警告横幅
  Widget _buildWarningBanner(BuildContext context, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  // 构建应用列表区域
  Widget _buildAppListSection(
    BuildContext context,
    AccessControlProvider provider,
    Translations trans,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索栏和操作按钮
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: trans.access_control.search_apps,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                onChanged: provider.updateSearchQuery,
              ),
            ),
            const SizedBox(width: 8),
            // 显示系统应用开关
            FilterChip(
              label: Text(trans.access_control.show_system_apps),
              selected: provider.showSystemApps,
              onSelected: (_) => provider.toggleShowSystemApps(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 选择操作按钮
        Row(
          children: [
            Text(
              trans.access_control.selected_count(
                count: provider.selectedCount,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                provider.selectAll();
                _showRestartHintIfNeeded();
              },
              child: Text(trans.access_control.select_all),
            ),
            TextButton(
              onPressed: () {
                provider.deselectAll();
                _showRestartHintIfNeeded();
              },
              child: Text(trans.access_control.deselect_all),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 应用列表
        if (provider.isLoadingApps)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(trans.access_control.loading_apps),
                ],
              ),
            ),
          )
        else if (provider.filteredApps.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(trans.access_control.no_apps),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: provider.filteredApps.length,
            itemBuilder: (context, index) {
              final app = provider.filteredApps[index];
              return _AppListTile(
                app: app,
                isSelected: provider.isPackageSelected(app.packageName),
                onToggle: () {
                  provider.togglePackage(app.packageName);
                  _showRestartHintIfNeeded();
                },
                getIcon: () => provider.getAppIcon(app.packageName),
              );
            },
          ),
      ],
    );
  }
}

// 应用列表项
class _AppListTile extends StatefulWidget {
  final AppInfo app;
  final bool isSelected;
  final VoidCallback onToggle;
  final Future<Uint8List?> Function() getIcon;

  const _AppListTile({
    required this.app,
    required this.isSelected,
    required this.onToggle,
    required this.getIcon,
  });

  @override
  State<_AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<_AppListTile> {
  Uint8List? _iconData;
  bool _iconLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant _AppListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果应用变化了，重新加载图标
    if (oldWidget.app.packageName != widget.app.packageName) {
      _iconLoaded = false;
      _iconData = null;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final icon = await widget.getIcon();
    if (mounted) {
      setState(() {
        _iconData = icon;
        _iconLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trans = context.translate;

    return ListTile(
      leading: _buildIcon(),
      title: Text(
        widget.app.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.app.packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
            ),
          ),
          Row(
            children: [
              if (widget.app.isSystem) ...[
                _buildTag(trans.access_control.system_app, Colors.orange),
                const SizedBox(width: 4),
              ],
              if (widget.app.hasInternet)
                _buildTag(trans.access_control.has_internet, Colors.green),
            ],
          ),
        ],
      ),
      trailing: Checkbox(
        value: widget.isSelected,
        onChanged: (_) => widget.onToggle(),
      ),
      onTap: widget.onToggle,
    );
  }

  Widget _buildIcon() {
    if (!_iconLoaded) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_iconData != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _iconData!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.android, size: 24),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
