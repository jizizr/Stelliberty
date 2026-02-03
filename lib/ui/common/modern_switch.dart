import 'package:flutter/material.dart';

// 现代开关组件：提供切换动画与悬停反馈。
// 外观与交互遵循 Material 3 风格。
class ModernSwitch extends StatefulWidget {
  // 开关状态
  final bool value;

  // 状态变化回调
  final ValueChanged<bool>? onChanged;

  // 是否启用
  final bool enabled;

  const ModernSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<ModernSwitch> createState() => _ModernSwitchState();
}

class _ModernSwitchState extends State<ModernSwitch>
    with SingleTickerProviderStateMixin {
  // 主动画控制器，控制开关切换动画
  late AnimationController _controller;

  // 圆点位置动画 (0.0 = 左侧, 1.0 = 右侧)
  late Animation<double> _positionAnimation;

  // 圆点尺寸动画 (20.0 = 关闭, 24.0 = 开启)
  late Animation<double> _sizeAnimation;

  // 勾选图标淡入动画
  late Animation<double> _checkOpacityAnimation;

  // 是否鼠标悬停
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();

    // 创建动画控制器，200ms 完成切换动画
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // 位置动画：从左到右线性插值
    _positionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 尺寸动画：20px -> 24px
    _sizeAnimation = Tween<double>(
      begin: 20.0,
      end: 24.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 勾选图标淡入动画：在动画后半段 (50%-100%) 淡入
    _checkOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // 如果初始状态为开启，直接设置动画到结束位置
    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ModernSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 状态改变时播放动画
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _controller.forward(); // 开启：播放正向动画
      } else {
        _controller.reverse(); // 关闭：播放反向动画
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.enabled && widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // 轨道颜色
            final trackColor = widget.value
                ? theme.colorScheme.primary
                : (isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surfaceContainerHighest);

            // 圆点颜色
            final thumbColor = widget.value
                ? (isDark ? theme.colorScheme.surface : Colors.white)
                : (isDark
                      ? theme.colorScheme.outline
                      : theme.colorScheme.outline);

            // 禁用时整体透明度降低
            final opacity = widget.enabled ? 1.0 : 0.4;

            // 圆点基础尺寸（根据开关状态）
            final baseThumbSize = _sizeAnimation.value;

            // 悬停时放大 15%
            final hoverScale = _isHovering && widget.enabled ? 1.15 : 1.0;

            // 圆点最终尺寸 = 基础尺寸 × 悬停缩放
            final thumbSize = baseThumbSize * hoverScale;

            // 轨道尺寸（固定）
            final trackWidth = 52.0;
            final trackHeight = 32.0;

            // 轨道半径 = 高度的一半（因为是圆角矩形）
            final trackRadius = trackHeight / 2;

            // 左侧半圆圆心的 X 坐标 = 半径
            final leftCenterX = trackRadius;

            // 右侧半圆圆心的 X 坐标 = 总宽度 - 半径
            final rightCenterX = trackWidth - trackRadius;

            // 圆点圆心 X：在左右半圆圆心之间插值。
            // progress=0 为 leftCenterX，progress=1 为 rightCenterX。
            final thumbCenterX =
                leftCenterX +
                (rightCenterX - leftCenterX) * _positionAnimation.value;

            // 圆点左上角 X 坐标 = 圆心 X - 半径
            final thumbLeft = thumbCenterX - thumbSize / 2;

            // 圆点左上角 Y 坐标 = 垂直居中
            final thumbTop = (trackHeight - thumbSize) / 2;

            return Opacity(
              opacity: opacity,
              child: SizedBox(
                width: trackWidth,
                height: trackHeight,
                child: Stack(
                  clipBehavior: Clip.none, // 允许圆点阴影溢出
                  children: [
                    // 轨道背景
                    Container(
                      width: trackWidth,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.value
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withAlpha(100),
                          width: 2,
                        ),
                      ),
                    ),
                    // 滑动圆点
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      left: thumbLeft,
                      top: thumbTop,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: thumbColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        // 开启状态时显示勾选图标
                        child: widget.value
                            ? Center(
                                child: FadeTransition(
                                  opacity: _checkOpacityAnimation,
                                  child: Icon(
                                    Icons.check,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
