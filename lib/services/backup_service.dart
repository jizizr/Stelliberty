import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/services/path_service.dart';
import 'package:stelliberty/utils/logger.dart';
import 'package:stelliberty/src/bindings/signals/signals.dart';

// 备份服务
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String backupVersion = '1.0.0';
  static const String backupExtension = '.stelliberty';

  // 并发控制标志
  bool _isOperating = false;

  // 创建备份
  Future<String> createBackup(String targetPath) async {
    // 检查是否正在进行其他操作
    if (_isOperating) {
      throw Exception('正在进行备份或还原操作，请稍后再试');
    }

    _isOperating = true;

    try {
      // 使用 Rust 层创建备份
      final completer = Completer<BackupOperationResult>();
      StreamSubscription? listener;

      try {
        // 订阅 Rust 响应流
        listener = BackupOperationResult.rustSignalStream.listen((result) {
          if (!completer.isCompleted) {
            completer.complete(result.message);
          }
        });

        // 获取应用版本
        final packageInfo = await PackageInfo.fromPlatform();

        // 发送创建备份请求到 Rust
        final request = CreateBackupRequest(
          targetPath: targetPath,
          appDataPath: PathService.instance.appDataPath,
          appVersion: packageInfo.version,
        );
        request.sendSignalToRust();

        // 等待备份结果
        final result = await completer.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw Exception('备份操作超时');
          },
        );

        if (!result.isSuccessful) {
          throw Exception(result.errorMessage ?? '备份创建失败');
        }

        return result.message;
      } finally {
        await listener?.cancel();
      }
    } catch (e) {
      Logger.error('创建备份失败：$e');
      rethrow;
    } finally {
      _isOperating = false;
    }
  }

  // 还原备份
  Future<void> restoreBackup(String backupPath) async {
    // 检查是否正在进行其他操作
    if (_isOperating) {
      throw Exception('正在进行备份或还原操作，请稍后再试');
    }

    _isOperating = true;

    try {
      // 使用 Rust 层还原备份
      final completer = Completer<BackupOperationResult>();
      StreamSubscription? listener;

      try {
        // 订阅 Rust 响应流
        listener = BackupOperationResult.rustSignalStream.listen((result) {
          if (!completer.isCompleted) {
            completer.complete(result.message);
          }
        });

        // 发送还原备份请求到 Rust
        final request = RestoreBackupRequest(
          backupPath: backupPath,
          appDataPath: PathService.instance.appDataPath,
        );
        request.sendSignalToRust();

        // 等待还原结果
        final result = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('还原操作超时');
          },
        );

        if (!result.isSuccessful) {
          throw Exception(result.errorMessage ?? '备份还原失败');
        }

        // 刷新内存状态（使 ClashManager 重新从持久化存储加载配置）
        ClashManager.instance.reloadFromPreferences();
      } finally {
        await listener?.cancel();
      }
    } catch (e) {
      Logger.error('还原备份失败：$e');
      rethrow;
    } finally {
      _isOperating = false;
    }
  }

  // 生成备份文件名
  String generateBackupFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'backup_$timestamp$backupExtension';
  }
}
