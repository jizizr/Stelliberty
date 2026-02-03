import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/material.dart';

// Modern Toast 类型
enum ToastType { success, error, warning, info }

// Toast 队列项
class _ToastQueueItem {
  final String message;
  final ToastType type;
  final Duration duration;

  _ToastQueueItem({
    required this.message,
    required this.type,
    required this.duration,
  });
}

// Toast 工具：显示轻量提示消息并支持队列串行展示。
// 通过全局 navigatorKey 获取 Overlay 上下文。
class ModernToast {
  // 全局导航键，用于获取稳定的 Overlay context
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Toast 队列
  static final Queue<_ToastQueueItem> _queue = Queue<_ToastQueueItem>();

  // 当前是否正在显示 Toast
  static bool _isShowing = false;

  // 显示 Toast 提示消息。
  // 可指定类型与持续时间。
  static void show(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    // 添加到队列
    _queue.add(
      _ToastQueueItem(message: message, type: type, duration: duration),
    );

    // 如果当前没有在显示，立即处理队列
    if (!_isShowing) {
      _processQueue();
    }
  }

  // 处理队列
  static Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isShowing = false;
      return;
    }

    _isShowing = true;
    final item = _queue.removeFirst();

    // 显示当前 Toast
    await _showSingle(item.message, type: item.type, duration: item.duration);

    // 继续处理下一个
    await _processQueue();
  }

  // 显示单个 Toast（内部方法）
  static Future<void> _showSingle(
    String message, {
    required ToastType type,
    required Duration duration,
  }) async {
    // 从 GlobalKey 的 NavigatorState 获取 overlay
    final navigatorState = navigatorKey.currentState;

    // 检查 navigator 是否可用
    if (navigatorState == null) {
      debugPrint('[ModernToast] Navigator 不可用，跳过显示');
      return;
    }

    // 直接从 navigator 获取 overlay
    final overlay = navigatorState.overlay;
    if (overlay == null) {
      debugPrint('[ModernToast] Overlay 不可用');
      return;
    }

    final completer = Completer<void>();
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDismiss: () {
          overlayEntry.remove();
          completer.complete();
        },
      ),
    );

    overlay.insert(overlayEntry);

    // 等待 Toast 显示完成
    return completer.future;
  }

  // 显示成功提示
  static void success(String message) {
    show(message, type: ToastType.success);
  }

  // 显示错误提示
  static void error(String message) {
    show(message, type: ToastType.error);
  }

  // 显示警告提示
  static void warning(String message) {
    show(message, type: ToastType.warning);
  }

  // 显示信息提示
  static void info(String message) {
    show(message, type: ToastType.info);
  }
}

// Toast Widget
class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // 微小延迟确保布局完全渲染后再开始动画（避免 BackdropFilter 闪烁）
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _controller.forward();
      }
    });

    // 指定时长后开始消失动画
    Future.delayed(widget.duration, () {
      _dismiss();
    });
  }

  // 触发消失动画
  Future<void> _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;

    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _getToastConfig(widget.type);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 30,
      left: MediaQuery.of(context).size.width * 0.5 - 150,
      width: 300,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  // 磨砂玻璃背景
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(config.icon, color: config.iconColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade100
                              : Colors.grey.shade800,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none, // 移除任何继承的下划线
                        ),
                        textAlign: TextAlign.start,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 获取 Toast 配置
  _ToastConfig _getToastConfig(ToastType type) {
    switch (type) {
      case ToastType.success:
        return _ToastConfig(
          iconColor: Colors.green.shade500,
          icon: Icons.check_circle_outline_rounded,
        );
      case ToastType.error:
        return _ToastConfig(
          iconColor: Colors.red.shade500,
          icon: Icons.cancel_rounded,
        );
      case ToastType.warning:
        return _ToastConfig(
          iconColor: Colors.orange.shade500,
          icon: Icons.warning_amber_rounded,
        );
      case ToastType.info:
        return _ToastConfig(
          iconColor: Colors.blue.shade500,
          icon: Icons.info_outline_rounded,
        );
    }
  }
}

// Toast 配置
class _ToastConfig {
  final Color iconColor;
  final IconData icon;

  _ToastConfig({required this.iconColor, required this.icon});
}
