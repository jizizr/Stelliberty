import 'package:flutter/material.dart';

// 多行文本输入组件：用于编辑较长文本（如规则、脚本）。
// 支持独立滚动条间距与等宽字体显示。
class ModernMultilineTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final double? height;
  final bool enabled;
  final EdgeInsets contentPadding;
  final double scrollbarRightPadding;
  final EdgeInsets scrollbarPadding;

  const ModernMultilineTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.maxLines,
    this.height,
    this.enabled = true,
    this.contentPadding = const EdgeInsets.all(12),
    this.scrollbarRightPadding = 2.0,
    this.scrollbarPadding = const EdgeInsets.only(
      left: 0,
      right: 1,
      top: 4,
      bottom: 4,
    ),
  });

  @override
  State<ModernMultilineTextField> createState() =>
      _ModernMultilineTextFieldState();
}

class _ModernMultilineTextFieldState extends State<ModernMultilineTextField> {
  bool _isFocused = false;
  bool _isHovering = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 计算背景颜色
    Color backgroundColor;
    if (!widget.enabled) {
      backgroundColor = theme.colorScheme.surface.withAlpha(100);
    } else if (_isFocused) {
      backgroundColor = Color.alphaBlend(
        theme.colorScheme.primary.withAlpha(10),
        theme.colorScheme.surface.withAlpha(255),
      );
    } else if (_isHovering) {
      backgroundColor = Color.alphaBlend(
        theme.colorScheme.onSurface.withAlpha(10),
        theme.colorScheme.surface.withAlpha(255),
      );
    } else {
      backgroundColor = theme.colorScheme.surface.withAlpha(255);
    }

    // 边框颜色
    Color borderColor;
    if (widget.errorText != null) {
      borderColor = theme.colorScheme.error;
    } else if (!widget.enabled) {
      borderColor = theme.colorScheme.outline.withAlpha(50);
    } else if (_isFocused) {
      borderColor = theme.colorScheme.primary.withAlpha(180);
    } else if (_isHovering) {
      borderColor = theme.colorScheme.outline.withAlpha(150);
    } else {
      borderColor = theme.colorScheme.outline.withAlpha(100);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标签
          if (widget.labelText != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                widget.labelText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isFocused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withAlpha(180),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          // 编辑器容器
          Focus(
            onFocusChange: (focused) => setState(() => _isFocused = focused),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: widget.height,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: _isFocused ? 2 : 1.5,
                ),
                boxShadow: [
                  if (_isFocused)
                    BoxShadow(
                      color: theme.colorScheme.primary.withAlpha(30),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Padding(
                padding: widget.scrollbarPadding,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: false,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false, // 禁用默认滚动条
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: TextField(
                        controller: widget.controller,
                        onChanged: widget.onChanged,
                        maxLines: null, // 不限制行数，不滚动
                        minLines: widget.maxLines ?? 1,
                        enabled: widget.enabled,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas, Monaco, monospace',
                          fontSize: 13,
                          color: widget.enabled
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withAlpha(100),
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(100),
                            fontFamily: 'Consolas, Monaco, monospace',
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          contentPadding: widget.contentPadding, // 文字左右对称
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 错误文本或帮助文本
          if (widget.errorText != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                widget.errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontSize: 11,
                ),
              ),
            ),
          ] else if (widget.helperText != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                widget.helperText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(130),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
