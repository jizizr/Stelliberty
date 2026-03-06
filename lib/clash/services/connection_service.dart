import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:stelliberty/clash/model/connection_model.dart';
import 'package:stelliberty/clash/services/vpn_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 连接监控服务
class ConnectionService {
  static final ConnectionService instance = ConnectionService._();
  ConnectionService._();

  StreamController<List<ConnectionInfo>>? _controller;
  StreamSubscription? _desktopSubscription;
  StreamSubscription<String>? _androidSubscription;
  bool _isMonitoring = false;

  // 连接数据流（供外部监听）
  Stream<List<ConnectionInfo>>? get connectionStream => _controller?.stream;

  // 是否正在监控
  bool get isMonitoring => _isMonitoring;

  // 开始监控
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _controller ??= StreamController<List<ConnectionInfo>>.broadcast();

    if (Platform.isAndroid) {
      _startAndroidStream();
    } else {
      _startDesktopStream();
    }
  }

  // 停止监控
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    _isMonitoring = false;

    if (Platform.isAndroid) {
      _stopAndroidStream();
    } else {
      _stopDesktopStream();
    }
  }

  // 桌面端：启动 WebSocket 流
  void _startDesktopStream() {
    _desktopSubscription?.cancel();
    _desktopSubscription = IpcConnectionData.rustSignalStream.listen(
      (signal) {
        _handleConnectionsData(signal.message.connectionsJson);
      },
      onError: (error) {
        Logger.error('连接监控流错误：$error');
      },
    );

    const StartConnectionStream().sendSignalToRust();
    Logger.info('连接监控已启动 (WebSocket 模式)');
  }

  // 桌面端：停止 WebSocket 流
  void _stopDesktopStream() {
    const StopConnectionStream().sendSignalToRust();
    _desktopSubscription?.cancel();
    _desktopSubscription = null;
    Logger.info('连接监控已停止 (WebSocket 模式)');
  }

  // Android：启动事件流
  void _startAndroidStream() {
    _androidSubscription?.cancel();
    VpnService.invokeAction(method: 'startConnections');
    _androidSubscription = VpnService.coreLogStream?.listen(
      _handleAndroidEvent,
      onError: (error) {
        Logger.error('连接监控流错误：$error');
      },
    );
    Logger.info('连接监控已启动 (Android 推送模式)');
  }

  // Android：停止事件流
  void _stopAndroidStream() {
    VpnService.invokeAction(method: 'stopConnections');
    _androidSubscription?.cancel();
    _androidSubscription = null;
    Logger.info('连接监控已停止 (Android 推送模式)');
  }

  // Android：处理事件
  void _handleAndroidEvent(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final method = json['method'] as String?;
      if (method != 'message') return;

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final messageType = data['type'] as String?;
      if (messageType != 'connections') return;

      final connectionsData = data['data'];
      if (connectionsData != null) {
        _handleConnectionsData(connectionsData);
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

      _controller?.add(connections);
    } catch (e) {
      Logger.error('解析连接数据失败：$e');
    }
  }

  // 清理资源
  void dispose() {
    stopMonitoring();
  }
}
