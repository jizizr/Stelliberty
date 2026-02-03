import 'package:flutter/material.dart';

// 统一的下拉按钮组件：用于触发下拉菜单。
// 提供一致的外观与交互反馈。
class CustomDropdownButton extends StatelessWidget {
  final String text;
  final bool isHovering;
  final double? width;
  final double? height;

  const CustomDropdownButton({
    super.key,
    required this.text,
    required this.isHovering,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 使用 switch expression 和 record 来简化逻辑
    final (baseColor, alpha) = switch ((isDark, isHovering)) {
      (true, true) => (Colors.white, 35), // 暗色主题 + hover
      (true, false) => (Colors.white, 25), // 暗色主题
      (false, true) => (Colors.black, 20), // 亮色主题 + hover
      (false, false) => (Colors.black, 13), // 亮色主题
    };

    final backgroundColor = baseColor.withAlpha(alpha);

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          Transform.translate(
            offset: const Offset(0, -1),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
          ),
        ],
      ),
    );
  }
}
