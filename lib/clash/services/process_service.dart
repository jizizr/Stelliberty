import 'dart:async';
import 'dart:io';

import 'package:stelliberty/clash/services/core_update_service.dart';
import 'package:stelliberty/clash/services/geo_service.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/src/bindings/bindings.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/storage/clash_preferences.dart';

// Clash 进程服务：封装 Rust 信号调用与端口检查工具。
// 仅包含技术实现，不承载业务决策。
class ProcessService {
  // netstat 输出缓存（优化性能，避免频繁调用）
  String? _cachedNetstat;
  DateTime? _cachedAt;
  static const _cacheDuration = Duration(milliseconds: 100);

  // 启动 Clash 进程（通过 Rust）
  // 纯技术调用，不包含业务逻辑
  Future<void> startProcess({
    required String executablePath,
    String? configPath,
    required String apiHost,
    required int apiPort,
  }) async {
    // 获取 Geodata 数据目录
    final geoDataDir = await GeoService.getGeoDataDir();

    // 构建启动参数
    final args = <String>[];

    if (configPath != null && configPath.isNotEmpty) {
      args.addAll(['-f', configPath]);
    }

    // 指定数据目录（Geodata 文件位置）
    args.addAll(['-d', geoDataDir]);

    // IPC 端点从配置读取：Windows 使用 pipe，Unix 使用 socket。
    // HTTP API 端点为 external-controller（如启用）。

    // 调用 Rust 端启动进程（详细信息由 Rust 端日志输出）
    StartClashProcess(
      executablePath: executablePath,
      args: args,
    ).sendSignalToRust();

    // 等待 Rust 端返回结果
    final resultReceiver = ClashProcessResult.rustSignalStream;
    final result = await resultReceiver.first;

    if (!result.message.isSuccessful) {
      final error = result.message.errorMessage ?? '未知错误';
      Logger.error('Clash 进程启动失败：$error');
      throw Exception('启动 Clash 进程失败：$error');
    }
  }

  // 停止 Clash 进程（通过 Rust）
  // 纯技术调用，不包含业务逻辑
  Future<void> stopProcess({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // 调用 Rust 端停止进程
    StopClashProcess().sendSignalToRust();

    // 等待 Rust 端返回结果
    final resultReceiver = ClashProcessResult.rustSignalStream;
    final result = await resultReceiver.first;

    if (!result.message.isSuccessful) {
      final error = result.message.errorMessage ?? '未知错误';
      Logger.warning('Clash 进程停止失败：$error');
    }
  }

  // 获取 Clash 可执行文件路径
  // 根据用户选择的渠道返回对应的核心路径
  static Future<String> getExecutablePath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      throw UnsupportedError('移动端不支持这个方式');
    }

    final prefs = ClashPreferences.instance;
    final channel = prefs.getCoreChannel();
    final customPath = prefs.getCoreCustomPath();

    Logger.info('获取核心路径: 渠道=$channel, 自定义路径=$customPath');

