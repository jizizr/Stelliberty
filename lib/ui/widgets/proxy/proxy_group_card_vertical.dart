import 'package:flutter/material.dart';
import 'package:stelliberty/clash/data/clash_model.dart';
import 'package:stelliberty/ui/widgets/proxy/proxy_node_card.dart';
import 'package:stelliberty/ui/notifiers/proxy_notifier.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 竖向模式的代理组折叠卡片
class ProxyGroupCardVertical extends StatelessWidget {
  final ProxyGroup group;
  final bool isExpanded;
  final int columns;
  final VoidCallback onToggle;
  final Function(String proxyName) onSelectProxy;
  final Function(String proxyName) onTestDelay;
  final bool isCoreRunning;
  final Map<String, dynamic> proxyNodes;
  final ProxyNotifier viewModel;
  final VoidCallback? onLocate;
  final Map<String, GlobalKey>? nodeKeys;

  const ProxyGroupCardVertical({
    super.key,
    required this.group,
    required this.isExpanded,
    required this.columns,
    required this.onToggle,
    required this.onSelectProxy,
    required this.onTestDelay,
    required this.isCoreRunning,
    required this.proxyNodes,
    required this.viewModel,
    this.onLocate,
    this.nodeKeys,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, theme, colorScheme),
          if (isExpanded) _buildContent(context),
        ],
      ),
    );
  }

  // 构建卡片头部
  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final currentNode = group.now ?? context.translate.proxy.notSelected;
    final nodeCount = group.all.length;
    final hasSelectedNode = group.now != null && group.now!.isNotEmpty;

    // 按钮样式常量
    const double buttonSize = 32.0;
    const double iconSize = 20.0;
    const double backgroundAlpha = 0.3;
    const double hoverAlpha = 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 代理组信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 代理组名称
                Text(
                  group.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // 当前选中节点
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        currentNode,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '($nodeCount ${context.translate.proxy.nodes})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 定位按钮（只在有选中节点且展开时显示）
          if (hasSelectedNode && isExpanded && onLocate != null) ...[
            IconButton(
              constraints: const BoxConstraints(
                minWidth: buttonSize,
                minHeight: buttonSize,
                maxWidth: buttonSize,
                maxHeight: buttonSize,
              ),
              padding: EdgeInsets.zero,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return colorScheme.surfaceContainerHighest.withValues(
                      alpha: hoverAlpha,
                    );
                  }
                  return colorScheme.surfaceContainerHighest.withValues(
                    alpha: backgroundAlpha,
                  );
                }),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              onPressed: onLocate,
              icon: Icon(
                Icons.gps_fixed,
                size: iconSize,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 展开/收起按钮
          IconButton(
            constraints: const BoxConstraints(
              minWidth: buttonSize,
              minHeight: buttonSize,
              maxWidth: buttonSize,
              maxHeight: buttonSize,
            ),
            padding: EdgeInsets.zero,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.surfaceContainerHighest.withValues(
                    alpha: hoverAlpha,
                  );
                }
                return colorScheme.surfaceContainerHighest.withValues(
                  alpha: backgroundAlpha,
                );
              }),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            onPressed: onToggle,
            icon: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 24,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // 构建卡片内容（节点列表）
  Widget _buildContent(BuildContext context) {
    // 应用排序（只排序节点，不排序代理组）
    final nodeNames = viewModel.getSortedProxyNames(group.all);

    if (nodeNames.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            context.translate.proxy.noNodes,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每个卡片的宽度
        const double spacing = 12.0;
        final double cardWidth =
            (constraints.maxWidth - (columns - 1) * spacing - 32) / columns;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: nodeNames.map((nodeName) {
              final node = proxyNodes[nodeName];

              // 如果节点信息不可用，跳过
              if (node == null) {
                return const SizedBox.shrink();
              }

              final isSelected = nodeName == group.now;

              // 为选中的节点获取或创建 GlobalKey
              final nodeKey = '${group.name}_$nodeName';
              GlobalKey? key;
              if (isSelected && nodeKeys != null) {
                nodeKeys!.putIfAbsent(nodeKey, () => GlobalKey());
                key = nodeKeys![nodeKey];
              }

              // 创建节点卡片
              Widget nodeCard = SizedBox(
                width: cardWidth,
                height: 88.0,
                child: ProxyNodeCard(
                  node: node,
                  isSelected: isSelected,
                  onTap: () => onSelectProxy(nodeName),
                  onTestDelay: () async => onTestDelay(nodeName),
                  isClashRunning: isCoreRunning,
                ),
              );

              // 为选中的节点添加 key，方便定位
              if (isSelected && key != null) {
                nodeCard = Container(key: key, child: nodeCard);
              }

              return nodeCard;
            }).toList(),
          ),
        );
      },
    );
  }
}
