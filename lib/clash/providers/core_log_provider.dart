import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/model/log_message_model.dart';
import 'package:stelliberty/clash/state/core_log_states.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 核心日志状态管理
// 统一管理所有日志相关的状态，确保切换页面时数据不丢失
class LogProvider extends ChangeNotifier {
  final ClashProvider _clashProvider;

  // 状态
  CoreLogState _state = CoreLogState.initial();

  // 上一次的核心运行状态（用于检测状态变化）
  bool _lastCoreRunning = false;

  // 待处理日志缓冲区
  final List<ClashLogMessage> _pendingLogs = [];

  StreamSubscription<ClashLogMessage>? _logSubscription;
  Timer? _batchUpdateTimer;
  Timer? _searchDebounceTimer;

  static const _batchUpdateInterval = Duration(milliseconds: 200);
  static const _maxBatchInterval = Duration(milliseconds: 500);
  static const _batchThreshold = 1;
  static const _maxLogsCount = 2000;

  // 过滤结果缓存
  List<ClashLogMessage>? _cachedFilteredLogs;
  String? _cacheKey;

  // 上次刷新时间（用于动态批量更新）
  DateTime _lastFlushedAt = DateTime.now();

  LogProvider(this._clashProvider) {
    // 监听 Clash 运行状态
    _clashProvider.removeListener(_onClashStateChanged);
    _clashProvider.addListener(_onClashStateChanged);
  }

  // 当 Clash 状态改变时
  void _onClashStateChanged() {
    final currentRunning = _clashProvider.isCoreRunning;

    // 只在从运行状态变为停止状态时清空日志
    if (_lastCoreRunning && !currentRunning) {
      _pendingLogs.clear();
      _state = CoreLogState.initial();
      _invalidateCache();
      notifyListeners();
      Logger.info('LogProvider: Clash 已停止，日志已清空，过滤条件已重置');
    }

    _lastCoreRunning = currentRunning;
  }

  // Getters
  List<ClashLogMessage> get logs => List.unmodifiable(_state.logs);
  bool get isMonitoringPaused => _state.isMonitoringPaused;
  ClashLogLevel? get filterLevel => _state.filterLevel;
  String get searchKeyword => _state.searchKeyword;
  bool get isLoading => _state.isLoading;

  // 获取过滤后的日志列表（带缓存优化）
  List<ClashLogMessage> get filteredLogs {
    // 生成缓存键（基于过滤条件和日志数量）
    final cacheKey =
        '${_state.filterLevel}_${_state.searchKeyword}_${_state.logs.length}';

    // 如果缓存有效，直接返回
    if (_cachedFilteredLogs != null && _cacheKey == cacheKey) {
      return _cachedFilteredLogs!;
    }

    // 重新计算过滤结果
    _cachedFilteredLogs = _state.logs.where((log) {
      // 级别过滤
      if (_state.filterLevel != null && log.level != _state.filterLevel) {
        return false;
      }
      // 搜索关键词过滤
      if (_state.searchKeyword.isNotEmpty) {
        final keyword = _state.searchKeyword.toLowerCase();
        return log.payload.toLowerCase().contains(keyword) ||
            log.type.toLowerCase().contains(keyword);
      }
      return true;
    }).toList();

    _cacheKey = cacheKey;
    return _cachedFilteredLogs!;
  }

  // 清除缓存（在过滤条件变化时调用）
  void _invalidateCache() {
    _cachedFilteredLogs = null;
    _cacheKey = null;
  }

  // 初始化 Provider
  void initialize() {
    Logger.info('LogProvider: 开始初始化');

    // 启动批量更新定时器
    _startBatchUpdateTimer();

    // 订阅日志流
    _subscribeToLogStream();

    // 异步加载历史日志（不阻塞 UI）
    _loadHistoryLogsAsync();

    Logger.info('LogProvider: 初始化完成（历史日志异步加载中）');
  }

  // 异步加载历史日志（不阻塞 UI）
  Future<void> _loadHistoryLogsAsync() async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    // 使用 microtask 确保 UI 先渲染
    await Future.microtask(() {});

