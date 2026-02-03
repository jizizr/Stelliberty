import 'dart:io';

import 'package:stelliberty/clash/client/clash_core_client.dart';
import 'package:stelliberty/clash/config/clash_defaults.dart';
import 'package:stelliberty/clash/services/delay_test_service.dart';
import 'package:stelliberty/services/log_print_service.dart';

// Clash 代理管理器
// 负责代理节点的切换、延迟测试
class ProxyManager {
  final ClashCoreClient _coreClient;
  final bool Function() _isCoreRunning;
  final String Function() _getTestUrl;

  ProxyManager({
    required ClashCoreClient coreClient,
    required bool Function() isCoreRunning,
    required String Function() getTestUrl,
  }) : _coreClient = coreClient,
       _isCoreRunning = isCoreRunning,
       _getTestUrl = getTestUrl;

  // 获取代理列表
  Future<Map<String, dynamic>> getProxies() async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.getProxies();
  }

  // 切换代理节点
  Future<bool> changeProxy(String groupName, String proxyName) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    final wasSuccessful = await _coreClient.changeProxy(groupName, proxyName);

    // 切换节点后关闭所有现有连接，确保立即生效
    if (wasSuccessful) {
      await _coreClient.closeAllConnections();
    }

    return wasSuccessful;
  }

  // 测试代理延迟（使用 ClashCoreClient）
  Future<int> testProxyDelay(String proxyName, {String? testUrl}) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.testProxyDelay(
      proxyName,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 测试单个代理节点延迟
  // Android 平台使用 JNI，桌面平台使用 Rust IPC
  Future<int> testProxyDelayViaRust(String proxyName, {String? testUrl}) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    if (Platform.isAndroid) {
      return await _coreClient.testProxyDelay(
        proxyName,
        testUrl: testUrl ?? _getTestUrl(),
      );
    }

    return await DelayTestService.testProxyDelay(
      proxyName,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 批量测试代理节点延迟
  // Android 平台使用 JNI 并发测试，桌面平台使用 Rust IPC
  Future<Map<String, int>> testGroupDelays(
    List<String> proxyNames, {
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    if (Platform.isAndroid) {
      return await _testGroupDelaysViaJni(
        proxyNames,
        testUrl: testUrl,
        onNodeStart: onNodeStart,
        onNodeComplete: onNodeComplete,
      );
    }

    return await DelayTestService.testGroupDelays(
      proxyNames,
      testUrl: testUrl ?? _getTestUrl(),
      onNodeStart: onNodeStart,
      onNodeComplete: onNodeComplete,
    );
  }

  // Android 平台：通过 JNI 并发测试延迟
  Future<Map<String, int>> _testGroupDelaysViaJni(
    List<String> proxyNames, {
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    final results = <String, int>{};
    final url = testUrl ?? _getTestUrl();
    final concurrency = ClashDefaults.delayTestConcurrency;

    Logger.info('开始批量延迟测试（JNI）：${proxyNames.length} 个节点，并发数=$concurrency');

    // 分批并发测试
    for (var i = 0; i < proxyNames.length; i += concurrency) {
      final batch = proxyNames.skip(i).take(concurrency).toList();
      final batchIndex = i ~/ concurrency + 1;
      final totalBatches = (proxyNames.length + concurrency - 1) ~/ concurrency;
      Logger.debug('测试批次 $batchIndex/$totalBatches：${batch.join(', ')}');

      final futures = batch.map((nodeName) async {
        onNodeStart?.call(nodeName);
        final delay = await _coreClient.testProxyDelay(nodeName, testUrl: url);
        results[nodeName] = delay;
        Logger.debug('节点 $nodeName 延迟：${delay == -1 ? "超时" : "${delay}ms"}');
        onNodeComplete?.call(nodeName, delay);
      });
      await Future.wait(futures);
    }

    final successCount = results.values.where((d) => d > 0).length;
    Logger.info(
      '批量延迟测试完成：成功=$successCount，超时=${results.length - successCount}',
    );

    return results;
  }
}
