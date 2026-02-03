import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

// 二维码覆盖层样式常量
class _QrCodeOverlayStyles {
  static const double containerSize = 300;
  static const double qrSize = 260;
  static const double borderRadius = 20;
  static const double shadowBlurRadius = 30;
  static const int animationDurationMs = 200;

  static final Color overlayColor = Colors.black.withValues(alpha: 0.7);
  static final Color shadowColor = Colors.black.withValues(alpha: 0.3);

  static final BoxDecoration containerDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(borderRadius),
    boxShadow: [
      BoxShadow(
        color: shadowColor,
        blurRadius: shadowBlurRadius,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

// 二维码覆盖层组件：全屏显示二维码，点击任意区域关闭。
class QrCodeOverlay extends StatefulWidget {
  // 二维码数据
  final String data;

  const QrCodeOverlay({super.key, required this.data});

  // 显示二维码覆盖层
  static void show(BuildContext context, {required String data}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return QrCodeOverlay(data: data);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(
          milliseconds: _QrCodeOverlayStyles.animationDurationMs,
        ),
      ),
    );
  }

  @override
  State<QrCodeOverlay> createState() => _QrCodeOverlayState();
}

class _QrCodeOverlayState extends State<QrCodeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  // 空操作处理器，避免每次 build 创建新闭包
  static void _emptyTapHandler() {}

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(
        milliseconds: _QrCodeOverlayStyles.animationDurationMs,
      ),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleClose() {
    _controller.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleClose,
      child: Material(
        color: _QrCodeOverlayStyles.overlayColor,
        child: Center(
          child: GestureDetector(
            // 阻止点击二维码区域时关闭
            onTap: _emptyTapHandler,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(opacity: _opacityAnimation.value, child: child);
              },
              child: Container(
                width: _QrCodeOverlayStyles.containerSize,
                height: _QrCodeOverlayStyles.containerSize,
                decoration: _QrCodeOverlayStyles.containerDecoration,
                child: Center(
                  child: QrImageView(
                    data: widget.data,
                    version: QrVersions.auto,
                    size: _QrCodeOverlayStyles.qrSize,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
