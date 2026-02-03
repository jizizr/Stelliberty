import 'dart:io';
import 'dart:async';
import 'package:stelliberty/clash/model/override_model.dart' as data;
import 'package:stelliberty/clash/model/subscription_model.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart' as signals;
import 'package:stelliberty/clash/config/clash_defaults.dart';

// 覆写服务
// 纯技术实现：文件操作、网络下载、Rust 调用
class OverrideService {
  // 覆写目录路径（从 PathService 获取）
  String get overridesDir => PathService.instance.overridesDir;

  // 初始化覆写目录
  Future<void> initialize() async {
    // 目录创建已由 PathService 统一管理
    Logger.info('覆写服务初始化完成，路径：$overridesDir');
  }

  // 保存本地覆写（复制文件内容）
  Future<String> saveLocalOverride(
    data.OverrideConfig config,
    String sourceFilePath,
  ) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourceFilePath');
      }

      // 读取源文件内容
      final content = await sourceFile.readAsString();

      // 保存到覆写目录
      final targetPath = _getOverridePath(config.id, config.format);
      final targetFile = File(targetPath);
      await targetFile.writeAsString(content);

      Logger.info('本地覆写已保存：${config.name} -> $targetPath');
      return content;
    } catch (e) {
      Logger.error('保存本地覆写失败：${config.name} - $e');
      rethrow;
    }
  }

  // 保存覆写内容（直接使用提供的内容）
  Future<void> saveOverrideContent(
    data.OverrideConfig config,
    String content,
  ) async {
    try {
      // 保存到覆写目录
      final targetPath = _getOverridePath(config.id, config.format);
      final targetFile = File(targetPath);
      await targetFile.writeAsString(content);

      Logger.info('覆写内容已保存：${config.name} -> $targetPath');
    } catch (e) {
      Logger.error('保存覆写内容失败：${config.name} - $e');
      rethrow;
    }
  }

  // 下载远程覆写
  // proxyMode: 由调用者决定使用的代理模式
  Future<String> downloadRemoteOverride(
    data.OverrideConfig config,
    SubscriptionProxyMode proxyMode,
    String userAgent,
    int mixedPort,
  ) async {
    if (config.url == null || config.url!.isEmpty) {
      throw Exception('远程 URL 为空');
    }

    // 使用覆写 ID 作为请求标识符
    final requestId = config.id;

    try {
      // 转换代理模式
      final signalProxyMode = _convertProxyMode(proxyMode);

      // 创建 Completer 等待响应
      final completer = Completer<signals.DownloadOverrideResponse>();
      StreamSubscription? subscription;

      try {
        // 订阅 Rust 响应流，只接收匹配的 request_id
        subscription = signals.DownloadOverrideResponse.rustSignalStream.listen(
          (result) {
            if (!completer.isCompleted &&
                result.message.requestId == requestId) {
              completer.complete(result.message);
              subscription?.cancel();
            }
          },
        );

        // 发送下载请求到 Rust 层
        signals.DownloadOverrideRequest(
          requestId: requestId,
          url: config.url!,
          proxyMode: signalProxyMode,
          userAgent: userAgent,
          timeoutSeconds: signals.Uint64(
            BigInt.from(ClashDefaults.overrideDownloadTimeout),
          ),
          mixedPort: mixedPort,
        ).sendSignalToRust();

        // 等待响应
        final response = await completer.future.timeout(
          Duration(seconds: ClashDefaults.overrideDownloadTimeout + 5),
          onTimeout: () {
            throw Exception('覆写下载超时');
          },
        );

        if (!response.isSuccessful) {
          throw Exception(response.errorMessage ?? '下载失败');
        }

        final content = response.content;
        if (content.isEmpty) {
          throw Exception('下载的内容为空');
        }

        // 保存到本地
        final targetPath = _getOverridePath(config.id, config.format);
        final targetFile = File(targetPath);
        await targetFile.writeAsString(content);

        Logger.debug('覆写已保存至：$targetPath');
        return content;
      } finally {
        await subscription?.cancel();
      }
    } catch (e) {
      Logger.error('下载远程覆写失败：${config.name} - $e');
      rethrow;
    }
  }

  // 转换代理模式枚举
  signals.ProxyMode _convertProxyMode(SubscriptionProxyMode mode) {
    return switch (mode) {
      SubscriptionProxyMode.direct => signals.ProxyMode.direct,
      SubscriptionProxyMode.system => signals.ProxyMode.system,
      SubscriptionProxyMode.core => signals.ProxyMode.core,
    };
  }

  // 读取覆写文件内容
  Future<String> getOverrideContent(
    String id,
    data.OverrideFormat format,
  ) async {
    try {
      final filePath = _getOverridePath(id, format);
      final file = File(filePath);

      if (!await file.exists()) {
        Logger.warning('覆写文件不存在：$filePath');
        return '';
      }

      return await file.readAsString();
    } catch (e) {
      Logger.error('读取覆写文件失败：$id - $e');
      return '';
    }
  }

  // 删除覆写文件
  Future<void> deleteOverride(String id, data.OverrideFormat format) async {
    try {
      final filePath = _getOverridePath(id, format);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        Logger.info('覆写文件已删除：$filePath');
      }
    } catch (e) {
      Logger.error('删除覆写文件失败：$id - $e');
      rethrow;
    }
  }

  // 检查覆写文件是否存在
  Future<bool> overrideExists(String id, data.OverrideFormat format) async {
    final filePath = _getOverridePath(id, format);
    return await File(filePath).exists();
  }

  // 获取覆写文件路径
  String _getOverridePath(String id, data.OverrideFormat format) {
    final ext = format == data.OverrideFormat.yaml ? 'yaml' : 'js';
    return PathService.instance.getOverridePath(id, ext);
  }

  // 应用覆写列表到订阅配置
  // 返回应用覆写后的配置内容
  Future<String> applyOverrides(
    String baseConfigContent,
    List<data.OverrideConfig> overrides,
  ) async {
    Logger.debug('applyOverrides');
    Logger.debug('基础配置长度：${baseConfigContent.length} 字符');
    Logger.debug('覆写数量：${overrides.length}');

    // 准备覆写配置列表（读取文件内容）
    final overrideConfigs = <signals.OverrideConfig>[];
    for (var i = 0; i < overrides.length; i++) {
      final override = overrides[i];
      try {
        Logger.info(
          '[$i] 准备覆写: ${override.name} (${override.format.displayName})',
        );

        // 读取覆写文件内容
        final overrideContent = await getOverrideContent(
          override.id,
          override.format,
        );

        Logger.debug('[$i] 覆写文件内容长度：${overrideContent.length} 字符');

        if (overrideContent.isEmpty) {
          Logger.warning('[$i] 覆写文件为空，跳过：${override.name}');
          continue;
        }

        // 转换为 Rinf 的 OverrideConfig
        overrideConfigs.add(
          signals.OverrideConfig(
            id: override.id,
            name: override.name,
            format: _convertFormat(override.format),
            content: overrideContent,
          ),
        );
      } catch (e) {
        final errorMsg = '准备覆写失败：${override.name} - $e';
        Logger.error('[$i] $errorMsg');
        // 继续处理下一个覆写，不中断整个流程
      }
    }

    if (overrideConfigs.isEmpty) {
      Logger.info('没有有效的覆写配置，返回原始配置');
      return baseConfigContent;
    }

    // 调用 Rust 处理所有覆写
    Logger.info('调用 Rust 处理 ${overrideConfigs.length} 个覆写…');
    try {
      final request = signals.ApplyOverridesRequest(
        baseConfigContent: baseConfigContent,
        overrides: overrideConfigs,
      );

      // 发送请求到 Rust
      request.sendSignalToRust();

      // 等待 Rust 响应
      final response =
          await signals.ApplyOverridesResponse.rustSignalStream.first;
      final result = response.message;

      if (!result.isSuccessful) {
        Logger.error('Rust 覆写处理失败：${result.errorMessage}');
        throw Exception('Rust 覆写处理失败：${result.errorMessage}');
      }

      Logger.info('Rust 覆写处理成功');
      Logger.debug('最终配置长度：${result.resultConfig.length} 字符');

      return result.resultConfig;
    } catch (e) {
      final errorMsg = 'Rust 覆写处理异常：$e';
      Logger.error(errorMsg);
      throw Exception(errorMsg);
    }
  }

  // 转换 Dart OverrideFormat 到 Rinf OverrideFormat
  signals.OverrideFormat _convertFormat(data.OverrideFormat format) {
    switch (format) {
      case data.OverrideFormat.yaml:
        return signals.OverrideFormat.yaml;
      case data.OverrideFormat.js:
        return signals.OverrideFormat.javascript;
    }
  }

  // 应用 YAML 覆写（从 Map）
  // 用于 DNS 覆写等场景，将 Map 直接合并到配置中
  Future<String> applyYamlOverride(
    String baseContent,
    Map<String, dynamic> overrideMap,
  ) async {
    Logger.debug('applyYamlOverride (from Map)');
    Logger.debug('基础配置长度：${baseContent.length} 字符');
    Logger.debug('覆写 Map 键：${overrideMap.keys.toList()}');

    // 将 Map 转换为简单的 YAML 字符串
    final yamlContent = _mapToYaml(overrideMap);
    Logger.debug('生成的 YAML 长度：${yamlContent.length} 字符');

    // 创建临时覆写配置
    final tempOverride = signals.OverrideConfig(
      id: 'temp_map_override',
      name: 'Map Override',
      format: signals.OverrideFormat.yaml,
      content: yamlContent,
    );

    // 调用 Rust 处理
    try {
      final request = signals.ApplyOverridesRequest(
        baseConfigContent: baseContent,
        overrides: [tempOverride],
      );

      // 发送请求到 Rust
      request.sendSignalToRust();

      // 等待 Rust 响应
      final response =
          await signals.ApplyOverridesResponse.rustSignalStream.first;
      final result = response.message;

      if (!result.isSuccessful) {
        Logger.error('Rust YAML 覆写失败：${result.errorMessage}');
        throw Exception('Rust YAML 覆写失败：${result.errorMessage}');
      }

      Logger.info('Rust YAML 覆写成功');
      Logger.debug('最终配置长度：${result.resultConfig.length} 字符');

      return result.resultConfig;
    } catch (e) {
      final errorMsg = 'Rust YAML 覆写异常：$e';
      Logger.error(errorMsg);
      throw Exception(errorMsg);
    }
  }

  // 将 Map 转换为简单的 YAML 字符串
  String _mapToYaml(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;
      buffer.writeln('$key: ${_formatYamlValue(value)}');
    }
    return buffer.toString();
  }

  // 格式化 YAML 值
  String _formatYamlValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) {
      // 简单处理字符串引号
      if (value.contains(':') || value.contains('#')) {
        return '"${value.replaceAll('"', '\\"')}"';
      }
      return value;
    }
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is List) {
      return '\n${value.map((item) => '  - ${_formatYamlValue(item)}').join('\n')}';
    }
    if (value is Map) {
      return '\n${(value as Map<String, dynamic>).entries.map((e) => '  ${e.key}: ${_formatYamlValue(e.value)}').join('\n')}';
    }
    return value.toString();
  }
}
