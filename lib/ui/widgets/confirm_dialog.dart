import 'package:flutter/material.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/common/modern_dialog.dart';

// 简单确认对话框（基于 ModernDialog）
// 用于需要用户确认的操作（如删除、清空等）
class ConfirmDialog extends StatelessWidget {
  // 标题文本
  final String title;

  // 提示内容
  final String message;

  // 确认按钮文本
  final String? confirmText;

  // 取消按钮文本
  final String? cancelText;

  // 确认按钮是否为危险操作（红色）
  final bool isDanger;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText,
    this.cancelText,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trans = context.translate;

    return ModernDialog(
      title: title,
      shouldShowCloseButton: false, // 不显示关闭按钮
      shouldShowDividers: false, // 不显示分隔线
      maxWidth: 420,
      maxHeightRatio: 0.5,
      // 内容区：带背景色（与顶栏一致）
      content: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.3),
        ),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
            height: 1.5,
          ),
        ),
      ),
      // 右侧按钮：取消和确认
      actionsRight: [
        DialogActionButton(
          label: cancelText ?? trans.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DialogActionButton(
          label: confirmText ?? trans.common.confirm,
          onPressed: () => Navigator.of(context).pop(true),
          isPrimary: true,
          isDanger: isDanger,
        ),
      ],
      onClose: () => Navigator.of(context).pop(false),
    );
  }
}

// 辅助函数：显示确认对话框
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmText,
  String? cancelText,
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      isDanger: isDanger,
    ),
  );
}
