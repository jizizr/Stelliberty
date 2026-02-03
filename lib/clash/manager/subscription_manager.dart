import 'package:stelliberty/clash/model/subscription_model.dart';
import 'package:stelliberty/clash/model/override_model.dart';
import 'package:stelliberty/clash/services/subscription_service.dart';
import 'package:stelliberty/clash/services/override_service.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 订阅管理器
// 负责订阅相关的业务逻辑
class SubscriptionManager {
  final SubscriptionService _service;
  final bool Function() _isCoreRunning;
  final int Function() _getMixedPort;

  SubscriptionManager({
    required SubscriptionService service,
    required bool Function() isCoreRunning,
    required int Function() getMixedPort,
  }) : _service = service,
       _isCoreRunning = isCoreRunning,
       _getMixedPort = getMixedPort;

  // 设置覆写获取器
  void setOverrideGetter(
    Future<List<OverrideConfig>> Function(List<String>) getter,
  ) {
    _service.setOverrideGetter(getter);
  }

  // 设置覆写服务
  void setOverrideService(OverrideService overrideService) {
    _service.setOverrideService(overrideService);
  }

  // 初始化服务
  Future<void> initialize() async {
    await _service.initialize();
  }

  // 加载订阅列表
  Future<List<Subscription>> loadSubscriptionList() async {
    return await _service.loadSubscriptionList();
  }

  // 保存订阅列表
  Future<void> saveSubscriptionList(List<Subscription> subscriptions) async {
    await _service.saveSubscriptionList(subscriptions);
  }

  // 保存本地订阅
  Future<void> saveLocalSubscription(
    Subscription subscription,
    String content,
  ) async {
    await _service.saveLocalSubscription(subscription, content);
  }

  // 删除订阅
  Future<void> deleteSubscription(Subscription subscription) async {
    await _service.deleteSubscription(subscription);
  }

  // 根据 ID 列表获取覆写
  Future<List<OverrideConfig>> getOverridesByIds(List<String> ids) async {
    return await _service.getOverridesByIds(ids);
  }

  // 读取订阅配置文件
  Future<String> readSubscriptionConfig(Subscription subscription) async {
    return await _service.readSubscriptionConfig(subscription);
  }

  // 导入本地文件
  Future<String> importLocalFile(String filePath) async {
    return await _service.parseLocalFile(filePath);
  }

  // 下载订阅
  // 根据 Clash 运行状态自动选择代理模式
  Future<Subscription> downloadSubscription(Subscription subscription) async {
    final isClashRunning = _isCoreRunning();

    final effectiveProxyMode = isClashRunning
        ? subscription.proxyMode
        : SubscriptionProxyMode.direct;

    if (!isClashRunning &&
        subscription.proxyMode != SubscriptionProxyMode.direct) {
      Logger.warning(
        'Clash 未运行，强制使用直连模式（用户配置: ${subscription.proxyMode.value}）',
      );
    }

    final mixedPort = _getMixedPort();

    return await _service.downloadSubscription(
      subscription,
      effectiveProxyMode,
      mixedPort,
    );
  }
}
