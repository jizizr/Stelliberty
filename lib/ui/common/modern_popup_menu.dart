import 'package:flutter/material.dart';

// 弹出菜单样式配置常量
class _PopupMenuStyle {
  // 菜单容器上下内边距（第一个项目距上和最后一个项目距下）
  static const double menuVerticalPadding = 8.0;

  // 项目之间的间距（相邻两个项目之间的实际距离）
  static const double itemGap = 7.0;

  // 菜单项距容器左右边缘的间距
  static const double itemHorizontalSpacing = 8.0;

  // 菜单项内容的左右内边距
  static const double itemContentHorizontalPadding = 14.0;

  // 菜单项内容的上下内边距
  static const double itemContentVerticalPadding = 12.0;

  // 菜单容器圆角半径
  static const double menuBorderRadius = 10.0;

  // 菜单项圆角半径
  static const double itemBorderRadius = 6.0;

  // 分割线左右间距
  static const double dividerHorizontalSpacing = 6.0;
}

// 弹出菜单项数据模型
// 定义菜单项的基本属性：图标、文本、回调和危险标识
class PopupMenuItemData {
  const PopupMenuItemData({
    this.icon,
    required this.label,
    required this.onPressed,
    this.isDangerous = false,
    this.closeOnTap = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isDangerous;
  final bool closeOnTap;
}

// 现代化弹出路由：提供弹出动画与回弹曲线。
// 内置智能定位，避免菜单溢出屏幕边界。
class ModernPopupRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final ValueNotifier<Offset> offsetNotifier;

  ModernPopupRoute({
    required this.barrierLabel,
    required this.builder,
    required this.offsetNotifier,
  });

  @override
  String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const align = Alignment.topRight;
    final curveAnimation = animation
        .drive(Tween(begin: 0.0, end: 1.0))
        .drive(CurveTween(curve: Curves.easeOutBack));
    return SafeArea(
      child: ValueListenableBuilder(
        valueListenable: offsetNotifier,
        builder: (_, value, child) {
          return Align(
            alignment: align,
            child: CustomSingleChildLayout(
              delegate: OverflowAwareLayoutDelegate(
                offset: value.translate(48, -8),
              ),
              child: child,
            ),
          );
        },
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, child) {
            return FadeTransition(
              opacity: curveAnimation,
              child: ScaleTransition(
                alignment: align,
                scale: curveAnimation,
                child: SlideTransition(
                  position: curveAnimation.drive(
                    Tween(begin: const Offset(0, -0.02), end: Offset.zero),
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: builder(context),
        ),
      ),
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);
}

// 智能定位委托：防止菜单超出屏幕边界。
// 自动调整位置并保留安全边距。
class OverflowAwareLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset offset;

  OverflowAwareLayoutDelegate({required this.offset});

  @override
  Size getSize(BoxConstraints constraints) {
    return Size(constraints.maxWidth, constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const safeOffset = Offset(16, 16);
    double x = (offset.dx - childSize.width).clamp(
      0,
      size.width - safeOffset.dx - childSize.width,
    );
    double y = (offset.dy).clamp(
      0,
      size.height - safeOffset.dy - childSize.height,
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant OverflowAwareLayoutDelegate oldDelegate) {
    return oldDelegate.offset != offset;
  }
}

// 弹出菜单容器：桥接触发器与弹出内容。
// 自动跟踪触发器位置变化并更新偏移。
typedef PopupOpen = Function({Offset offset});

class ModernPopupBox extends StatefulWidget {
  final Widget Function(PopupOpen open) targetBuilder;
  final Widget popup;

  const ModernPopupBox({
    super.key,
    required this.targetBuilder,
    required this.popup,
  });

  @override
  State<ModernPopupBox> createState() => _ModernPopupBoxState();
}

class _ModernPopupBoxState extends State<ModernPopupBox> {
  bool _isOpen = false;
  // 缓存 ValueNotifier 避免每次 build 重建
  late final ValueNotifier<Offset> _targetOffsetValueNotifier;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _targetOffsetValueNotifier = ValueNotifier<Offset>(Offset.zero);
  }

  @override
  void dispose() {
    _targetOffsetValueNotifier.dispose();
    super.dispose();
  }

  // 打开弹出菜单
  void _open({Offset offset = Offset.zero}) {
    _offset = offset;
    _updateOffset();
    _isOpen = true;
    Navigator.of(context)
        .push(
          ModernPopupRoute(
            barrierLabel: 'popup_menu',
            builder: (BuildContext context) {
              return widget.popup;
            },
            offsetNotifier: _targetOffsetValueNotifier,
          ),
        )
        .then((_) {
          _isOpen = false;
        });
  }

  // 更新菜单位置（响应布局变化）
  void _updateOffset() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final viewPadding = MediaQuery.of(context).viewPadding;
    _targetOffsetValueNotifier.value = renderBox
        .localToGlobal(
          Offset.zero.translate(viewPadding.right, viewPadding.top),
        )
        .translate(_offset.dx, _offset.dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isOpen) {
            _updateOffset();
          }
        });
        return widget.targetBuilder(_open);
      },
    );
  }
}

