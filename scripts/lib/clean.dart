import 'dart:io';
import 'package:path/path.dart' as p;
import 'common.dart';

// 终止 Rust 编译进程 (跨平台支持, 成功时静默)
Future<void> killRustProcesses() async {
  try {
    if (Platform.isWindows) {
      // Windows: 终止 rustc.exe
      final result = await Process.run('taskkill', [
        '/F',
        '/IM',
        'rustc.exe',
        '/T',
      ]);
      if (result.exitCode != 0 && result.exitCode != 128) {
        // exitCode 128 表示进程不存在,这是正常的
        log('⚠️  终止 Rust 进程时出现警告: ${result.stderr}');
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      // Linux/macOS: 终止 rustc
      final result = await Process.run('pkill', ['-9', 'rustc']);
      if (result.exitCode != 0 && result.exitCode != 1) {
        // exitCode 1 表示进程不存在,这是正常的
        log('⚠️  终止 Rust 进程时出现警告: ${result.stderr}');
      }
    }
    await Future.delayed(Duration(milliseconds: 500));
  } catch (e) {
    log('⚠️  终止 Rust 进程失败: $e');
  }
}

// 运行 flutter clean
Future<void> runFlutterCleanCmd(String projectRoot, String flutterCmd) async {
  final result = await Process.run(flutterCmd, [
    'clean',
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    log('⚠️  flutter clean 执行失败');
    log(result.stderr.toString().trim());
    // 不抛出异常,继续执行其他清理任务
  }
}

// 运行 cargo clean
Future<void> runCargoClean(String projectRoot) async {
  // 检查是否有 Cargo.toml 文件
  final cargoToml = File(p.join(projectRoot, 'Cargo.toml'));
  if (!await cargoToml.exists()) {
    log('⏭️  跳过 cargo clean (未找到 Cargo.toml)');
    return;
  }

  // 在执行 cargo clean 前先终止 Rust 编译进程
  await killRustProcesses();

  final result = await Process.run('cargo', [
    'clean',
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    log('⚠️  cargo clean 执行失败 (可能 cargo 未安装或进程被占用)');
    log(result.stderr.toString().trim());
    // 不抛出异常,继续执行其他清理任务
  }
}

// 运行完整清理流程
Future<void> runFlutterClean(
  String projectRoot, {
  bool skipClean = false,
}) async {
  if (skipClean) {
    log('⏭️  跳过构建缓存清理（--dirty 模式）');
    return;
  }

  final flutterCmd = await resolveFlutterCmd();

  log('🧹 开始清理构建缓存...');

  // 静默终止 Rust 编译进程,避免文件占用
  await killRustProcesses();

  // Flutter 缓存清理
  await runFlutterCleanCmd(projectRoot, flutterCmd);

  // Rust 缓存清理
  await runCargoClean(projectRoot);

  log('✅ 所有清理任务已完成');
}

// 清理 assets 目录（保留 test 文件夹）
Future<void> cleanAssetsDirectory({required String projectRoot}) async {
  final assetsDir = Directory(p.join(projectRoot, 'assets'));

  if (!await assetsDir.exists()) {
    log('  ⚠️  assets 目录不存在，跳过清理。');
    return;
  }

  // 遍历 assets 目录中的所有项
  await for (final entity in assetsDir.list()) {
    final name = p.basename(entity.path);

    // 跳过 test 文件夹
    if (name == 'test') {
      log('  ⏭️  保留: $name');
      continue;
    }

    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
        log('  🗑️  删除目录: $name');
      } else if (entity is File) {
        await entity.delete();
        log('  🗑️  删除文件: $name');
      }
    } catch (e) {
      log('  ⚠️  删除失败 $name: $e');
    }
  }
}
