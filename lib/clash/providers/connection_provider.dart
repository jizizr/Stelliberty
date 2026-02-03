import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:stelliberty/clash/model/connection_model.dart';
import 'package:stelliberty/clash/state/connection_states.dart' as state;
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/services/vpn_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 连接管理 Provider
// 桌面端：通过 WebSocket 流获取连接信息
// Android：通过事件流推送获取连接信息
class ConnectionProvider extends ChangeNotifier {
  final ClashProvider _clashProvider;

  // 直连标识（常量）
  static const String _directProxy = 'DIRECT';

  // 状态
  state.ConnectionState _state = state.ConnectionState.initial();

  // 过滤后的连接列表缓存
  List<ConnectionInfo>? _cachedFilteredConnections;

  // 过滤后的连接列表
  List<ConnectionInfo> get connections {
    _cachedFilteredConnections ??= _getFilteredConnections();
    return _cachedFilteredConnections!;
  }

  // Getters
  bool get isLoading => _state.isLoading;
  String? get errorMessage => _state.errorMessage;
  bool get isMonitoringPaused => _state.isMonitoringPaused;
  state.ConnectionFilterLevel get filterLevel => _state.filterLevel;
  String get searchKeyword => _state.searchKeyword;

  // Android 事件流订阅
  StreamSubscription<String>? _androidStreamSubscription;

  // 桌面端 WebSocket 流订阅
  StreamSubscription? _desktopStreamSubscription;

  ConnectionProvider(this._clashProvider) {
    // 监听 Clash 运行状态
    // 先移除可能存在的旧监听器，防止重复添加
    _clashProvider.removeListener(_onClashStateChanged);
    _clashProvider.addListener(_onClashStateChanged);

    // 如果 Clash 已经在运行，立即开始刷新
    if (_clashProvider.isCoreRunning) {
      startAutoRefresh();
    }
  }

  // 当 Clash 状态改变时
  void _onClashStateChanged() {
    if (_clashProvider.isCoreRunning) {
      // Clash 启动，开始自动刷新
      startAutoRefresh();
    } else {
      // Clash 停止，重置状态
      stopAutoRefresh();
      _state = state.ConnectionState.initial();
      _cachedFilteredConnections = null;
      notifyListeners();
    }
  }

  // 开始自动刷新
  void startAutoRefresh() {
    if (Platform.isAndroid) {
      _startAndroidStream();
    } else {
      _startDesktopStream();
    }
  }

  // Android：启动事件流监听
  void _startAndroidStream() {
    if (_androidStreamSubscription != null) {
      return;
    }

    // 调用 Go 核心启动连接推送
    VpnService.invokeAction(method: 'startConnections');

    // 订阅事件流
    _androidStreamSubscription = VpnService.coreLogStream?.listen(
      _handleAndroidEvent,
      onError: (error) {
        Logger.error('Android 连接流错误：$error');
      },
    );

    Logger.info('连接监控已启动 (Android 推送模式)');
  }

  // 桌面端：启动 WebSocket 流监听
  void _startDesktopStream() {
    if (_desktopStreamSubscription != null) {
      return;
    }

    // 发送启动信号到 Rust
    const StartConnectionStream().sendSignalToRust();

    // 订阅 Rust 推送的连接数据
    _desktopStreamSubscription = IpcConnectionData.rustSignalStream.listen(
      (signal) {
        if (_state.isMonitoringPaused) return;
        _handleConnectionsData(signal.message.connectionsJson);
      },
      onError: (error) {
        Logger.error('桌面端连接流错误：$error');
      },
    );

    Logger.info('连接监控已启动 (WebSocket 模式)');
  }

