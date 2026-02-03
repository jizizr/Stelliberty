import 'package:stelliberty/clash/model/log_message_model.dart';

// 核心日志状态
class CoreLogState {
  final List<ClashLogMessage> logs; // 日志列表
  final bool isMonitoringPaused; // 是否暂停监控
  final ClashLogLevel? filterLevel; // 过滤级别
  final String searchKeyword; // 搜索关键字
  final bool isLoading; // 是否正在加载

  const CoreLogState({
    required this.logs,
    required this.isMonitoringPaused,
    this.filterLevel,
    required this.searchKeyword,
    required this.isLoading,
  });

  // 简单辅助方法
  bool get isEmpty => logs.isEmpty;
  bool get hasLogs => logs.isNotEmpty;
  int get logCount => logs.length;
  bool get hasFilter => filterLevel != null || searchKeyword.isNotEmpty;
  bool get hasSearchKeyword => searchKeyword.isNotEmpty;

  factory CoreLogState.initial() {
    return const CoreLogState(
      logs: [],
      isMonitoringPaused: false,
      searchKeyword: '',
      isLoading: false,
    );
  }

  CoreLogState copyWith({
    List<ClashLogMessage>? logs,
    bool? isMonitoringPaused,
    Object? filterLevel = _undefined,
    String? searchKeyword,
    bool? isLoading,
  }) {
    return CoreLogState(
      logs: logs ?? this.logs,
      isMonitoringPaused: isMonitoringPaused ?? this.isMonitoringPaused,
      filterLevel: filterLevel == _undefined
          ? this.filterLevel
          : filterLevel as ClashLogLevel?,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Sentinel 值，用于区分"未传入参数"和"传入 null"
const Object _undefined = Object();
