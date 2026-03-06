import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stelliberty/clash/model/connection_model.dart';
import 'package:stelliberty/clash/state/connection_states.dart' as state;
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/services/connection_service.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 连接管理 Provider
class ConnectionProvider extends ChangeNotifier {
  final ClashProvider _clashProvider;
  final ConnectionService _monitor = ConnectionService.instance;

  static const String _directProxy = 'DIRECT';

  state.ConnectionState _state = state.ConnectionState.initial();
  List<ConnectionInfo>? _cachedFilteredConnections;
  StreamSubscription<List<ConnectionInfo>>? _streamSubscription;

  List<ConnectionInfo> get connections {
    _cachedFilteredConnections ??= _getFilteredConnections();
    return _cachedFilteredConnections!;
  }

  bool get isLoading => _state.isLoading;
  String? get errorMessage => _state.errorMessage;
  bool get isMonitoringPaused => _state.isMonitoringPaused;
  state.ConnectionFilterLevel get filterLevel => _state.filterLevel;
  String get searchKeyword => _state.searchKeyword;

  ConnectionProvider(this._clashProvider) {
    _clashProvider.removeListener(_onClashStateChanged);
    _clashProvider.addListener(_onClashStateChanged);

    if (_clashProvider.isCoreRunning) {
      _startMonitoring();
    }
  }

  void _onClashStateChanged() {
    if (_clashProvider.isCoreRunning) {
      _startMonitoring();
      return;
    }

    _stopMonitoring();
    _state = state.ConnectionState.initial();
    _cachedFilteredConnections = null;
    notifyListeners();
  }

  void _startMonitoring() {
    if (_streamSubscription != null) return;

    _monitor.startMonitoring();
    _streamSubscription = _monitor.connectionStream?.listen(
      _handleConnectionsData,
      onError: (error) {
        Logger.error('连接数据流错误：$error');
      },
    );
  }

  void _stopMonitoring() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _monitor.stopMonitoring();
  }

  void _handleConnectionsData(List<ConnectionInfo> connections) {
    if (_state.isMonitoringPaused) return;

    final hasChanged = _hasConnectionsChanged(_state.connections, connections);

    _state = _state.copyWith(
      connections: connections,
      isLoading: false,
      errorMessage: null,
    );

    if (hasChanged || connections.isNotEmpty) {
      _cachedFilteredConnections = null;
      notifyListeners();
    }
  }

  void startAutoRefresh() {
    _startMonitoring();
  }

  void stopAutoRefresh({bool silent = false}) {
    _stopMonitoring();
    if (!silent) {
      Logger.info('连接监控已停止');
    }
  }

  void togglePause() {
    _state = _state.copyWith(isMonitoringPaused: !_state.isMonitoringPaused);
    Logger.info('连接列表自动刷新已${_state.isMonitoringPaused ? "暂停" : "恢复"}');
    notifyListeners();
  }

  void setFilterLevel(state.ConnectionFilterLevel level) {
    _state = _state.copyWith(filterLevel: level);
    _cachedFilteredConnections = null;
    Logger.info('连接过滤级别已设置为：${level.name}');
    notifyListeners();
  }

  void setSearchKeyword(String keyword) {
    _state = _state.copyWith(searchKeyword: keyword);
    _cachedFilteredConnections = null;
    Logger.debug('连接搜索关键字已设置为: $keyword');
    notifyListeners();
  }

  List<ConnectionInfo> _getFilteredConnections() {
    List<ConnectionInfo> filteredConnections = _state.connections;

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
        break;
    }

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

  bool _hasConnectionsChanged(
    List<ConnectionInfo> oldConnections,
    List<ConnectionInfo> nextConnections,
  ) {
    if (oldConnections.length != nextConnections.length) {
      return true;
    }

    if (oldConnections.isEmpty) {
      return false;
    }

    final previousIds = oldConnections.map((c) => c.id).toSet();
    final currentIds = nextConnections.map((c) => c.id).toSet();

    return !previousIds.containsAll(currentIds) ||
        !currentIds.containsAll(previousIds);
  }

  Future<bool> closeConnection(String connectionId) async {
    return _executeConnectionOperation(
      () => ClashManager.instance.closeConnection(connectionId),
      '关闭连接',
      '连接已关闭: $connectionId',
    );
  }

  Future<bool> closeAllConnections() async {
    return _executeConnectionOperation(
      ClashManager.instance.closeAllConnections,
      '关闭所有连接',
      '所有连接已关闭',
    );
  }

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
      }
      return success;
    } catch (e) {
      Logger.error('$operationName失败：$e');
      return false;
    }
  }

  @override
  void dispose() {
    _stopMonitoring();
    _clashProvider.removeListener(_onClashStateChanged);
    super.dispose();
  }
}
