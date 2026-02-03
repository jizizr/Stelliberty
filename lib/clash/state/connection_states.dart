import 'package:stelliberty/clash/model/connection_model.dart';

enum ConnectionFilterLevel {
  all, // 全部连接
  direct, // 直连
  proxy, // 代理
}

// 连接列表状态
class ConnectionState {
  final List<ConnectionInfo> connections; // 原始连接列表
  final bool isLoading;
  final bool isMonitoringPaused; // 是否暂停监控
  final ConnectionFilterLevel filterLevel; // 过滤级别
  final String searchKeyword; // 搜索关键字
  final String? errorMessage;

  const ConnectionState({
    required this.connections,
    required this.isLoading,
    required this.isMonitoringPaused,
    required this.filterLevel,
    required this.searchKeyword,
    this.errorMessage,
  });

  // 简单辅助方法
  bool get isEmpty => connections.isEmpty;
  bool get hasConnections => connections.isNotEmpty;
  int get connectionCount => connections.length;
  bool get hasError => errorMessage != null;
  bool get hasSearchKeyword => searchKeyword.isNotEmpty;

  factory ConnectionState.initial() {
    return const ConnectionState(
      connections: [],
      isLoading: false,
      isMonitoringPaused: false,
      filterLevel: ConnectionFilterLevel.all,
      searchKeyword: '',
    );
  }

  ConnectionState copyWith({
    List<ConnectionInfo>? connections,
    bool? isLoading,
    bool? isMonitoringPaused,
    ConnectionFilterLevel? filterLevel,
    String? searchKeyword,
    String? errorMessage,
  }) {
    return ConnectionState(
      connections: connections ?? this.connections,
      isLoading: isLoading ?? this.isLoading,
      isMonitoringPaused: isMonitoringPaused ?? this.isMonitoringPaused,
      filterLevel: filterLevel ?? this.filterLevel,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
