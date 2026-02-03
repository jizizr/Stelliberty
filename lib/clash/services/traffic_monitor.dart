import 'dart:async';
import 'package:stelliberty/clash/model/traffic_data_model.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// Clash 流量监控服务
// 纯技术实现：通过 IPC 接收 Rust 信号并转发原始流量数据
class TrafficMonitor {
  static final TrafficMonitor instance = TrafficMonitor._();
  TrafficMonitor._();

  StreamController<TrafficData>? _controller;
  StreamSubscription? _trafficSubscription;
  bool _isMonitoring = false;

  // 流量数据流（供外部监听）
  Stream<TrafficData>? get trafficStream => _controller?.stream;

  // 是否正在监控
  bool get isMonitoring => _isMonitoring;

  // 开始监控流量（IPC 模式）
  Future<void> startMonitoring([String? _]) async {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // 创建流控制器
    _controller ??= StreamController<TrafficData>.broadcast();

    // 监听来自 Rust 的流量数据
    _trafficSubscription = IpcTrafficData.rustSignalStream.listen((signal) {
      _handleTrafficData(signal.message);
    });

    // 发送启动流量监控信号到 Rust
    const StartTrafficStream().sendSignalToRust();
    Logger.info('流量监控已启动 (IPC 模式)');
  }

  // 停止监控流量
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    _isMonitoring = false;

    // 发送停止信号到 Rust
    const StopTrafficStream().sendSignalToRust();

    // 取消 Rust 流订阅
    await _trafficSubscription?.cancel();
    _trafficSubscription = null;

    Logger.info('流量监控已停止');
  }

  // 处理来自 Rust 的流量数据
  void _handleTrafficData(IpcTrafficData data) {
    try {
      // 将 Uint64 转换为 int
      final uploadInt = data.upload.toInt();
      final downloadInt = data.download.toInt();

      // 创建 TrafficData 对象并转发
      final trafficData = TrafficData(
        upload: uploadInt,
        download: downloadInt,
        timestamp: DateTime.now(),
      );

      // 推送到流
      _controller?.add(trafficData);
    } catch (e) {
      Logger.error('处理流量数据失败：$e');
    }
  }

  // 清理资源
  void dispose() {
    stopMonitoring();
  }
}