// 现代化弹出菜单组件：提供更一致的交互与视觉样式。
// 内置禁用态、危险态与自动分页逻辑。
class ModernPopupMenu extends StatefulWidget {
  final List<PopupMenuItemData> items;
  final double minWidth;
  final double minItemVerticalPadding;
  final double fontSize;
  final String? moreOptionsLabel;

  const ModernPopupMenu({
    super.key,
    required this.items,
    this.minWidth = 220,
    this.minItemVerticalPadding = 16,
    this.fontSize = 15,
    this.moreOptionsLabel,
  });

  @override
  State<ModernPopupMenu> createState() => _ModernPopupMenuState();
}

class _ModernPopupMenuState extends State<ModernPopupMenu> {
  int _currentPage = 0;

  // 构建菜单项：支持禁用态、危险态与点击关闭策略。
  // 由 `closeOnTap` 决定是否先关闭菜单再执行回调。
  Widget _popupMenuItem(
    BuildContext context, {
    required PopupMenuItemData item,
    required int index,
  }) {
    final onPressed = item.onPressed;
    final disabled = onPressed == null;
    final colorScheme = Theme.of(context).colorScheme;
    final color = item.isDangerous ? colorScheme.error : colorScheme.onSurface;
    final foregroundColor = disabled ? color.withValues(alpha: 0.3) : color;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _PopupMenuStyle.itemHorizontalSpacing,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed != null
              ? () {
                  // 根据 closeOnTap 决定是否关闭菜单
                  // 分页导航按钮不关闭菜单
                  if (item.closeOnTap) {
                    Navigator.of(context).pop();
                  }
                  onPressed();
                }
              : null,
          borderRadius: BorderRadius.circular(_PopupMenuStyle.itemBorderRadius),
          splashFactory: InkRipple.splashFactory,
          hoverColor: item.isDangerous
              ? colorScheme.error.withValues(alpha: 0.1)
              : null,
          child: Container(
            constraints: BoxConstraints(minWidth: widget.minWidth - 16),
            padding: const EdgeInsets.symmetric(
              horizontal: _PopupMenuStyle.itemContentHorizontalPadding,
              vertical: _PopupMenuStyle.itemContentVerticalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                _PopupMenuStyle.itemBorderRadius,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: widget.fontSize + 2,
                    color: foregroundColor,
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: widget.fontSize - 1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 获取当前页显示的菜单项
  List<PopupMenuItemData> _getCurrentPageItems() {
    final totalItems = widget.items.length;

    // 不超过 6 项，直接显示全部
    if (totalItems <= 6) {
      return widget.items;
    }

    // 第一页：前 5 项 + "更多选项"
    if (_currentPage == 0) {
      final firstPageItems = widget.items.take(5).toList();
      firstPageItems.add(
        PopupMenuItemData(
          icon: Icons.more_horiz,
          label: widget.moreOptionsLabel ?? '更多选项',
          closeOnTap: false,
          onPressed: () {
            setState(() {
              _currentPage = 1;
            });
          },
        ),
      );
      return firstPageItems;
    }

    // 第二页：显示剩余项
    return widget.items.skip(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final displayItems = _getCurrentPageItems();

    return IntrinsicHeight(
      child: IntrinsicWidth(
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(
              _PopupMenuStyle.menuBorderRadius,
            ),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: isDark ? 0.3 : 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: _PopupMenuStyle.menuVerticalPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in displayItems.asMap().entries) ...[
                  _popupMenuItem(context, item: item.value, index: item.key),
                  if (item.value != displayItems.last) ...[
                    SizedBox(height: _PopupMenuStyle.itemGap),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _PopupMenuStyle.dividerHorizontalSpacing,
                      ),
                      child: Divider(
                        height: 0,
                        thickness: 1,
                        color: colorScheme.outline.withValues(
                          alpha: isDark ? 0.15 : 0.1,
                        ),
                      ),
                    ),
                    SizedBox(height: _PopupMenuStyle.itemGap),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
