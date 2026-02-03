import 'package:flutter/material.dart';

// 通用基础卡片组件：统一圆角、边框、阴影与标题栏布局。
// 支持可选操作区与自定义内容区域。
class BaseCard extends StatelessWidget {
  // 卡片标题图标
  final IconData icon;

  // 卡片标题文字
  final String title;

  // 标题右侧的操作组件（可选）
  final Widget? trailing;

  // 卡片内容区域
  final Widget child;

  const BaseCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.1);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactLayout = screenWidth < 360;
    final contentPadding = isCompactLayout ? 16.0 : 24.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(contentPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_buildHeader(context), const SizedBox(height: 16), child],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final titleWidget = Transform.translate(
      offset: const Offset(0, -2),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    );

    final trailingWidget = trailing;
    if (trailingWidget == null) {
      return Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: titleWidget),
        ],
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrowHeader = screenWidth < 500;

    if (!isNarrowHeader) {
      return Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: titleWidget),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailingWidget,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: titleWidget),
          ],
        ),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: trailingWidget),
      ],
    );
  }
}
