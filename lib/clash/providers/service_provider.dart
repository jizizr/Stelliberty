import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/state/service_states.dart';
import 'package:stelliberty/clash/manager/service_manager.dart';
import 'package:stelliberty/services/log_print_service.dart';

// Clash 服务模式状态管理
class ServiceProvider extends ChangeNotifier {
  final ServiceManager _manager = ServiceManager.instance;

  // 服务状态
  ServiceState _serviceState = ServiceState.unknown;
  ServiceState get serviceState => _serviceState;

  // 最后的操作结果
  String? _lastOperationError;
  bool? _wasLastOperationSuccessful;

  ServiceState get status => _serviceState;
  bool get isServiceModeInstalled => _serviceState.isServiceModeInstalled;
  bool get isServiceModeRunning => _serviceState.isServiceModeRunning;
  bool get isServiceModeProcessing => _serviceState.isServiceModeProcessing;
  String? get lastOperationError => _lastOperationError;
  bool? get wasLastOperationSuccessful => _wasLastOperationSuccessful;

  // 更新服务状态
  void _updateServiceState(ServiceState nextState) {
    if (_serviceState == nextState) return;

    final previousState = _serviceState;
    _serviceState = nextState;
    Logger.debug('服务状态变化：${previousState.name} -> ${nextState.name}');
    notifyListeners();
  }

  // 清除最后的操作结果
  void clearLastOperationResult() {
    _lastOperationError = null;
    _wasLastOperationSuccessful = null;
    notifyListeners();
  }

  // 初始化服务状态
  Future<void> initialize() async {
    await refreshStatus();
  }

  // 刷新服务状态
  Future<void> refreshStatus() async {
    final nextState = await _manager.refreshStatus();
    _updateServiceState(nextState);
  }

  // 安装服务
  Future<bool> installService() async {
    if (isServiceModeProcessing) return false;

    _updateServiceState(ServiceState.installing);
    _wasLastOperationSuccessful = null;
    _lastOperationError = null;

    final (success, error) = await _manager.installService();

    _wasLastOperationSuccessful = success;
    _lastOperationError = error;

    // 刷新状态
    await refreshStatus();

    return success;
  }

  // 卸载服务
  Future<bool> uninstallService() async {
    if (isServiceModeProcessing) return false;

    _updateServiceState(ServiceState.uninstalling);
    _wasLastOperationSuccessful = null;
    _lastOperationError = null;

    final (success, error) = await _manager.uninstallService();

    _wasLastOperationSuccessful = success;
    _lastOperationError = error;

    if (success) {
      _updateServiceState(ServiceState.notInstalled);
    } else {
      // 失败时刷新状态
      await refreshStatus();
    }

    return success;
  }
}
