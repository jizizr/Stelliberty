import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';
import 'package:stelliberty/clash/core/core_channel.dart';

// 更新进度回调：progress (0.0-1.0)，message (当前步骤描述)
typedef ProgressCallback = void Function(double progress, String message);

// 核心更新服务：从 GitHub 下载最新的 Mihomo 核心并替换现有核心
// 支持多渠道：stable（正式版）、beta（测试版）、custom（自定义路径）
class CoreUpdateService {
  // 获取当前安装的核心版本
  static Future<String?> getCurrentCoreVersion({
    required CoreChannel channel,
    String? customPath,
  }) async {
    try {
      final corePath = await getExistingCorePath(
        channel,
        customPath: customPath,
      );

      if (corePath == null) {
        Logger.warning('核心文件不存在，无法获取版本');
        return null;
      }

      // 执行核心文件获取版本信息
      final result = await Process.run(corePath, ['-v']).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.warning('获取核心版本超时');
          throw TimeoutException('获取核心版本超时');
        },
      );

      Logger.info('核心版本命令退出码：${result.exitCode}');
      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      Logger.info('核心版本输出 (stdout)：$stdout');
      if (stderr.isNotEmpty) {
        Logger.info('核心版本输出 (stderr)：$stderr');
      }

      if (result.exitCode == 0) {
        // 解析版本号：优先匹配 `version x.y.z`，再回退到纯版本号。
        final versionPattern = r'version\s+v?(\d+\.\d+\.\d+)';
        var versionMatch = RegExp(
          versionPattern,
          caseSensitive: false,
        ).firstMatch(stdout);
        if (versionMatch != null) {
          final version = versionMatch.group(1)!;
          Logger.info('成功解析核心版本：$version');
          return version;
        }

        // 回退：匹配纯版本号（v1.2.3 或 1.2.3）。
        final pureVersionPattern = r'v?(\d+\.\d+\.\d+)';
        versionMatch = RegExp(pureVersionPattern).firstMatch(stdout);
        if (versionMatch != null) {
          final version = versionMatch.group(1)!;
          Logger.info('成功解析核心版本（纯数字格式）：$version');
          return version;
        }

        Logger.warning('无法从输出中解析版本号');
      }