    try {
      // 使用 CoreUpdateService 获取或确保核心存在
      final executablePath = await CoreUpdateService.ensureCorePath(
        channel: channel,
        customPath: customPath,
      );

      final executableFile = File(executablePath);

      // 验证文件存在
      if (!await executableFile.exists()) {
        Logger.error('Clash 可执行文件不存在：$executablePath');
        throw Exception('Clash 可执行文件不存在，请检查核心设置');
      }

      Logger.info('使用 Clash 可执行文件（$channel）：$executablePath');
      return executablePath;
    } catch (e) {
      Logger.error('获取核心路径失败: $e');
      // 如果获取失败，回退到内置核心
      return _getFallbackExecutablePath();
    }
  }

  // 回退：获取内置核心路径
  static Future<String> _getFallbackExecutablePath() async {
    final String fileName;
    if (Platform.isWindows) {
      fileName = 'clash-core.exe';
    } else if (Platform.isMacOS || Platform.isLinux) {
      fileName = 'clash-core';
    } else {
      throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
    }

    // 使用 PathService 获取可执行文件路径
    final executablePath = PathService.instance.getClashCoreExecutablePath(
      fileName,
    );

    final executableFile = File(executablePath);

    // 验证文件存在
    if (!await executableFile.exists()) {
      Logger.error('Clash 回退可执行文件不存在：$executablePath');
      throw Exception('Clash 可执行文件不存在，请检查应用打包是否正确');
    }

    Logger.info('使用内置 Clash 可执行文件（回退）：$executablePath');
    return executablePath;
  }

  // ==================== 端口检查工具方法 ====================

  // 获取 netstat 输出（带缓存，100ms 内复用）
  Future<String> getNetstatOutput() async {
    if (!Platform.isWindows) {
      return '';
    }

    final now = DateTime.now();

    // 100ms 内复用缓存
    if (_cachedNetstat != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheDuration) {
      return _cachedNetstat!;
    }

    try {
      // 执行 netstat -ano 并缓存结果
      final result = await Process.run('netstat', ['-ano']);
      if (result.exitCode == 0) {
        _cachedNetstat = result.stdout.toString();
        _cachedAt = now;
        return _cachedNetstat!;
      }
    } catch (e) {
      Logger.warning('执行 netstat 失败：$e');
    }

    return '';
  }

  // 清除 netstat 缓存（在进程状态改变后调用）
  void clearNetstatCache() {
    _cachedNetstat = null;
    _cachedAt = null;
  }

  // 从 netstat 输出中解析端口是否被占用
  bool parsePortInOutput(String output, int port) {
    if (output.isEmpty) {
      return false;
    }

    final lines = output.split('\n');
    final portPattern = RegExp(r':' + port.toString() + r'\b');

    for (final line in lines) {
      // 必须同时满足：包含 LISTENING 状态 + 精确匹配端口号
      if (line.contains('LISTENING') && portPattern.hasMatch(line)) {
        return true;
      }
    }

    return false;
  }

  // 批量检查多个端口（一次 netstat 扫描）
  Future<Map<int, bool>> checkMultiplePorts(List<int> ports) async {
    final output = await getNetstatOutput();
    final results = <int, bool>{};

    for (final port in ports) {
      results[port] = parsePortInOutput(output, port);
    }

    return results;
  }

  // 检查端口是否被占用（Windows 使用 netstat）
  Future<bool> isPortInUse(int port) async {
    if (!Platform.isWindows) {
      return false; // 非 Windows 系统暂不检查
    }

    try {
      final output = await getNetstatOutput();
      final inUse = parsePortInOutput(output, port);

      if (inUse) {
        Logger.debug('检测到端口 $port 正在被监听');
      }

      return inUse;
    } catch (e) {
      Logger.warning('检查端口占用失败：$e');
      return false;
    }
  }

  // 等待端口释放
  Future<void> waitForPortRelease(int port, {required Duration maxWait}) async {
    const checkInterval = Duration(milliseconds: 100);
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < maxWait) {
      final inUse = await isPortInUse(port);
      if (!inUse) {
        return;
      }
      await Future.delayed(checkInterval);
    }

    Logger.warning('端口 $port 在 ${maxWait.inSeconds} 秒后仍未释放');
  }

  // 尝试通过服务模式停止 Clash 核心
  // 用于清理权限不足无法终止的进程（服务模式启动的进程）
  Future<bool> tryStopViaService() async {
    try {
      Logger.debug('发送 StopClash 信号到服务…');
      StopClash().sendSignalToRust();

      // 等待服务响应（5 秒超时）
      final signal = await ClashProcessResult.rustSignalStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.warning('服务停止超时');
          throw TimeoutException('服务停止超时');
        },
      );

      if (signal.message.isSuccessful) {
        Logger.info('服务已成功停止 Clash');
        return true;
      } else {
        Logger.warning('服务停止失败：${signal.message.errorMessage}');
        return false;
      }
    } catch (e) {
      Logger.error('通过服务停止失败：$e');
      return false;
    }
  }
}