  // Android：处理事件
  void _handleAndroidEvent(String jsonString) {
    if (_state.isMonitoringPaused) return;

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final method = json['method'] as String?;

      if (method == 'message') {
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) return;

        final messageType = data['type'] as String?;
        if (messageType == 'connections') {
          final connectionsData = data['data'];
          if (connectionsData != null) {
            _handleConnectionsData(connectionsData);
          }
        }
      }
    } catch (e) {
      // 忽略非连接事件的解析错误
    }
  }

  // 处理连接数据
  void _handleConnectionsData(dynamic rawData) {
    try {
      Map<String, dynamic> snapshot;
      if (rawData is String) {
        snapshot = jsonDecode(rawData) as Map<String, dynamic>;
      } else {
        snapshot = rawData as Map<String, dynamic>;
      }

      final connectionsList = snapshot['connections'] as List<dynamic>? ?? [];
      final connections = connectionsList
          .map((item) => ConnectionInfo.fromJson(item as Map<String, dynamic>))
          .toList();

      // 检查数据是否真正发生了变化
      final hasChanged = _hasConnectionsChanged(
        _state.connections,
        connections,
      );

      _state = _state.copyWith(
        connections: connections,
        isLoading: false,
        errorMessage: null,
      );

      if (hasChanged || connections.isNotEmpty) {
        _cachedFilteredConnections = null;
        notifyListeners();
      }
    } catch (e) {
      Logger.error('解析连接数据失败：$e');
    }
  }

  // 停止自动刷新
  void stopAutoRefresh({bool silent = false}) {
    // 停止 Android 事件流
    if (_androidStreamSubscription != null) {
      _androidStreamSubscription?.cancel();
      _androidStreamSubscription = null;
      // 调用 Go 核心停止连接推送
      VpnService.invokeAction(method: 'stopConnections');
      if (!silent) {
        Logger.info('连接监控已停止 (Android 推送模式)');
      }
    }

    // 停止桌面端 WebSocket 流
    if (_desktopStreamSubscription != null) {
      _desktopStreamSubscription?.cancel();
      _desktopStreamSubscription = null;
      // 发送停止信号到 Rust
      const StopConnectionStream().sendSignalToRust();
      if (!silent) {
        Logger.info('连接监控已停止 (WebSocket 模式)');
      }
    }
  }

  // 暂停/恢复自动刷新（监控）
  void togglePause() {
    _state = _state.copyWith(isMonitoringPaused: !_state.isMonitoringPaused);
    Logger.info('连接列表自动刷新已${_state.isMonitoringPaused ? "暂停" : "恢复"}');
    notifyListeners();
  }

  // 设置过滤级别
  void setFilterLevel(state.ConnectionFilterLevel level) {
    _state = _state.copyWith(filterLevel: level);
    _cachedFilteredConnections = null;
    Logger.info('连接过滤级别已设置为：${level.name}');
    notifyListeners();
  }

  // 设置搜索关键字
  void setSearchKeyword(String keyword) {
    _state = _state.copyWith(searchKeyword: keyword);
    _cachedFilteredConnections = null;
    Logger.debug('连接搜索关键字已设置为: $keyword');
    notifyListeners();
  }

  // 获取过滤后的连接列表
  List<ConnectionInfo> _getFilteredConnections() {
    List<ConnectionInfo> filteredConnections = _state.connections;

    // 1. 按过滤级别筛选
    switch (_state.filterLevel) {
      case state.ConnectionFilterLevel.direct:
        filteredConnections = filteredConnections
            .where((conn) => conn.proxyNode == _directProxy)
            .toList();
        break;
      case state.ConnectionFilterLevel.proxy:
        filteredConnections = filteredConnections
            .where((conn) => conn.proxyNode != _directProxy)
            .toList();
        break;
      case state.ConnectionFilterLevel.all:
        // 不过滤
        break;
    }

    // 2. 按关键字筛选
    if (_state.searchKeyword.isNotEmpty) {
      final keyword = _state.searchKeyword.toLowerCase();
      filteredConnections = filteredConnections.where((conn) {
        final descLower = conn.metadata.description.toLowerCase();
        final proxyLower = conn.proxyNode.toLowerCase();
        final ruleLower = conn.rule.toLowerCase();
        final processLower = conn.metadata.process.toLowerCase();

        return descLower.contains(keyword) ||
            proxyLower.contains(keyword) ||
            ruleLower.contains(keyword) ||
            processLower.contains(keyword);
      }).toList();
    }

    return filteredConnections;
  }

  // 检查连接列表是否发生变化
  bool _hasConnectionsChanged(
    List<ConnectionInfo> oldConnections,
    List<ConnectionInfo> nextConnections,
  ) {
    // 数量不同，肯定有变化
    if (oldConnections.length != nextConnections.length) {
      return true;
    }

    // 数量相同但为空，认为没变化
    if (oldConnections.isEmpty) {
      return false;
    }

    // 创建 ID 集合进行快速比较
    final previousIds = oldConnections.map((c) => c.id).toSet();
    final currentIds = nextConnections.map((c) => c.id).toSet();

    // 比较 ID 集合是否相同
    return !previousIds.containsAll(currentIds) ||
        !currentIds.containsAll(previousIds);
  }

  // 关闭指定连接
  Future<bool> closeConnection(String connectionId) async {
    return _executeConnectionOperation(
      () => ClashManager.instance.closeConnection(connectionId),
      '关闭连接',
      '连接已关闭: $connectionId',
    );
  }

  // 关闭所有连接
  Future<bool> closeAllConnections() async {
    return _executeConnectionOperation(
      ClashManager.instance.closeAllConnections,
      '关闭所有连接',
      '所有连接已关闭',
    );
  }

  // 执行连接操作的公共逻辑
  Future<bool> _executeConnectionOperation(
    Future<bool> Function() operation,
    String operationName,
    String successMessage,
  ) async {
    if (!_clashProvider.isCoreRunning) {
      Logger.warning('Clash 未运行，无法$operationName');
      return false;
    }

    try {
      final success = await operation();

      if (success) {
        Logger.info(successMessage);
        // 连接关闭后，WebSocket 流会自动推送更新
      }

      return success;
    } catch (e) {
      Logger.error('$operationName失败：$e');
      return false;
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _clashProvider.removeListener(_onClashStateChanged);
    super.dispose();
  }
}