      return null;
    } catch (e) {
      Logger.warning('获取当前核心版本失败：$e');
      return null;
    }
  }

  // 比较两个版本号，返回：-1（v1<v2）, 0（v1==v2）, 1（v1>v2）
  static int compareVersions(String v1, String v2) {
    // 移除可能的 'v' 前缀
    final vPrefixPattern = RegExp(r'^v');
    v1 = v1.replaceFirst(vPrefixPattern, '');
    v2 = v2.replaceFirst(vPrefixPattern, '');

    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = parts1.length > parts2.length
        ? parts1.length
        : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }

    return 0;
  }

  // 下载核心文件，成功返回新版本号和解压后的核心字节
  // 返回 (version, coreBytes) 元组，调用方负责停止核心后替换文件
  static Future<(String, List<int>)> downloadCore({
    required CoreChannel channel,
    ProgressCallback? onProgress,
  }) async {
    if (channel == CoreChannel.custom) {
      throw ArgumentError('自定义渠道不支持下载');
    }

    final completer = Completer<DownloadCoreResponse>();
    StreamSubscription? responseSubscription;
    StreamSubscription? progressSubscription;

    try {
      // 1. 获取当前平台和架构
      final platform = _getCurrentPlatform();
      final arch = _getCurrentArch();

      // 2. 订阅进度通知
      progressSubscription = DownloadCoreProgress.rustSignalStream.listen((
        result,
      ) {
        final progress = result.message;
        onProgress?.call(progress.progress, progress.message);
      });

      // 3. 订阅响应流
      responseSubscription = DownloadCoreResponse.rustSignalStream.listen((
        result,
      ) {
        if (!completer.isCompleted) {
          completer.complete(result.message);
        }
      });

      // 4. 发送下载请求到 Rust
      final request = DownloadCoreRequest(platform: platform, arch: arch);
      request.sendSignalToRust();

      // 5. 等待下载结果
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('核心下载超时');
        },
      );

      if (!result.isSuccessful) {
        throw Exception(result.errorMessage ?? '核心下载失败');
      }

      final version = result.version ?? '';
      final coreBytes = result.coreBytes ?? [];
      return (version, coreBytes);
    } catch (e) {
      Logger.error('核心下载失败：$e');
      rethrow;
    } finally {
      await responseSubscription?.cancel();
      await progressSubscription?.cancel();
    }
  }

  // 替换核心文件（在核心停止后调用）
  static Future<void> replaceCore({
    required String coreDir,
    required List<int> coreBytes,
  }) async {
    final completer = Completer<ReplaceCoreResponse>();
    StreamSubscription? subscription;

    try {
      // 订阅 Rust 响应流
      subscription = ReplaceCoreResponse.rustSignalStream.listen((result) {
        if (!completer.isCompleted) {
          completer.complete(result.message);
        }
      });

      // 发送替换请求到 Rust
      final request = ReplaceCoreRequest(
        coreDir: coreDir,
        coreBytes: coreBytes,
        platform: _getCurrentPlatform(),
      );
      request.sendSignalToRust();

      // 等待结果
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('核心替换超时');
        },
      );

      if (!result.isSuccessful) {
        throw Exception(result.errorMessage ?? '核心替换失败');
      }
    } catch (e) {
      Logger.error('核心替换失败：$e');
      rethrow;
    } finally {
      await subscription?.cancel();
    }
  }

  // 获取最新的 Release 信息
  // 返回 Map 包含 'tag_name' 等信息，以兼容现有调用代码
  static Future<Map<String, dynamic>> getLatestRelease({
    required CoreChannel channel,
  }) async {
    if (channel == CoreChannel.custom) {
      throw ArgumentError('自定义渠道不支持获取版本');
    }

    final completer = Completer<GetLatestCoreVersionResponse>();
    StreamSubscription? subscription;

    try {
      // 订阅 Rust 响应流
      subscription = GetLatestCoreVersionResponse.rustSignalStream.listen((
        result,
      ) {
        if (!completer.isCompleted) {
          completer.complete(result.message);
        }
      });

      // 发送请求到 Rust（渠道信息可在 Rust 端处理）
      final request = GetLatestCoreVersionRequest();
      request.sendSignalToRust();

      // 等待结果
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('获取版本信息超时');
        },
      );

      if (!result.isSuccessful) {
        throw Exception(result.errorMessage ?? '获取版本信息失败');
      }

      // 返回兼容格式的 Map
      return {'tag_name': result.version ?? ''};
    } finally {
      await subscription?.cancel();
    }
  }

  // 删除备份的旧核心
  static Future<void> deleteOldCore(String coreDir) async {
    final platform = _getCurrentPlatform();
    final coreName = platform == 'windows' ? 'clash-core.exe' : 'clash-core';
    final backupFile = File(p.join(coreDir, '${coreName}_backup'));

    if (await backupFile.exists()) {
      try {
        await backupFile.delete();
      } catch (e) {
        Logger.warning('删除旧核心备份失败：$e');
      }
    }
  }

  // 获取核心文件目录（指定渠道）
  static Future<String> getCoreDirectory(CoreChannel channel) async {
    if (channel == CoreChannel.custom) {
      throw ArgumentError('自定义渠道没有固定目录');
    }
    return _getChannelDirectory(channel);
  }

  // 确保核心存在，不存在时自动下载/复制，返回核心可执行路径
  static Future<String> ensureCorePath({
    required CoreChannel channel,
    String? customPath,
    ProgressCallback? onProgress,
  }) async {
    if (channel == CoreChannel.custom) {
      if (customPath == null || customPath.isEmpty) {
        throw ArgumentError('自定义核心路径未设置');
      }

      final customFile = File(customPath);
      if (!await customFile.exists()) {
        throw Exception('自定义核心文件不存在: $customPath');
      }

      return customFile.path;
    }

    final coreDir = await _getChannelDirectory(channel);
    final coreFileName = _getCoreFileName();
    final targetPath = p.join(coreDir, coreFileName);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      return targetPath;
    }

    // 尝试从内置核心复制（仅稳定渠道）
    if (channel == CoreChannel.stable) {
      final bundledPath = _getBundledCorePath();
      final bundledFile = File(bundledPath);
      if (await bundledFile.exists()) {
        await Directory(coreDir).create(recursive: true);
        await bundledFile.copy(targetPath);
        return targetPath;
      }
    }

    // 下载核心
    onProgress?.call(0.0, '下载核心中');
    final (_, coreBytes) = await downloadCore(
      channel: channel,
      onProgress: onProgress,
    );
    await _replaceCore(coreDir, coreBytes);
    return targetPath;
  }

  // 获取已存在的核心路径（不触发下载）
  static Future<String?> getExistingCorePath(
    CoreChannel channel, {
    String? customPath,
  }) async {
    if (channel == CoreChannel.custom) {
      if (customPath == null || customPath.isEmpty) return null;
      final customFile = File(customPath);
      return await customFile.exists() ? customFile.path : null;
    }

    final coreDir = await _getChannelDirectory(channel);
    final corePath = p.join(coreDir, _getCoreFileName());
    final coreFile = File(corePath);

    if (await coreFile.exists()) {
      return corePath;
    }

    if (channel == CoreChannel.stable) {
      final bundled = _getBundledCorePath();
      final bundledFile = File(bundled);
      if (await bundledFile.exists()) {
        return bundledFile.path;
      }
    }

    return null;
  }

  // 替换核心文件：备份旧核心 → 写入新核心 → 设置权限 → 失败时自动回滚
  static Future<void> _replaceCore(String coreDir, List<int> coreBytes) async {
    final platform = _getCurrentPlatform();
    final coreName = platform == 'windows' ? 'clash-core.exe' : 'clash-core';
    final coreFile = File(p.join(coreDir, coreName));
    final backupFile = File(p.join(coreDir, '${coreName}_old'));

    await Directory(coreDir).create(recursive: true);

    try {
      // 1. 备份旧核心
      if (await coreFile.exists()) {
        await coreFile.rename(backupFile.path);
      }

      // 2. 写入新核心
      await coreFile.writeAsBytes(coreBytes);

      // 3. 设置可执行权限（Linux/macOS）
      if (platform != 'windows') {
        final result = await Process.run('chmod', ['+x', coreFile.path]);
        if (result.exitCode != 0) {
          Logger.warning('设置可执行权限失败：${result.stderr}');
        }
      }
    } catch (e) {
      // 如果失败，尝试恢复备份
      if (await backupFile.exists()) {
        try {
          if (await coreFile.exists()) {
            await coreFile.delete();
          }
          await backupFile.rename(coreFile.path);
          Logger.info('已恢复旧核心');
        } catch (restoreError) {
          Logger.error('恢复备份失败：$restoreError');
        }
      }

      throw Exception('替换核心失败: $e');
    }
  }

  static Future<String> _getChannelDirectory(CoreChannel channel) async {
    final dir = p.join(_getDataRoot(), 'clash-cores', channel.storageValue);
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return dir;
  }

  static String _getBundledCorePath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'clash-core',
      _getCoreFileName(),
    );
  }

  static String _getCoreFileName() {
    final platform = _getCurrentPlatform();
    return platform == 'windows' ? 'clash-core.exe' : 'clash-core';
  }

  static String _getDataRoot() {
    return p.join(p.dirname(Platform.resolvedExecutable), 'data');
  }

  // 获取当前平台
  static String _getCurrentPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'darwin';
    throw Exception('不支持的平台: ${Platform.operatingSystem}');
  }

  // 获取当前架构（通过 Platform.version 推断）
  static String _getCurrentArch() {
    final is64Bit =
        Platform.version.contains('x64') ||
        Platform.version.contains('aarch64') ||
        !Platform.version.contains('x86');

    if (Platform.isWindows || Platform.isLinux) {
      return is64Bit ? 'amd64' : 'amd64'; // 默认 amd64
    }

    if (Platform.isMacOS) {
      // macOS 可能是 amd64 或 arm64
      return Platform.version.contains('arm64') ||
              Platform.version.contains('aarch64')
          ? 'arm64'
          : 'amd64';
    }

    return 'amd64'; // 默认值
  }
}