    // 初始化完成，等待实时日志
    // 日志将在用户打开页面后实时接收
    Logger.info('LogProvider: 初始化完成，等待实时日志');

    _state = _state.copyWith(isLoading: false);
    notifyListeners();
  }

  // 订阅日志流
  void _subscribeToLogStream() {
    _logSubscription = ClashManager.instance.logStream.listen(
      (log) {
        if (!_state.isMonitoringPaused) {
          _pendingLogs.add(log);
        }
      },
      onError: (error) {
        Logger.error('LogProvider: 日志流错误：$error');
      },
      onDone: () {
        Logger.warning('LogProvider: 日志流已关闭');
      },
    );
    Logger.info('LogProvider: 已订阅日志流');
  }

  // 启动批量更新定时器（动态批量优化，兼顾即时性与性能）。
  void _startBatchUpdateTimer() {
    _batchUpdateTimer = Timer.periodic(_batchUpdateInterval, (_) {
      // 动态批量策略：满足阈值立即更新；超时则强制更新。
      // 目标是减少高频 notify 的开销。
      final shouldFlush =
          _pendingLogs.length >= _batchThreshold ||
          (_pendingLogs.isNotEmpty && _shouldFlushPending());

      if (shouldFlush) {
        final nextLogs = List<ClashLogMessage>.from(_state.logs)
          ..addAll(_pendingLogs);

        // 限制日志数量
        while (nextLogs.length > _maxLogsCount) {
          nextLogs.removeAt(0);
        }

        _state = _state.copyWith(logs: nextLogs);
        _pendingLogs.clear();
        _invalidateCache();
        _lastFlushedAt = DateTime.now();
        notifyListeners();
      }
    });
    Logger.info(
      'LogProvider: 批量更新定时器已启动 (间隔: ${_batchUpdateInterval.inMilliseconds}ms, 阈值: $_batchThreshold条, 最大延迟: ${_maxBatchInterval.inMilliseconds}ms)',
    );
  }

  // 检查是否应该刷新待处理日志（超时强制刷新）
  bool _shouldFlushPending() {
    // 如果超过最大间隔未刷新，强制刷新保证即时性
    return DateTime.now().difference(_lastFlushedAt) > _maxBatchInterval;
  }

  // 清空日志
  void clearLogs() {
    _pendingLogs.clear();
    _state = _state.copyWith(logs: []);
    _invalidateCache();
    notifyListeners();
    Logger.info('LogProvider: 日志已清空');
  }

  // 切换暂停状态（监控）
  void togglePause() {
    _state = _state.copyWith(isMonitoringPaused: !_state.isMonitoringPaused);
    notifyListeners();
    Logger.info('LogProvider: 日志监控暂停状态 = ${_state.isMonitoringPaused}');
  }

  // 设置过滤级别
  void setFilterLevel(ClashLogLevel? level) {
    _state = _state.copyWith(filterLevel: level);
    _invalidateCache();
    notifyListeners();
    Logger.debug('LogProvider: 过滤级别已设置为 $level');
  }

  // 设置搜索关键词（带防抖）
  void setSearchKeyword(String keyword) {
    // 取消防抖定时器
    _searchDebounceTimer?.cancel();

    // 设置防抖定时器（300ms 后触发过滤）
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _state = _state.copyWith(searchKeyword: keyword);
      _invalidateCache();
      notifyListeners();
    });
  }

  // 复制所有日志
  String copyAllLogs() {
    return _state.logs
        .map((log) => '[${log.formattedTime}] [${log.type}] ${log.payload}')
        .join('\n');
  }

  @override
  void dispose() {
    Logger.info('LogProvider: 开始清理资源');
    _batchUpdateTimer?.cancel();
    _logSubscription?.cancel();
    _searchDebounceTimer?.cancel(); // 取消搜索防抖定时器
    _clashProvider.removeListener(_onClashStateChanged);
    super.dispose();
  }
}
