import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';
import 'package:stelliberty/atomic/platform_helper.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/services/vpn_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

class ResourceUsageProvider extends ChangeNotifier {
  ResourceUsageProvider(this._clashProvider) {
    _clashProvider.addListener(_handleCoreStateChanged);
    _startAppMemoryTimer();
    if (_clashProvider.isCoreRunning) {
      _startMemoryStream();
    } else {
      _refreshAppMemory();
    }
  }

  static const Duration _appRefreshInterval = Duration(seconds: 2);

  final ClashProvider _clashProvider;

  Timer? _appRefreshTimer;
  StreamSubscription<RustSignalPack<IpcMemoryData>>? _memorySubscription;
  StreamSubscription<String>? _androidMemorySubscription;
  bool _isMemoryStreamActive = false;

  int? _appMemoryBytes;
  int? _coreMemoryBytes;

  int? get appMemoryBytes => _appMemoryBytes;
  int? get coreMemoryBytes => _coreMemoryBytes;

  void _handleCoreStateChanged() {
    if (_clashProvider.isCoreRunning) {
      _startMemoryStream();
      return;
    }

    _stopMemoryStream();
    final shouldNotify = _coreMemoryBytes != null;
    _coreMemoryBytes = null;
    if (shouldNotify) {
      notifyListeners();
    }
    _refreshAppMemory();
  }

  void _startAppMemoryTimer() {
    _appRefreshTimer?.cancel();
    _appRefreshTimer = Timer.periodic(_appRefreshInterval, (_) {
      _refreshAppMemory();
    });
  }

  void _startMemoryStream() {
    if (_isMemoryStreamActive) return;
    _isMemoryStreamActive = true;

    if (PlatformHelper.isMobile) {
      _startAndroidMemoryStream();
    } else {
      _startDesktopMemoryStream();
    }
  }

  void _startDesktopMemoryStream() {
    _memorySubscription?.cancel();
    _memorySubscription = IpcMemoryData.rustSignalStream.listen(
      _handleMemoryData,
      onError: (error) {
        Logger.warning('核心内存数据流错误：$error');
      },
    );
    const StartMemoryStream().sendSignalToRust();
  }

  void _startAndroidMemoryStream() {
    _androidMemorySubscription?.cancel();
    _androidMemorySubscription = VpnService.coreLogStream?.listen(
      _handleAndroidEvent,
      onError: (error) {
        Logger.warning('Android 内存数据流错误：$error');
      },
    );
    // 启动核心内存推送
    VpnService.invokeAction(method: 'startMemory');
  }

  void _stopMemoryStream() {
    if (!_isMemoryStreamActive) return;
    _isMemoryStreamActive = false;

    if (PlatformHelper.isMobile) {
      VpnService.invokeAction(method: 'stopMemory');
      _androidMemorySubscription?.cancel();
      _androidMemorySubscription = null;
    } else {
      const StopMemoryStream().sendSignalToRust();
      _memorySubscription?.cancel();
      _memorySubscription = null;
    }
  }

  void _handleAndroidEvent(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final method = json['method'] as String?;
      if (method != 'message') return;

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final messageType = data['type'] as String?;
      if (messageType != 'memory') return;

      final memoryData = data['data'] as Map<String, dynamic>?;
      if (memoryData == null) return;

      final inuse = memoryData['inuse'];
      if (inuse == null) return;

      final memoryBytes = (inuse is int)
          ? inuse
          : int.tryParse(inuse.toString());
      if (memoryBytes == null) return;

      _updateCoreMemory(memoryBytes);
    } catch (e) {
      Logger.warning('处理 Android 内存事件失败：$e');
    }
  }

  void _handleMemoryData(RustSignalPack<IpcMemoryData> signal) {
    _updateCoreMemory(signal.message.inuse.toInt());
  }

  void _updateCoreMemory(int memoryBytes) {
    final nextAppMemoryBytes = _readAppMemoryBytes();
    final resolvedAppMemoryBytes = nextAppMemoryBytes ?? _appMemoryBytes;

    final shouldNotify =
        memoryBytes != _coreMemoryBytes ||
        resolvedAppMemoryBytes != _appMemoryBytes;

    _coreMemoryBytes = memoryBytes;
    if (nextAppMemoryBytes != null) {
      _appMemoryBytes = nextAppMemoryBytes;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  int? _readAppMemoryBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (e) {
      Logger.warning('获取应用内存失败：$e');
      return null;
    }
  }

  void _refreshAppMemory() {
    final nextAppMemoryBytes = _readAppMemoryBytes();
    if (nextAppMemoryBytes == null) return;

    if (nextAppMemoryBytes != _appMemoryBytes) {
      _appMemoryBytes = nextAppMemoryBytes;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopMemoryStream();
    _appRefreshTimer?.cancel();
    _clashProvider.removeListener(_handleCoreStateChanged);
    super.dispose();
  }
}
