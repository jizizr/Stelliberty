import 'package:stelliberty/clash/model/override_model.dart';
import 'package:stelliberty/clash/model/subscription_model.dart';
import 'package:stelliberty/clash/services/override_service.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 覆写管理器
// 负责覆写相关的业务逻辑
class OverrideManager {
  final OverrideService _service;
  final bool Function() _isCoreRunning;
  final int Function() _getMixedPort;
  final String Function() _getDefaultUserAgent;

  OverrideManager({
    required OverrideService service,
    required bool Function() isCoreRunning,
    required int Function() getMixedPort,
    required String Function() getDefaultUserAgent,
  }) : _service = service,
       _isCoreRunning = isCoreRunning,
       _getMixedPort = getMixedPort,
       _getDefaultUserAgent = getDefaultUserAgent;

  // 下载远程覆写
  // 根据 Clash 运行状态自动选择代理模式
  Future<String> downloadRemoteOverride(OverrideConfig override) async {
    final isClashRunning = _isCoreRunning();

    final effectiveProxyMode = isClashRunning
        ? override.proxyMode
        : SubscriptionProxyMode.direct;

    if (!isClashRunning && override.proxyMode != SubscriptionProxyMode.direct) {
      Logger.warning('Clash 未运行，强制使用直连模式（用户配置：${override.proxyMode.value}）');
    }

    final userAgent = _getDefaultUserAgent();
    final mixedPort = _getMixedPort();

    return await _service.downloadRemoteOverride(
      override,
      effectiveProxyMode,
      userAgent,
      mixedPort,
    );
  }

  // 保存覆写内容
  Future<void> saveOverrideContent(
    OverrideConfig override,
    String content,
  ) async {
    await _service.saveOverrideContent(override, content);
  }

  // 保存本地覆写
  Future<String> saveLocalOverride(
    OverrideConfig override,
    String sourceFilePath,
  ) async {
    return await _service.saveLocalOverride(override, sourceFilePath);
  }

  // 删除覆写
  Future<void> deleteOverride(String id, OverrideFormat format) async {
    await _service.deleteOverride(id, format);
  }

  // 获取覆写内容
  Future<String> getOverrideContent(String id, OverrideFormat format) async {
    return await _service.getOverrideContent(id, format);
  }
}
