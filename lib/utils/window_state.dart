import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:stelliberty/storage/preferences.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'logger.dart';

// 窗口状态管理器，负责窗口尺寸、位置及最大化状态的持久化
class WindowStateManager {
  // 默认窗口配置
  static const _defaultSize = Size(900, 660);
  static const _minSize = Size(900, 660);

  // 缓存窗口状态，避免重复读取
  static _WindowState? _cachedState;

  // 获取窗口状态（带缓存）
  static _WindowState _getState() {
    _cachedState ??= _WindowState.fromAppConfig();
    return _cachedState!;
  }

  // 清除状态缓存，保存新状态后调用
  static void clearCache() {
    _cachedState = null;
  }

  // 应用启动时恢复窗口状态，从本地存储读取上次保存的几何信息
  static Future<void> loadAndApplyState({bool forceSilent = false}) async {
    try {
      // 设置窗口最小尺寸
      appWindow.minSize = _minSize;
      await windowManager.setTitle(
        LocaleSettings.instance.currentTranslations.common.appName,
      );

      // 预计算所需值
      final state = _getState();
      final silentStart =
          forceSilent || AppPreferences.instance.getSilentStartEnabled();

      // 直接使用保存的窗口尺寸，无论是否最大化
      final windowSize = state.size;
      const shouldCenter = true;

      Logger.info(
        "窗口状态: 最大化=${state.isMaximized}, 尺寸=${windowSize.width}x${windowSize.height}",
      );
      // 等待窗口初始化完成
      await windowManager.waitUntilReadyToShow();
      // 设置窗口尺寸和位置
      await windowManager.setSize(windowSize);
      if (shouldCenter) {
        await windowManager.center();
      }

      // 非静默启动时才显示窗口
      if (!silentStart) {
        try {
          if (state.isMaximized) {
            await windowManager.maximize();
          }
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          Logger.error("显示窗口失败：$e");
        }
      }
    } catch (e) {
      Logger.error("加载窗口状态失败：$e");
      await windowManager.setSize(_defaultSize);
      await windowManager.waitUntilReadyToShow();
      await windowManager.show();
      await windowManager.focus();
    }
  }

  // 保存窗口状态到本地存储，应用关闭时调用
  static Future<void> saveStateOnClose() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      await AppPreferences.instance.setIsMaximized(isMaximized);

      // 非最大化时保存尺寸和位置
      if (!isMaximized) {
        await _saveWindowGeometry();
      }

      clearCache();
      Logger.info("窗口状态已保存: isMaximized=$isMaximized");
    } catch (e) {
      Logger.error("保存窗口状态失败：$e");
    }
  }

  // 保存窗口几何信息（尺寸和位置）到本地存储
  static Future<void> _saveWindowGeometry() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();

    await Future.wait([
      AppPreferences.instance.setWindowSize(size),
      AppPreferences.instance.setWindowPosition(position),
    ]);
  }

  // 处理窗口最大化/还原切换
  static Future<void> handleMaximizeRestore() async {
    try {
      final isMaximized = await windowManager.isMaximized();

      if (isMaximized) {
        await _restoreWindow();
      } else {
        await _maximizeWindow();
      }
    } catch (e) {
      Logger.error("窗口操作失败：$e");
    }
  }

  // 还原窗口到之前保存的尺寸和位置
  static Future<void> _restoreWindow() async {
    clearCache();
    final state = _getState();

    await windowManager.unmaximize();

    // 渲染完成后设置精确尺寸和位置
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.setSize(state.size);

        if (state.hasPosition) {
          await windowManager.setPosition(state.position!);
        }
      } catch (e) {
        Logger.error("还原位置失败：$e");
      }
    });
  }

  // 最大化窗口，先保存当前状态
  static Future<void> _maximizeWindow() async {
    Size? backupSize;
    Offset? backupPosition;

    try {
      backupSize = await windowManager.getSize();
      backupPosition = await windowManager.getPosition();
    } catch (e) {
      Logger.warning("获取当前窗口状态失败：$e");
    }

    try {
      await _saveWindowGeometry();
      clearCache();
    } catch (e) {
      Logger.error("保存窗口状态失败，使用内存备份：$e");
      if (backupSize != null) {
        _cachedState = _WindowState(
          isMaximized: false,
          size: backupSize,
          position: backupPosition,
        );
      }
    }

    await windowManager.maximize();
  }
}

// 窗口状态数据类
class _WindowState {
  final bool isMaximized;
  final Size size;
  final Offset? position;

  const _WindowState({
    required this.isMaximized,
    required this.size,
    this.position,
  });

  // 从配置构造窗口状态对象
  factory _WindowState.fromAppConfig() {
    return _WindowState(
      isMaximized: AppPreferences.instance.getIsMaximized(),
      size:
          AppPreferences.instance.getWindowSize() ??
          WindowStateManager._defaultSize,
      position: AppPreferences.instance.getWindowPosition(),
    );
  }

  bool get hasPosition => position != null;

  @override
  String toString() {
    return '窗口状态（最大化：$isMaximized，尺寸：$size，位置：$position）';
  }
}
