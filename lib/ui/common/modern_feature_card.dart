import 'package:flutter/material.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';

// 现代特性卡片的间距常量
class ModernFeatureCardSpacing {
  // 卡片水平内边距
  static const double cardHorizontalPadding = 25.0;

  // 卡片垂直内边距
  static const double cardVerticalPadding = 20.0;

  // 特性图标和文字之间的间距（最左侧图标到标题文本）
  static const double featureIconToTextSpacing = 16.0;

  // 辅助特性图标和右侧控件之间的间距（如更新按钮到开关）
  static const double auxiliaryIconToControlSpacing = 16.0;
}

// 特性卡片容器：带动画与描边效果的通用卡片。
// 支持选中态样式与可选的悬停/点击控制。
class ModernFeatureCard extends StatelessWidget {
  // 卡片内部的子组件。
  final Widget child;

  // 卡片是否处于选中状态。
  final bool isSelected;

  // 点击卡片时的回调函数。
  final VoidCallback onTap;

  // 卡片的圆角半径。
  final double borderRadius;

  // 是否启用悬停效果。
  final bool isHoverEnabled;

  // 是否启用点击效果（包括水波纹和 onTap 回调）。
  final bool isTapEnabled;

  // 卡片内边距（默认使用标准间距）
  final EdgeInsets? padding;

  const ModernFeatureCard({
    super.key,
    required this.child,
    required this.isSelected,
    required this.onTap,
    this.borderRadius = 12.0,
    this.isHoverEnabled = true,
    this.isTapEnabled = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 使用 switch expression 简化颜色选择
    final backgroundColor = switch (isSelected) {
      true => theme.colorScheme.primary.withAlpha(38),
      false => theme.colorScheme.surface.withAlpha(153),
    };

    final borderColor = switch (isSelected) {
      true => theme.colorScheme.primary.withAlpha(150),
      false => theme.colorScheme.outline.withAlpha(80),
    };

    final hoverColor = switch (isHoverEnabled) {
      true => theme.colorScheme.primary.withAlpha(20),
      false => Colors.transparent,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: switch (isTapEnabled) {
        true => Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onTap,
            hoverColor: hoverColor,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding:
                  padding ??
                  const EdgeInsets.symmetric(
                    horizontal: ModernFeatureCardSpacing.cardHorizontalPadding,
                    vertical: ModernFeatureCardSpacing.cardVerticalPadding,
                  ),
              child: child,
            ),
          ),
        ),
        false => Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(
                horizontal: ModernFeatureCardSpacing.cardHorizontalPadding,
                vertical: ModernFeatureCardSpacing.cardVerticalPadding,
              ),
          child: child,
        ),
      },
    );
  }
}

// 统一布局的特性卡片：图标 + 标题/描述 + 右侧控件。
// 用于构建一致的设置项行布局。
class ModernFeatureLayoutCard extends StatelessWidget {
  // 左侧图标（可选）
  final IconData? icon;

  // 标题文本
  final String title;

  // 描述文本（可选）
  final String? subtitle;

  // 右侧控件（可以是开关、下拉框、图标、输入框等）
  final Widget? trailing;

  // 右侧控件左边的按钮（可选，通常用于开关左边的更新按钮）
  final Widget? trailingLeadingButton;

  // 卡片内边距
  final EdgeInsets? padding;

  // 图标大小
  final double? iconSize;

  // 图标颜色
  final Color? iconColor;

  // 是否启用悬停效果
  final bool isHoverEnabled;

  // 是否启用点击效果
  final bool isTapEnabled;

  // 点击事件
  final VoidCallback? onTap;

  const ModernFeatureLayoutCard({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingLeadingButton,
    this.padding,
    this.iconSize,
    this.iconColor,
    this.isHoverEnabled = true,
    this.isTapEnabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ModernFeatureCard(
      isSelected: false,
      onTap: onTap ?? () {},
      isHoverEnabled: isHoverEnabled,
      isTapEnabled: isTapEnabled,
      padding: padding,
      child: Row(
        children: [
          // 左侧：图标 + 标题 + 描述
          if (icon != null) ...[
            Icon(icon, size: iconSize ?? 24, color: iconColor),
            const SizedBox(
              width: ModernFeatureCardSpacing.featureIconToTextSpacing,
            ),
          ],

          // 标题和描述
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),

          // 右侧：可选的前导按钮 + 控件
          if (trailingLeadingButton != null || trailing != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailingLeadingButton != null) ...[
                  trailingLeadingButton!,
                  const SizedBox(
                    width:
                        ModernFeatureCardSpacing.auxiliaryIconToControlSpacing,
                  ),
                ],
                ?trailing,
              ],
            ),
        ],
      ),
    );
  }
}

// 简单的切换特性卡片：图标 + 标题/描述 + 开关。
class ModernFeatureToggleCard extends StatelessWidget {
  // 左侧图标
  final IconData icon;

  // 标题文本
  final String title;

  // 描述文本
  final String subtitle;

  // 开关状态
  final bool value;

  // 开关状态变化回调
  final ValueChanged<bool> onChanged;

  // 卡片内边距
  final EdgeInsets? padding;

  const ModernFeatureToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ModernFeatureCard(
      isSelected: false,
      onTap: () {},
      isHoverEnabled: true,
      isTapEnabled: false,
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧图标和标题
          Row(
            children: [
              Icon(icon),
              const SizedBox(
                width: ModernFeatureCardSpacing.featureIconToTextSpacing,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
          // 右侧开关
          ModernSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
