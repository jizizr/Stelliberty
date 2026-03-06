import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rinf/rinf.dart';
import 'package:stelliberty/clash/services/vpn_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 内存数据
class MemoryData {
  final int inuse;
  final int oslimit;
  final DateTime timestamp;

  MemoryData({
    required this.inuse,
    required this.oslimit,
    required this.timestamp,
  });
}

// 核心内存监控服务
class MemoryService {
  static final MemoryService instance = MemoryService._();
  MemoryService._();

  StreamController<MemoryData>? _controller;
  StreamSubscription<RustSignalPack<IpcMemoryData>>? _desktopSubscription;
  StreamSubscription<String>? _androidSubscription;
  bool _isMonitoring = false;

  // 内存数据流（供外部监听）
  Stream<MemoryData>? get memoryStream => _controller?.stream;

  // 是否正在监控
  bool get isMonitoring => _isMonitoring;

  // 开始监控
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _controller ??= StreamController<MemoryData>.broadcast();

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
    _desktopSubscription = IpcMemoryData.rustSignalStream.listen(
      _handleDesktopMemoryData,
      onError: (error) {
        Logger.error('内存监控流错误：$error');
      },
    );

    const StartMemoryStream().sendSignalToRust();
    Logger.info('内存监控已启动 (WebSocket 模式)');
  }

  // 桌面端：停止 WebSocket 流
  void _stopDesktopStream() {
    const StopMemoryStream().sendSignalToRust();
    _desktopSubscription?.cancel();
    _desktopSubscription = null;
    Logger.info('内存监控已停止 (WebSocket 模式)');
  }

  // Android：启动事件流
  void _startAndroidStream() {
    _androidSubscription?.cancel();
    VpnService.invokeAction(method: 'startMemory');
    _androidSubscription = VpnService.coreLogStream?.listen(
      _handleAndroidEvent,
      onError: (error) {
        Logger.error('内存监控流错误：$error');
      },
    );
    Logger.info('内存监控已启动 (Android 推送模式)');
  }

  // Android：停止事件流
  void _stopAndroidStream() {
    VpnService.invokeAction(method: 'stopMemory');
    _androidSubscription?.cancel();
    _androidSubscription = null;
    Logger.info('内存监控已停止 (Android 推送模式)');
  }

  // 桌面端：处理内存数据
  void _handleDesktopMemoryData(RustSignalPack<IpcMemoryData> signal) {
    final data = MemoryData(
      inuse: signal.message.inuse.toInt(),
      oslimit: signal.message.oslimit.toInt(),
      timestamp: DateTime.now(),
    );
    _controller?.add(data);
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
      if (messageType != 'memory') return;

      final memoryData = data['data'] as Map<String, dynamic>?;
      if (memoryData == null) return;

      final inuse = memoryData['inuse'];
      final oslimit = memoryData['oslimit'];
      if (inuse == null) return;

      final inuseInt = (inuse is int) ? inuse : int.tryParse(inuse.toString());
      final oslimitInt = (oslimit is int)
          ? oslimit
          : (int.tryParse(oslimit?.toString() ?? '0') ?? 0);
      if (inuseInt == null) return;

      final data2 = MemoryData(
        inuse: inuseInt,
        oslimit: oslimitInt,
        timestamp: DateTime.now(),
      );
      _controller?.add(data2);
    } catch (e) {
      Logger.warning('处理内存事件失败：$e');
    }
  }

  // 清理资源
  void dispose() {
    stopMonitoring();
  }
}
