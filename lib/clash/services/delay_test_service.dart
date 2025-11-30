import 'package:stelliberty/clash/data/clash_model.dart';
import 'package:stelliberty/clash/config/clash_defaults.dart';
import 'package:stelliberty/clash/utils/delay_tester.dart';
import 'package:stelliberty/utils/logger.dart';

// 延迟测试服务
// 封装所有与代理延迟测试相关的方法
// 使用服务类模式替代 Mixin，提高代码可读性和可测试性
class DelayTestService {
  // 递归解析代理节点名称
  // 如果输入的是代理组，会递归查找到最终的实际代理节点
  // 优先级：selectedMap > 默认第一个
  // 增加了循环检测，防止无限递归
  static String resolveProxyNodeName(
    String proxyName,
    Map<String, ProxyNode> proxyNodes,
    List<ProxyGroup> allProxyGroups,
    Map<String, String> selectedMap, {
    int maxDepth = 20,
    Set<String>? visited,
  }) {
    // 初始化已访问集合（用于循环检测）
    visited ??= {};

    // 检查深度限制
    if (maxDepth <= 0) {
      Logger.warning('代理组递归深度过深（超过20层）：$proxyName');
      return proxyName;
    }

    // 循环检测：如果已经访问过这个节点，说明有循环引用
    if (visited.contains(proxyName)) {
      Logger.warning('检测到代理组循环引用：${visited.join(' -> ')} -> $proxyName');
      return proxyName;
    }

    final node = proxyNodes[proxyName];
    if (node == null) {
      Logger.warning('代理节点不存在：$proxyName');
      return proxyName;
    }

    // 如果是实际的代理节点，直接返回
    if (node.isProxy) {
      return proxyName;
    }

    // 如果是代理组，查找其当前选中的节点
    if (node.isGroup) {
      final group = allProxyGroups.firstWhere(
        (g) => g.name == proxyName,
        orElse: () => ProxyGroup(name: proxyName, type: '', all: []),
      );

      String selectedProxy = '';

      // 1. 优先从 selectedMap 获取
      if (selectedMap.containsKey(proxyName)) {
        selectedProxy = selectedMap[proxyName]!;
        Logger.debug('从 selectedMap 获取选择：$proxyName -> $selectedProxy');
      }

      // 2. 如果 selectedMap 中没有，回退到第一个节点
      if (selectedProxy.isEmpty && group.all.isNotEmpty) {
        selectedProxy = group.all.first;
        Logger.debug('使用默认选择（第一个）：$proxyName -> $selectedProxy');
      }

      if (selectedProxy.isNotEmpty) {
        // 添加当前节点到已访问集合
        final newVisited = Set<String>.from(visited)..add(proxyName);

        // 递归查找真实的代理节点
        return resolveProxyNodeName(
          selectedProxy,
          proxyNodes,
          allProxyGroups,
          selectedMap,
          maxDepth: maxDepth - 1,
          visited: newVisited,
        );
      }
    }

    return proxyName;
  }

  // 测试代理延迟（支持代理组）
  // 使用 Clash API 进行统一延迟测试（需要 Clash 正在运行）
  // 注意：此方法不修改传入的 proxyNodes Map，仅返回延迟值
  //
  // 重要：不递归解析代理组，直接测试传入的节点名称
  // 如果是代理组，Clash API 会测试该代理组当前选中的节点
  static Future<int> testProxyDelay(
    String proxyName,
    Map<String, ProxyNode> proxyNodes,
    List<ProxyGroup> allProxyGroups,
    Map<String, String> selectedMap, {
    String? testUrl,
  }) async {
    final node = proxyNodes[proxyName];
    if (node == null) {
      Logger.warning('代理节点不存在：$proxyName');
      return -1;
    }

    // 关键：检查 DelayTester 是否可用（即 Clash API 客户端是否已设置）
    if (!DelayTester.isAvailable) {
      Logger.error('Clash 未运行或 API 未就绪，无法进行延迟测试。请先启动 Clash。');
      return -1;
    }

    Logger.debug('测试延迟：$proxyName (通过 Clash API)');
    final delay = await DelayTester.testProxyDelay(node, testUrl: testUrl);

    return delay;
  }

  // 批量测试代理组中所有节点的延迟
  // 使用并发测试以提高效率，根据 CPU 核心数动态调整并发数
  // 每个节点测试完成后立即更新 UI，而不是等待整批完成
  static Future<Map<String, int>> testGroupDelays(
    String groupName,
    Map<String, ProxyNode> proxyNodes,
    List<ProxyGroup> allProxyGroups,
    Map<String, String> selectedMap, {
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    final group = allProxyGroups.firstWhere(
      (g) => g.name == groupName,
      orElse: () => throw Exception('Group not found: $groupName'),
    );

    // 获取所有要测试的代理名称（包括代理组和实际节点）
    final proxyNames = group.all.where((proxyName) {
      final node = proxyNodes[proxyName];
      return node != null; // 只要存在就可以测试
    }).toList();

    if (proxyNames.isEmpty) {
      Logger.warning('代理组 $groupName 中没有可测试的节点');
      return {};
    }

    // 使用动态并发数（基于 CPU 核心数）
    final concurrency = ClashDefaults.dynamicDelayTestConcurrency;
    Logger.info(
      '开始测试代理组 $groupName 中的 ${proxyNames.length} 个项目（并发数：$concurrency）',
    );

    // 存储所有节点的延迟结果
    final delayResults = <String, int>{};
    int successCount = 0;
    int completedCount = 0;

    // 分批处理，避免并发过多
    for (int i = 0; i < proxyNames.length; i += concurrency) {
      final batch = proxyNames.skip(i).take(concurrency).toList();

      // 启动这一批的所有测试，每个节点测试完成后立即回调
      final futures = batch.map((proxyName) async {
        // 通知节点开始测试
        onNodeStart?.call(proxyName);

        // 执行测试
        final delay = await testProxyDelay(
          proxyName,
          proxyNodes,
          allProxyGroups,
          selectedMap,
          testUrl: testUrl,
        );

        // 保存延迟结果
        delayResults[proxyName] = delay;

        // 更新成功计数
        if (delay > 0) {
          successCount++;
        }

        completedCount++;

        // 通知节点测试完成
        onNodeComplete?.call(proxyName, delay);

        Logger.debug('已完成 $completedCount/${proxyNames.length} 个代理的延迟测试');
      }).toList();

      // 等待这一批全部完成后再开始下一批
      await Future.wait(futures);

      Logger.info('已完成 ${i + batch.length}/${proxyNames.length} 个代理的延迟测试');
    }

    Logger.info('延迟测试完成，成功：$successCount/${proxyNames.length}');

    return delayResults;
  }
}
