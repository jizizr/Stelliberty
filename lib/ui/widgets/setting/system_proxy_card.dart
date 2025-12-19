import 'dart:io';
import 'package:flutter/material.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_dropdown_menu.dart';
import 'package:stelliberty/ui/common/modern_text_field.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';
import 'package:stelliberty/ui/widgets/modern_multiline_text_field.dart';
import 'package:stelliberty/ui/notifiers/system_proxy_notifier.dart';
import 'package:stelliberty/ui/widgets/modern_toast.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/utils/logger.dart';

// 系统代理配置卡片
class SystemProxyCard extends StatefulWidget {
  const SystemProxyCard({super.key});

  @override
  State<SystemProxyCard> createState() => _SystemProxyCardState();
}

class _SystemProxyCardState extends State<SystemProxyCard> {
  late SystemProxyNotifier _viewModel;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _viewModel = SystemProxyNotifier();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  String _getBypassHelperText() {
    final trans = context.translate;
    if (Platform.isWindows) {
      return trans.systemProxy.bypassHelper;
    } else if (Platform.isLinux) {
      return trans.systemProxy.bypassHelperLinux;
    } else if (Platform.isMacOS) {
      return trans.systemProxy.bypassHelperMac;
    } else {
      return trans.systemProxy.bypassHelper;
    }
  }

  // 保存配置
  Future<void> _saveConfig() async {
    final trans = context.translate;
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _viewModel.saveConfig();

      if (mounted) {
        ModernToast.success(context, trans.systemProxy.saveSuccess);
      }
    } catch (e) {
      Logger.error('保存系统代理配置失败: $e');
      if (mounted) {
        ModernToast.error(
          context,
          trans.systemProxy.saveFailed.replaceAll('{error}', e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trans = context.translate;

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return ModernFeatureCard(
          isSelected: false,
          onTap: () {},
          isHoverEnabled: false,
          isTapEnabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  const Icon(Icons.settings_ethernet_rounded),
                  const SizedBox(
                    width: ModernFeatureCardSpacing.featureIconToTextSpacing,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trans.systemProxy.configTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // 骨架屏或真实内容
              if (_viewModel.isLoading)
                _buildSkeleton(theme)
              else
                ..._buildRealContent(theme),
            ],
          ),
        );
      },
    );
  }

  // 构建骨架屏
  Widget _buildSkeleton(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 代理主机骨架
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                    100,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 80,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // PAC 模式开关骨架
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 12),
        // 绕过规则骨架
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  // 构建真实内容
  List<Widget> _buildRealContent(ThemeData theme) {
    final trans = context.translate;
    return [
      // 代理主机（输入框内嵌下拉按钮）
      ModernDropdownMenu<String>(
        items: _viewModel.availableHosts,
        selectedItem: _viewModel.selectedHost,
        onSelected: _viewModel.selectHost,
        itemToString: (host) => host,
        child: ModernTextField(
          controller: _viewModel.proxyHostController,
          labelText: trans.systemProxy.proxyHost,
          hintText: trans.systemProxy.proxyHostHint,
          helperText: trans.systemProxy.proxyHostHelper,
          shouldShowDropdownIcon: true,
        ),
      ),
      const SizedBox(height: 16),

      // PAC 模式开关
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trans.systemProxy.pacMode,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  trans.systemProxy.pacModeDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ModernSwitch(
            value: _viewModel.usePacMode,
            onChanged: _viewModel.togglePacMode,
          ),
        ],
      ),
      const SizedBox(height: 12),

      // 根据模式显示不同的配置
      if (!_viewModel.usePacMode) ...[
        // 使用默认绕过规则开关
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trans.systemProxy.useDefaultBypass,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trans.systemProxy.useDefaultBypassDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ModernSwitch(
              value: _viewModel.useDefaultBypass,
              onChanged: _viewModel.toggleUseDefaultBypass,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 绕过地址编辑器
        ModernMultilineTextField(
          controller: _viewModel.bypassController,
          labelText: trans.systemProxy.bypassLabel,
          helperText: _getBypassHelperText(),
          height: 120,
          enabled: !_viewModel.useDefaultBypass,
          contentPadding: const EdgeInsets.only(
            left: 10,
            right: 9,
            top: 2,
            bottom: 2,
          ),
          scrollbarRightPadding: 0.0,
        ),
      ] else ...[
        // PAC 脚本标签
        Text(
          trans.systemProxy.pacScriptLabel,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        // PAC 脚本编辑器
        ModernMultilineTextField(
          controller: _viewModel.pacScriptController,
          helperText: trans.systemProxy.pacScriptHelper,
          height: 250,
          contentPadding: const EdgeInsets.only(
            left: 10,
            right: 7,
            top: 2,
            bottom: 2,
          ),
          scrollbarRightPadding: 0.0,
        ),
        const SizedBox(height: 8),
        // 恢复默认按钮
        TextButton.icon(
          onPressed: _viewModel.restoreDefaultPacScript,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(trans.clashFeatures.testUrl.restoreDefault),
        ),
      ],

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
              _isSaving ? trans.systemProxy.saving : trans.common.save,
            ),
          ),
        ],
      ),
    ];
  }
}
