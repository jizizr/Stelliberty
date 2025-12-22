import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:args/args.dart';

// 导入模块化功能
import 'lib/common.dart';
import 'lib/process.dart';
import 'lib/download.dart';
import 'lib/http_utils.dart';

// 获取当前平台名称
String _getCurrentPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  throw Exception('不支持的平台');
}

// 获取当前架构（x64/arm64/x86）
String _getCurrentArchitecture() {
  final version = Platform.version;
  if (version.contains('arm64') || version.contains('aarch64')) {
    return 'arm64';
  } else if (version.contains('x64') || version.contains('x86_64')) {
    return 'x64';
  } else if (version.contains('ia32') || version.contains('x86')) {
    return 'x86';
  }
  return 'x64'; // 默认
}

// --- 配置 ---
const githubRepo = "MetaCubeX/mihomo";
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('android', negatable: false, help: '构建 Android 平台（暂未适配）')
    ..addFlag(
      'installer',
      negatable: false,
      help: '安装平台安装器工具（Windows: Inno Setup, Linux: dpkg/rpm/appimagetool）',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助信息');

  ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } catch (e) {
    log('❌ 参数错误: ${e.toString()}\n');
    log(parser.usage);
    exit(1);
  }

  if (argResults['help'] as bool) {
    log('Flutter 预构建脚本（自动识别平台和架构）');
    log('\n用法: dart run scripts/prebuild.dart [选项]\n');
    log('选项:');
    log(parser.usage);
    log('\n支持平台: Windows, macOS, Linux');
    log('\n示例:');
    log('  dart run scripts/prebuild.dart            # 自动识别当前平台和架构');
    log('  dart run scripts/prebuild.dart --installer # 安装平台工具（Inno Setup）');
    log('  dart run scripts/prebuild.dart --android   # 提示 Android 暂未适配');
    exit(0); // 显式退出，避免继续执行
  }

  final projectRoot = p.dirname(p.dirname(Platform.script.toFilePath()));
  final coreAssetDir = p.join(projectRoot, 'assets', 'clash-core');

  // 提前检测代理配置（只输出一次）
  final testUrl = Uri.parse('https://github.com');
  final testClient = HttpClient();
  final (proxyInfo, shouldLog) = configureProxy(
    testClient,
    testUrl,
    isFirstAttempt: true,
  );
  testClient.close();

  if (shouldLog && proxyInfo != null) {
    log('🌐 $proxyInfo');
  }

  // 处理 --installer 参数（移到任务最后，避免影响核心下载）
  final setupInstaller = argResults['installer'] as bool;

  final isAndroid = argResults['android'] as bool;

  // 检查 Android 支持
  if (isAndroid) {
    log('❌ 错误: 项目暂未适配 Android 平台');
    exit(1);
  }

  // 自动识别平台和架构
  final platform = _getCurrentPlatform();
  final arch = _getCurrentArchitecture();

  final startTime = DateTime.now();
  log('🚀 开始执行预构建任务');
  log('🖥️  检测到平台: $platform ($arch)');

  try {
    // Step 1: 清理资源
    log('▶️  [1/6] 正在清理资源目录...');
    await cleanAssetsDirectory(projectRoot: projectRoot);
    log('✅ 资源清理完成。');

    // Step 2: 获取 Mihomo 核心
    log('▶️  [2/6] 正在获取最新的 Mihomo 核心...');
    await downloadAndSetupCore(
      targetDir: coreAssetDir,
      platform: platform,
      arch: arch,
    );
    log('✅ 核心准备完成。');

    // Step 3: 下载 GeoIP 数据
    log('▶️  [3/6] 正在下载最新的 GeoIP 数据文件...');
    final geoDataDir = p.join(coreAssetDir, 'data');
    await downloadGeoData(targetDir: geoDataDir);
    log('✅ GeoIP 数据下载完成。');

    // Step 4: 编译 Stelliberty Service
    log('▶️  [4/6] 正在编译 Stelliberty Service...');
    await buildStelliibertyService(projectRoot: projectRoot);
    log('✅ Service 编译完成。');

    // Step 5: 复制所需资源
    log('▶️  [5/6] 正在复制所需资源...');
    await copyTrayIcons(projectRoot: projectRoot, platform: platform);
    log('✅ 资源复制完成。');

    // Step 6: 安装打包工具（如果指定）
    if (setupInstaller) {
      log('▶️  [6/6] 正在安装打包工具...');
      if (Platform.isWindows) {
        await setupInnoSetup(projectRoot: projectRoot);
      } else if (Platform.isLinux) {
        await setupLinuxPackagingTools(projectRoot: projectRoot, arch: arch);
      }
      log('✅ 打包工具安装完成。');
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    final seconds = duration.inMilliseconds / 1000;

    log('🎉 所有预构建任务已成功完成！');
    log('⏱️  总耗时: ${seconds.toStringAsFixed(2)} 秒');
  } catch (e) {
    log('❌ 任务失败: $e');
    exit(1);
  }
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

// 编译 Stelliberty Service 并复制到 assets/service
Future<void> buildStelliibertyService({required String projectRoot}) async {
  final serviceDir = p.join(projectRoot, 'native', 'stelliberty_service');
  final targetDir = p.join(projectRoot, 'assets', 'service');

  // 确保 service 目录存在
  if (!await Directory(serviceDir).exists()) {
    log('⚠️  未找到 stelliberty_service 目录，跳过编译。');
    return;
  }

  // 编译 release 版本
  log('🔨 正在编译 stelliberty-service (release)...');
  await runProcess(
    'cargo',
    ['build', '--release'],
    workingDirectory: serviceDir,
    allowNonZeroExit: false,
  );

  // 查找编译后的可执行文件
  final exeName = Platform.isWindows
      ? 'stelliberty-service.exe'
      : 'stelliberty-service';
  final sourceExe = File(p.join(projectRoot, 'target', 'release', exeName));

  if (!await sourceExe.exists()) {
    throw Exception('编译产物未找到: ${sourceExe.path}');
  }

  // 确保目标目录存在
  final targetDirectory = Directory(targetDir);
  if (!await targetDirectory.exists()) {
    await targetDirectory.create(recursive: true);
  }

  // 复制到 assets/service 目录
  final targetExe = File(p.join(targetDir, exeName));
  await sourceExe.copy(targetExe.path);

  final sizeInMB = (await targetExe.length() / (1024 * 1024)).toStringAsFixed(
    2,
  );
  log('✅ 复制到 assets/service: $exeName ($sizeInMB MB)');
}

// 下载并设置 Clash 核心（带重试机制）
// 复制托盘图标到 assets/icons 目录
Future<void> copyTrayIcons({
  required String projectRoot,
  required String platform,
}) async {
  final sourceDir = p.join(projectRoot, 'scripts', 'pre_assets', 'tray_icon');
  final targetDir = p.join(projectRoot, 'assets', 'icons');

  // 确保目标目录存在
  final targetDirectory = Directory(targetDir);
  if (!await targetDirectory.exists()) {
    await targetDirectory.create(recursive: true);
  }

  // 根据平台选择源目录和文件扩展名
  String platformSubDir;
  String fileExtension;

  if (platform == 'windows') {
    platformSubDir = 'windows';
    fileExtension = '.ico';
  } else if (platform == 'darwin') {
    // macOS 使用 PNG
    platformSubDir = 'macos';
    fileExtension = '.png';
  } else if (platform == 'linux') {
    // Linux 使用 PNG
    platformSubDir = 'linux';
    fileExtension = '.png';
  } else {
    log('⚠️  不支持的平台: $platform');
    return;
  }

  final platformSourceDir = p.join(sourceDir, platformSubDir);

  // 检查源目录是否存在
  if (!await Directory(platformSourceDir).exists()) {
    log('⚠️  未找到平台图标目录: $platformSourceDir');
    return;
  }

  // 复制四个图标文件
  final iconFiles = [
    'disabled',
    'proxy_enabled',
    'tun_enabled',
    'proxy_tun_enabled',
  ];

  for (final iconName in iconFiles) {
    final sourceFile = File(
      p.join(platformSourceDir, '$iconName$fileExtension'),
    );
    final targetFile = File(p.join(targetDir, '$iconName$fileExtension'));

    try {
      if (await sourceFile.exists()) {
        await sourceFile.copy(targetFile.path);
        log('  ✅ 复制 $iconName$fileExtension');
      } else {
        log('⚠️  未找到源文件: ${sourceFile.path}');
      }
    } catch (e) {
      log('❌ 复制 $iconName$fileExtension 失败: $e');
    }
  }
}

// 安装 Inno Setup（仅 Windows，调用前已检查平台）
Future<void> setupInnoSetup({required String projectRoot}) async {
  log('🔧 正在检查 Inno Setup 安装状态...');

  // 检查是否已安装
  final installedVersion = await _getInnoSetupVersion();

  if (installedVersion != null) {
    log('✅ 检测到 Inno Setup 版本: $installedVersion');
  } else {
    log('⚠️  未检测到 Inno Setup');
  }

  final tempDir = Directory.systemTemp.createTempSync('innosetup_');

  try {
    // 使用统一的下载函数（会自动获取最新版本）
    final installerPath = await downloadInnoSetup(tempDir: tempDir.path);

    // 直接运行静默安装（GitHub Actions 环境已具有管理员权限）
    log('🔧 正在静默安装 Inno Setup...');
    log('💡 使用参数: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-');

    final result = await Process.run(installerPath, [
      '/VERYSILENT', // 完全静默，不显示任何界面
      '/SUPPRESSMSGBOXES', // 禁止消息框
      '/NORESTART', // 禁止重启
      '/SP-', // 跳过启动提示
      '/NOICONS', // 不创建桌面/开始菜单图标
    ]);

    if (result.exitCode != 0) {
      log('❌ 安装失败 (退出码: ${result.exitCode})');
      if (result.stdout.toString().trim().isNotEmpty) {
        log('标准输出: ${result.stdout}');
      }
      if (result.stderr.toString().trim().isNotEmpty) {
        log('错误输出: ${result.stderr}');
      }
      throw Exception('Inno Setup 安装失败，退出码: ${result.exitCode}');
    }

    log('✅ Inno Setup 安装成功！');

    // 验证安装
    final newVersion = await _getInnoSetupVersion();
    if (newVersion != null) {
      log('✅ 安装验证通过，当前版本: $newVersion');
    } else {
      log('⚠️  安装后版本验证失败');
      log('💡 Inno Setup 可能已安装，但版本检测失败（这通常不影响使用）');
    }
  } catch (e) {
    log('❌ Inno Setup 安装失败: ${simplifyError(e)}');
    log('❌ 请检查网络连接或手动安装 Inno Setup');
    rethrow;
  } finally {
    // 清理临时文件
    try {
      await tempDir.delete(recursive: true);
    } catch (e) {
      // 忽略清理错误
    }
  }
}

// 获取已安装的 Inno Setup 版本
Future<String?> _getInnoSetupVersion() async {
  // 方法1: 从注册表读取版本信息（最可靠）
  try {
    final result = await Process.run('powershell', [
      '-Command',
      "Get-ItemProperty 'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Inno Setup 6_is1' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayVersion",
    ]);

    if (result.exitCode == 0) {
      final version = result.stdout.toString().trim();
      if (version.isNotEmpty && version != '') {
        return version;
      }
    }
  } catch (e) {
    // 注册表读取失败，尝试其他方法
  }

  // 方法2: 检查常见安装路径（回退方案）
  final paths = [
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
  ];

  for (final path in paths) {
    if (await File(path).exists()) {
      // 文件存在，但无法准确获取版本号，返回通用版本
      return '6.0.0'; // 推测为 Inno Setup 6
    }
  }

  return null;
}

// 运行一个进程并等待其完成

// 安装 Linux 打包工具
Future<void> setupLinuxPackagingTools({
  required String projectRoot,
  required String arch, // x64 或 arm64
}) async {
  log('🔧 正在检查 Linux 打包工具...');

  // 检测包管理器类型
  final packageManager = await _detectPackageManager();
  log('📦 检测到包管理器: $packageManager');

  // 检查并安装 dpkg-deb
  await _checkAndInstallDpkg(packageManager);

  // 检查并安装 rpmbuild
  await _checkAndInstallRpm(packageManager);

  // 检查并安装 appimagetool（从 GitHub 下载最新版）
  await _checkAndInstallAppImageTool(projectRoot: projectRoot, arch: arch);

  log('✅ Linux 打包工具检查完成');
}

// 检测 Linux 包管理器类型
Future<String> _detectPackageManager() async {
  // 检查 apt（Debian/Ubuntu）
  final aptResult = await Process.run('which', ['apt']);
  if (aptResult.exitCode == 0) return 'apt';

  // 检查 dnf（Fedora/RHEL 8+）
  final dnfResult = await Process.run('which', ['dnf']);
  if (dnfResult.exitCode == 0) return 'dnf';

  // 检查 yum（CentOS/RHEL 7）
  final yumResult = await Process.run('which', ['yum']);
  if (yumResult.exitCode == 0) return 'yum';

  // 检查 pacman（Arch Linux）
  final pacmanResult = await Process.run('which', ['pacman']);
  if (pacmanResult.exitCode == 0) return 'pacman';

  // 检查 zypper（openSUSE）
  final zypperResult = await Process.run('which', ['zypper']);
  if (zypperResult.exitCode == 0) return 'zypper';

  return 'unknown';
}

// 检查并安装 dpkg-deb
Future<void> _checkAndInstallDpkg(String packageManager) async {
  final result = await Process.run('which', ['dpkg-deb']);
  if (result.exitCode == 0) {
    // 获取版本
    final versionResult = await Process.run('dpkg-deb', ['--version']);
    final versionLine = (versionResult.stdout as String).split('\n').first;
    log('✅ dpkg-deb 已安装: $versionLine');
    return;
  }

  log('⚠️  dpkg-deb 未安装，正在安装...');

  switch (packageManager) {
    case 'apt':
      await _runSudoCommand(['apt', 'update']);
      await _runSudoCommand(['apt', 'install', '-y', 'dpkg']);
      break;
    case 'dnf':
    case 'yum':
      await _runSudoCommand([packageManager, 'install', '-y', 'dpkg']);
      break;
    case 'pacman':
      await _runSudoCommand(['pacman', '-S', '--noconfirm', 'dpkg']);
      break;
    case 'zypper':
      await _runSudoCommand(['zypper', 'install', '-y', 'dpkg']);
      break;
    default:
      log('⚠️  无法自动安装 dpkg-deb，请手动安装');
      return;
  }

  log('✅ dpkg-deb 安装完成');
}

// 检查并安装 rpmbuild
Future<void> _checkAndInstallRpm(String packageManager) async {
  final result = await Process.run('which', ['rpmbuild']);
  if (result.exitCode == 0) {
    // 获取版本
    final versionResult = await Process.run('rpmbuild', ['--version']);
    final versionLine = (versionResult.stdout as String).trim();
    log('✅ rpmbuild 已安装: $versionLine');
    return;
  }

  log('⚠️  rpmbuild 未安装，正在安装...');

  switch (packageManager) {
    case 'apt':
      await _runSudoCommand(['apt', 'update']);
      await _runSudoCommand(['apt', 'install', '-y', 'rpm']);
      break;
    case 'dnf':
    case 'yum':
      await _runSudoCommand([packageManager, 'install', '-y', 'rpm-build']);
      break;
    case 'pacman':
      await _runSudoCommand(['pacman', '-S', '--noconfirm', 'rpm-tools']);
      break;
    case 'zypper':
      await _runSudoCommand(['zypper', 'install', '-y', 'rpm-build']);
      break;
    default:
      log('⚠️  无法自动安装 rpmbuild，请手动安装');
      return;
  }

  log('✅ rpmbuild 安装完成');
}

// 检查并安装 appimagetool（从 GitHub 获取最新版本）
Future<void> _checkAndInstallAppImageTool({
  required String projectRoot,
  required String arch, // x64 或 arm64
}) async {
  // 存放到 assets/tools 目录，避免被 flutter clean 清理
  final toolPath = p.join(projectRoot, 'assets', 'tools', 'appimagetool');
  final toolFile = File(toolPath);

  // 检查本地工具是否存在
  if (await toolFile.exists()) {
    // 验证可执行性
    final testResult = await Process.run(toolPath, ['--version']);
    if (testResult.exitCode == 0) {
      final version = (testResult.stdout as String).trim();
      log('✅ appimagetool 已安装: $version');

      // 检查是否有更新版本
      await _updateAppImageToolIfNeeded(toolPath, projectRoot, arch);
      return;
    }
  }

  log('📥 正在从 GitHub 下载最新版 appimagetool...');
  await downloadAppImageTool(projectRoot: projectRoot, arch: arch);
}

// 检查并更新 appimagetool
Future<void> _updateAppImageToolIfNeeded(
  String currentToolPath,
  String projectRoot,
  String arch,
) async {
  try {
    // 获取当前版本
    final currentResult = await Process.run(currentToolPath, ['--version']);
    final currentVersion = (currentResult.stdout as String).trim();

    // 从 GitHub 获取最新 release 信息
    final githubToken =
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];

    final headers = <String, String>{'Accept': 'application/vnd.github+json'};
    if (githubToken != null && githubToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $githubToken';
    }

    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/AppImage/appimagetool/releases/latest',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final latestTag = data['tag_name'] as String;

      // 比较版本（简单字符串比较）
      if (!currentVersion.contains(latestTag) && latestTag != currentVersion) {
        log('💡 发现新版本: $latestTag（当前: $currentVersion）');
        log('🔄 正在更新 appimagetool...');
        await downloadAppImageTool(projectRoot: projectRoot, arch: arch);
      }
    }
  } catch (e) {
    // 更新检查失败不影响使用
    log('⚠️  检查更新失败: ${simplifyError(e)}');
  }
}

// 使用 sudo 运行命令（支持从 stdin 读取密码）
Future<void> _runSudoCommand(List<String> command) async {
  log('🔐 需要管理员权限执行: ${command.join(' ')}');

  // 使用 -S 选项从 stdin 读取密码
  final process = await Process.start('sudo', [
    '-S',
    ...command,
  ], mode: ProcessStartMode.inheritStdio);

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('命令执行失败: sudo ${command.join(' ')}');
  }
}
