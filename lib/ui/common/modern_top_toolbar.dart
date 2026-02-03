import 'package:flutter/material.dart';
import 'package:stelliberty/ui/widgets/modern_tooltip.dart';

class ModernTopToolbarTokens {
  ModernTopToolbarTokens._();

  static const double radius = 12;
  static const double chipRadius = 10;
  static const double controlHeight = 38;

  static final BorderRadius borderRadius = BorderRadius.circular(radius);
  static final BorderRadius chipBorderRadius = BorderRadius.circular(
    chipRadius,
  );
}

// 现代顶部工具栏
class ModernTopToolbar extends StatelessWidget {
  const ModernTopToolbar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: children),
    );
  }
}

// 搜索框
class ModernTopToolbarSearchField extends StatelessWidget {
  const ModernTopToolbarSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.prefixIcon = Icons.search_rounded,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final IconData prefixIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: ModernTopToolbarTokens.controlHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            prefixIcon,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: ModernTopToolbarTokens.borderRadius,
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// 过滤按钮组
class ModernTopToolbarChipGroup extends StatelessWidget {
  const ModernTopToolbarChipGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: ModernTopToolbarTokens.borderRadius,
      ),
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class ModernTopToolbarChip extends StatelessWidget {
  const ModernTopToolbarChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: ModernTopToolbarTokens.chipBorderRadius,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// 操作按钮组
class ModernTopToolbarActionGroup extends StatelessWidget {
  const ModernTopToolbarActionGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: ModernTopToolbarTokens.borderRadius,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class ModernTopToolbarIconButton extends StatelessWidget {
  const ModernTopToolbarIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.iconSize = 20,
    this.size = ModernTopToolbarTokens.controlHeight,
    this.borderRadius = ModernTopToolbarTokens.chipRadius,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ModernTooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: iconSize,
          style: IconButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
              alpha: 0.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: ModernTopToolbarTokens.chipBorderRadius,
            ),
          ),
        ),
      ),
    );
  }
}

RoundedRectangleBorder modernTopToolbarButtonShape([double? radius]) {
  return RoundedRectangleBorder(
    borderRadius: radius != null
        ? BorderRadius.circular(radius)
        : ModernTopToolbarTokens.borderRadius,
  );
}

RoundedRectangleBorder modernOperationButtonShape([double? radius]) {
  return modernTopToolbarButtonShape(radius);
}
