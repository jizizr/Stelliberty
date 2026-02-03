import 'dart:async';
import 'dart:io';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 系统代理服务：Dart 端仅负责发送信号与等待响应。
// 平台相关实现由 Rust 端完成。
class SystemProxy {
  // ==================== 绕过规则配置 ====================

  // 获取默认绕过规则字符串（按平台生成）。
  // Windows 使用分号分隔，其他平台使用逗号分隔。
  static String getDefaultBypassRules() {
    if (Platform.isWindows) {
      return 'localhost;127.*;192.168.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;<local>';
    } else if (Platform.isLinux) {
      // Linux 格式 (逗号分隔，支持 CIDR)
      return 'localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,172.29.0.0/16,::1';
    } else if (Platform.isMacOS) {
      // macOS 格式 (逗号分隔，支持通配符和 CIDR)
      return '127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,172.29.0.0/16,localhost,*.local,*.crashlytics.com,<local>';
    } else {
      // 其他平台使用通用格式
      return 'localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12';
    }
  }

  // 解析绕过规则字符串为列表。
  static List<String> parseBypassRules(String bypassString) {
    // 根据平台使用不同的分隔符
    final separator = Platform.isWindows ? ';' : ',';
    return bypassString
        .split(separator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ==================== 系统代理设置 ====================

  // 启用系统代理（平台逻辑由 Rust 端处理）。
  static Future<bool> enable({
    required String host,
    required int port,
    List<String> bypassDomains = const [],
    bool usePacMode = false,
    String pacScript = '',
    String? pacFilePath,
  }) async {
    // 如果没有提供 PAC 文件路径，使用 PathService 的默认路径
    final finalPacFilePath = pacFilePath ?? PathService.instance.pacFilePath;

    return _executeRustSignal(
      sendSignal: () {
        final signal = EnableSystemProxy(
          host: host,
          port: port,
          bypassDomains: bypassDomains,
          shouldUsePacMode: usePacMode,
          pacScript: pacScript,
          pacFilePath: finalPacFilePath,
        );
        signal.sendSignalToRust();
      },
      operationName: usePacMode ? '设置系统代理 (PAC 模式)' : '设置系统代理',
      successMessage: null,
    );
  }

  // 禁用系统代理（平台逻辑由 Rust 端处理）。
  static Future<bool> disable() async {
    return _executeRustSignal(
      sendSignal: () {
        final signal = DisableSystemProxy();
        signal.sendSignalToRust();
      },
      operationName: '禁用系统代理',
      successMessage: null,
    );
  }

  // 获取系统代理状态（平台逻辑由 Rust 端处理）。
  static Future<Map<String, dynamic>> getStatus() async {
    try {
      Logger.info('正在获取系统代理状态');

      final completer = Completer<Map<String, dynamic>>();

      // 订阅 Rust 信号流
      final subscription = SystemProxyInfo.rustSignalStream.listen((result) {
        if (!completer.isCompleted) {
          completer.complete({
            'enabled': result.message.isEnabled,
            'server': result.message.server,
          });
        }
      });

      // 发送信号到 Rust
      final signal = GetSystemProxy();
      signal.sendSignalToRust();

      // 等待响应，设置超时
      final status = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.error('获取系统代理状态超时');
          return {'enabled': false, 'server': null};
        },
      );

      // 停止监听信号流
      await subscription.cancel();

      Logger.info('系统代理状态：$status');
      return status;
    } catch (e) {
      Logger.error('获取系统代理状态出错：$e');
      return {'enabled': false, 'server': null};
    }
  }

  // ==================== 内部辅助方法 ====================

  // 执行 Rust 信号并等待响应（统一封装订阅与超时逻辑）。
  static Future<bool> _executeRustSignal({
    required void Function() sendSignal,
    required String operationName,
    String? successMessage,
  }) async {
    try {
      Logger.info('正在$operationName');

      // 创建一个 Completer 来等待 Rust 响应
      final completer = Completer<bool>();

      // 订阅 Rust 信号流
      final subscription = SystemProxyResult.rustSignalStream.listen((result) {
        if (!completer.isCompleted) {
          completer.complete(result.message.isSuccessful);
          if (!result.message.isSuccessful &&
              result.message.errorMessage != null) {
            Logger.error('$operationName失败：${result.message.errorMessage}');
          }
        }
      });

      // 发送信号到 Rust
      sendSignal();

      // 等待响应，设置超时
      final success = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.error('$operationName超时');
          return false;
        },
      );

      // 停止监听信号流
      await subscription.cancel();

      if (success && successMessage != null) {
        Logger.info(successMessage);
      }
      return success;
    } catch (e) {
      Logger.error('$operationName出错：$e');
      return false;
    }
  }
}
