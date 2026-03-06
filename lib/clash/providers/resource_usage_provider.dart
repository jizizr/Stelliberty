import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/services/memory_service.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 资源使用 Provider
class ResourceUsageProvider extends ChangeNotifier {
  ResourceUsageProvider(this._clashProvider) {
    _clashProvider.addListener(_handleCoreStateChanged);
    _startAppMemoryTimer();
    if (_clashProvider.isCoreRunning) {
      _startMemoryMonitoring();
    } else {
      _refreshAppMemory();
    }
  }

  static const Duration _appRefreshInterval = Duration(seconds: 2);

  final ClashProvider _clashProvider;
  final MemoryService _monitor = MemoryService.instance;

  Timer? _appRefreshTimer;
  StreamSubscription<MemoryData>? _memorySubscription;

  int? _appMemoryBytes;
  int? _coreMemoryBytes;

  int? get appMemoryBytes => _appMemoryBytes;
  int? get coreMemoryBytes => _coreMemoryBytes;

  void _handleCoreStateChanged() {
    if (_clashProvider.isCoreRunning) {
      _startMemoryMonitoring();
      return;
    }

    _stopMemoryMonitoring();
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

  void _startMemoryMonitoring() {
    if (_memorySubscription != null) return;

    _monitor.startMonitoring();
    _memorySubscription = _monitor.memoryStream?.listen(
      _handleMemoryData,
      onError: (error) {
        Logger.warning('核心内存数据流错误：$error');
      },
    );
  }

  void _stopMemoryMonitoring() {
    _memorySubscription?.cancel();
    _memorySubscription = null;
    _monitor.stopMonitoring();
  }

  void _handleMemoryData(MemoryData data) {
    _updateCoreMemory(data.inuse);
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
    _stopMemoryMonitoring();
    _appRefreshTimer?.cancel();
    _clashProvider.removeListener(_handleCoreStateChanged);
    super.dispose();
  }
}
