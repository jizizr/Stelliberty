import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/ui/widgets/home/base_card.dart';
import 'package:stelliberty/utils/logger.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 出站模式卡片
//
// 提供规则模式、全局模式、直连模式切换
class OutboundModeCard extends StatefulWidget {
  const OutboundModeCard({super.key});

  @override
  State<OutboundModeCard> createState() => _OutboundModeCardState();
}

class _OutboundModeCardState extends State<OutboundModeCard> {
  String _selectedMode = 'rule';

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
    // 监听 ClashManager 状态变化
    ClashManager.instance.addListener(_onClashManagerChanged);
  }

  @override
  void dispose() {
    // 移除监听器，防止内存泄漏
    ClashManager.instance.removeListener(_onClashManagerChanged);
    super.dispose();
  }

  // ClashManager 状态变化回调
  void _onClashManagerChanged() {
    if (mounted) {
      final currentMode = ClashManager.instance.mode;
      if (_selectedMode != currentMode) {
        setState(() {
          _selectedMode = currentMode;
        });
        Logger.debug('主页出站模式卡片已同步到: $currentMode');
      }
    }
  }

  Future<void> _loadCurrentMode() async {
    try {
      final mode = ClashManager.instance.mode;
      if (mounted) {
        setState(() {
          _selectedMode = mode;
        });
      }
    } catch (e) {
      Logger.warning('获取当前模式失败: $e，使用默认值');
      if (mounted) {
        setState(() {
          _selectedMode = 'rule';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clashProvider = context.watch<ClashProvider>();
    final isRunning = clashProvider.isRunning;
    final isLoading = clashProvider.isLoading;

    return BaseCard(
      icon: Icons.alt_route_rounded,
      title: context.translate.proxy.outboundMode,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModeOption(
            context,
            icon: Icons.rule_rounded,
            title: context.translate.proxy.ruleMode,
            mode: 'rule',
            isRunning: isRunning,
            isLoading: isLoading,
          ),

          const SizedBox(height: 8),

          _buildModeOption(
            context,
            icon: Icons.public_rounded,
            title: context.translate.proxy.globalMode,
            mode: 'global',
            isRunning: isRunning,
            isLoading: isLoading,
          ),

          const SizedBox(height: 8),

          _buildModeOption(
            context,
            icon: Icons.phonelink_rounded,
            title: context.translate.proxy.directMode,
            mode: 'direct',
            isRunning: isRunning,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String mode,
    required bool isRunning,
    required bool isLoading,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedMode == mode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (!isLoading && !isSelected)
            ? () => _switchOutboundMode(context, mode, isRunning)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.primary.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchOutboundMode(
    BuildContext context,
    String mode,
    bool isRunning,
  ) async {
    Logger.info('用户切换出站模式: $mode (核心运行: $isRunning)');

    setState(() {
      _selectedMode = mode;
    });

    try {
      if (isRunning) {
        final success = await ClashManager.instance.setMode(mode);

        if (context.mounted) {
          if (!success) {
            await _loadCurrentMode();
          }
        }
      } else {
        final success = await ClashManager.instance.setModeOffline(mode);

        if (context.mounted) {
          if (!success) {
            await _loadCurrentMode();
          }
        }
      }
    } catch (e) {
      Logger.error('切换出站模式失败: $e');
      await _loadCurrentMode();
    }
  }
}
