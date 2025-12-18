import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:args/args.dart';

// --- 配置 ---
const githubRepo = "MetaCubeX/mihomo";

// --- 日志函数（可选时间戳） ---
void log(Object? message, {bool withTime = false}) {
  if (withTime) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final timestamp = "$year-$month-$day $hour:$minute";
    stdout.writeln("[$timestamp] $message");
  } else {
    stdout.writeln("$message");
  }
}

// 简化错误信息：提取核心错误类型
String simplifyError(Object error) {
  final errorStr = error.toString();

  // SocketException: 信号灯超时 → 网络连接超时
  if (errorStr.contains('SocketException') && errorStr.contains('信号灯超时')) {
    return '网络连接超时';
  }

  // TimeoutException → 请求超时
  if (errorStr.contains('TimeoutException')) {
    return '请求超时';
  }

  // HttpException → HTTP 错误
  if (errorStr.contains('HttpException')) {
    final match = RegExp(r'HTTP (\d+)').firstMatch(errorStr);
    if (match != null) {
      return 'HTTP ${match.group(1)} 错误';
    }
    return 'HTTP 请求错误';
  }

  // SocketException: Connection refused → 连接被拒绝
  if (errorStr.contains('Connection refused')) {
    return '连接被拒绝';
  }

  // SocketException: Network is unreachable → 网络不可达
  if (errorStr.contains('Network is unreachable')) {
    return '网络不可达';
  }

  // 其他 SocketException → 网络错误
  if (errorStr.contains('SocketException')) {
    return '网络错误';
  }

  // 如果错误信息很短（<50字符），直接返回
  if (errorStr.length <= 50) {
    return errorStr;
  }

  // 否则截取前100个字符（安全截取，防止越界）
  final maxLen = errorStr.length < 100 ? errorStr.length : 100;
  return '${errorStr.substring(0, maxLen)}...';
}

// 平台名映射：用户输入 macos → 内部使用 darwin
String normalizePlatform(String input) {
  switch (input.toLowerCase()) {
    case 'macos':
      return 'darwin';
    default:
      return input.toLowerCase();
  }
}

// 自动解析 flutter 命令路径
Future<String> resolveFlutterCmd() async {
  if (Platform.isWindows) {
    return 'flutter.bat';
  } else {
    final result = await Process.run('which', ['flutter']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) {
        return path;
      }
    }
    throw Exception('未能找到 flutter 命令，请确认 Flutter SDK 已安装并加入 PATH');
  }
}

// 获取当前平台
String getCurrentPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  throw Exception('不支持的平台');
}

// 获取当前架构
String getCurrentArch() {
  // 通过 Dart VM 信息获取架构
  final version = Platform.version;
  if (version.contains('arm64') || version.contains('aarch64')) {
    return 'arm64';
  }
  return 'amd64';
}

// 配置 HttpClient 的代理设置
// 返回值：(proxyInfo, shouldLog) - proxyInfo 用于日志输出，shouldLog 表示是否需要记录
(String?, bool) configureProxy(
  HttpClient client,
  Uri targetUrl, {
  bool isFirstAttempt = true,
}) {
  final httpProxy =
      Platform.environment['HTTP_PROXY'] ?? Platform.environment['http_proxy'];
  final httpsProxy =
      Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['https_proxy'];

  // 判断目标 URL 是 HTTPS 还是 HTTP
  final isHttps = targetUrl.scheme == 'https';

  // 优先级：HTTPS 请求优先使用 HTTPS_PROXY，HTTP 请求优先使用 HTTP_PROXY
  String? selectedProxy;
  String? proxyType;

  if (isHttps) {
    // HTTPS 请求：优先 HTTPS_PROXY，其次 HTTP_PROXY
    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      selectedProxy = httpsProxy;
      proxyType = 'HTTPS';
    } else if (httpProxy != null && httpProxy.isNotEmpty) {
      selectedProxy = httpProxy;
      proxyType = 'HTTP';
    }
  } else {
    // HTTP 请求：优先 HTTP_PROXY，其次 HTTPS_PROXY
    if (httpProxy != null && httpProxy.isNotEmpty) {
      selectedProxy = httpProxy;
      proxyType = 'HTTP';
    } else if (httpsProxy != null && httpsProxy.isNotEmpty) {
      selectedProxy = httpsProxy;
      proxyType = 'HTTPS';
    }
  }

  if (selectedProxy != null) {
    // 移除协议前缀，只保留 host:port
    final proxyHost = selectedProxy
        .replaceFirst(RegExp(r'https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
    client.findProxy = (uri) => 'PROXY $proxyHost';

    // 只在第一次尝试时返回日志信息
    if (isFirstAttempt) {
      return ('使用 $proxyType 代理: $selectedProxy', true);
    }
    return (null, false);
  }

  // 没有代理配置
  if (isFirstAttempt) {
    return ('未检测到代理设置，使用直连', true);
  }
  return (null, false);
}

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
  final rawPlatform = getCurrentPlatform();
  final targetPlatform = normalizePlatform(rawPlatform);
  final targetArch = getCurrentArch();

  final startTime = DateTime.now();
  log('🚀 开始执行预构建任务');
  log('🖥️  检测到平台: $rawPlatform ($targetArch)');

  try {
    // Step 1: 清理资源
    log('▶️  [1/6] 正在清理资源目录...');
    await cleanAssetsDirectory(projectRoot: projectRoot);
    log('✅ 资源清理完成。');

    // Step 2: 获取 Mihomo 核心
    log('▶️  [2/6] 正在获取最新的 Mihomo 核心...');
    await downloadAndSetupCore(
      targetDir: coreAssetDir,
      platform: targetPlatform,
      arch: targetArch,
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
    await copyTrayIcons(projectRoot: projectRoot, platform: targetPlatform);
    log('✅ 资源复制完成。');

    // Step 6: 安装打包工具（如果指定）
    if (setupInstaller) {
      log('▶️  [6/6] 正在安装打包工具...');
      if (Platform.isWindows) {
        await setupInnoSetup(projectRoot: projectRoot);
      } else if (Platform.isLinux) {
        await setupLinuxPackagingTools(projectRoot: projectRoot);
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
Future<void> downloadAndSetupCore({
  required String targetDir,
  required String platform,
  required String arch,
}) async {
  if (platform == 'android') {
    log('⚠️  Android 平台暂未实现自动下载 Mihomo 核心，请手动处理。');
    return;
  }

  String assetKeyword = '$platform-$arch';
  log('🔍 正在寻找资源关键字: $assetKeyword');

  const maxRetries = 5;
  Exception? lastException;

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (attempt > 1) {
        log('🔄 重试第 $attempt 次...');
        await Future.delayed(Duration(seconds: 2 * attempt)); // 递增延迟
      }

      final apiUrl = Uri.parse(
        "https://api.github.com/repos/$githubRepo/releases/latest",
      );

      // 从环境变量获取 GitHub Token（优先 GITHUB_TOKEN，其次 GH_TOKEN）
      final githubToken =
          Platform.environment['GITHUB_TOKEN'] ??
          Platform.environment['GH_TOKEN'];

      // 构建请求头
      final headers = <String, String>{'Accept': 'application/vnd.github+json'};

      // 如果有 Token，添加认证头
      if (githubToken != null && githubToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $githubToken';
        if (attempt == 1) {
          log('🔐 使用 GitHub Token 认证请求');
        }
      } else if (attempt == 1) {
        log('⚠️  未检测到 GITHUB_TOKEN，使用未认证请求（每小时限制 60 次）');
      }

      final response = await http
          .get(apiUrl, headers: headers)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('获取 Release 信息超时'),
          );

      if (response.statusCode != 200) {
        throw Exception('获取 GitHub Release 失败: ${response.body}');
      }

      final releaseInfo = json.decode(response.body);
      final assets = releaseInfo['assets'] as List;

      final asset = assets.firstWhere((a) {
        final name = a['name'] as String;
        // 确保只选择脚本支持解压的 .gz 或 .zip 格式，避免选中 .deb 或 .rpm
        return name.contains(assetKeyword) &&
            (name.endsWith('.gz') || name.endsWith('.zip'));
      }, orElse: () => null);

      if (asset == null) {
        throw Exception('在最新的 Release 中未找到匹配 "$assetKeyword" 的资源文件。');
      }

      final downloadUrl = Uri.parse(asset['browser_download_url']);
      final fileName = asset['name'] as String;
      final version = releaseInfo['tag_name'] ?? 'unknown';

      // 仅首次下载时输出完整信息
      if (attempt == 1) {
        log('✅ 找到核心: $fileName，版本号: $version');
        log('📥 正在下载...');
      }

      // 使用 HttpClient 替代 http.readBytes，支持更长超时和代理
      final client = HttpClient();

      // 配置代理（不输出日志，已在脚本开始时统一输出）
      configureProxy(client, downloadUrl, isFirstAttempt: false);

      try {
        final request = await client.getUrl(downloadUrl);
        final response = await request.close().timeout(
          const Duration(minutes: 5), // 大文件需要更长超时
          onTimeout: () => throw TimeoutException('下载超时'),
        );

        if (response.statusCode != 200) {
          throw Exception('下载失败: HTTP ${response.statusCode}');
        }

        final fileBytes = await response.fold<List<int>>(
          <int>[],
          (previous, element) => previous..addAll(element),
        );
        client.close();

        List<int> coreFileBytes;
        if (fileName.endsWith('.zip')) {
          final archive = ZipDecoder().decodeBytes(fileBytes);
          final coreFile = archive.firstWhere(
            (file) =>
                file.isFile &&
                (file.name.endsWith('.exe') || !file.name.contains('.')),
            orElse: () => throw Exception('在 ZIP 压缩包中未找到可执行文件。'),
          );
          coreFileBytes = coreFile.content as List<int>;
        } else if (fileName.endsWith('.gz')) {
          coreFileBytes = GZipDecoder().decodeBytes(fileBytes);
        } else {
          throw Exception('不支持的文件格式: $fileName');
        }

        final targetExeName = (platform == 'windows')
            ? 'clash-core.exe'
            : 'clash-core';
        final targetFile = File(p.join(targetDir, targetExeName));

        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }

        await targetFile.writeAsBytes(coreFileBytes);

        if (platform != 'windows') {
          await runProcess('chmod', ['+x', targetFile.path]);
        }

        final sizeInMB = (coreFileBytes.length / (1024 * 1024)).toStringAsFixed(
          2,
        );
        log('✅ 核心已放置 assets/clash-core: $targetExeName ($sizeInMB MB)');
        return; // 成功，直接返回
      } catch (e) {
        client.close();
        rethrow;
      }
    } catch (e) {
      lastException = e is Exception ? e : Exception(e.toString());
      final simpleError = simplifyError(e);

      // 仅在最后一次失败时输出详细错误
      if (attempt == maxRetries) {
        log('❌ 下载失败 (尝试 $attempt/$maxRetries): $simpleError');
      } else {
        log('⚠️  下载失败 (尝试 $attempt/$maxRetries): $simpleError，即将重试...');
      }
    }
  }

  // 所有重试都失败
  throw Exception('下载核心失败，已重试 $maxRetries 次: ${lastException?.toString()}');
}

// 下载单个 GeoIP 文件（带重试机制）
Future<void> _downloadSingleGeoFile({
  required String baseUrl,
  required String remoteFileName,
  required String localFileName,
  required String targetDir,
}) async {
  const maxRetries = 5;
  final downloadUrl = Uri.parse('$baseUrl/$remoteFileName');
  final targetFile = File(p.join(targetDir, localFileName));

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (attempt > 1) {
        log('🔄 重试 $remoteFileName (第 $attempt 次)...');
      } else {
        log('📥 正在下载 $remoteFileName...');
      }

      // 创建带代理支持的 HTTP 客户端
      final client = HttpClient();

      // 配置代理（不输出日志，因为已在 downloadGeoData 中统一输出）
      configureProxy(client, downloadUrl, isFirstAttempt: false);

      try {
        final request = await client.getUrl(downloadUrl);
        final response = await request.close();

        if (response.statusCode == 200) {
          final bodyBytes = await response.fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );
          client.close();

          await targetFile.writeAsBytes(bodyBytes);
          final sizeInMB = (bodyBytes.length / (1024 * 1024)).toStringAsFixed(
            1,
          );
          log('✅ $localFileName 下载完成 ($sizeInMB MB)');
          return; // 成功，直接返回
        } else {
          client.close();
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        client.close();
        rethrow;
      }
    } catch (e) {
      final simpleError = simplifyError(e);

      if (attempt < maxRetries) {
        log('⚠️  $remoteFileName 下载失败 (尝试 $attempt/$maxRetries): $simpleError');
        await Future.delayed(Duration(seconds: 2)); // 等待 2 秒后重试
      } else {
        // 最后一次尝试失败，抛出异常
        throw Exception(
          '$remoteFileName 下载失败 (已重试 $maxRetries 次): $simpleError',
        );
      }
    }
  }
}

// 下载 GeoIP 数据文件（并发下载，带重试机制）
Future<void> downloadGeoData({required String targetDir}) async {
  const baseUrl =
      'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest';

  // 文件映射：下载URL文件名 -> 本地文件名
  final files = {
    'country.mmdb': 'country.mmdb',
    'GeoLite2-ASN.mmdb': 'asn.mmdb',
    'geoip.dat': 'geoip.dat',
    'geoip.metadb': 'geoip.metadb',
    'geosite.dat': 'geosite.dat',
  };

  // 确保目标目录存在
  final targetDirectory = Directory(targetDir);
  if (!await targetDirectory.exists()) {
    await targetDirectory.create(recursive: true);
  }

  // 不再输出代理信息，已在脚本开始时统一输出

  // 并发下载所有文件，任意一个失败则抛出异常
  final downloadTasks = files.entries.map(
    (entry) => _downloadSingleGeoFile(
      baseUrl: baseUrl,
      remoteFileName: entry.key,
      localFileName: entry.value,
      targetDir: targetDir,
    ),
  );

  // 等待所有下载任务完成，如果任何一个失败则抛出异常
  await Future.wait(downloadTasks);
}

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
  }

  // 获取最新版本
  log('📡 正在获取 Inno Setup 最新版本信息...');

  String latestVersion;
  String downloadUrl;

  try {
    // 从环境变量获取 GitHub Token
    final githubToken =
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];

    // 构建请求头
    final headers = <String, String>{'Accept': 'application/vnd.github+json'};

    // 如果有 Token，添加认证头
    if (githubToken != null && githubToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $githubToken';
    }

    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/jrsoftware/issrc/releases/latest',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final tagName = data['tag_name'] as String; // 例如: "is-6_6_1"

      // 解析版本号（is-6_6_1 -> 6.6.1）
      latestVersion = tagName.replaceFirst('is-', '').replaceAll('_', '.');

      // 构建下载 URL
      downloadUrl =
          'https://github.com/jrsoftware/issrc/releases/download/$tagName/innosetup-$latestVersion.exe';

      log('✅ 最新版本: $latestVersion');
    } else {
      throw Exception('获取版本信息失败: HTTP ${response.statusCode}');
    }
  } catch (e) {
    log('❌ 无法获取最新版本信息: $e');
    log('❌ 请检查网络连接或手动安装 Inno Setup');
    return;
  }

  // 判断是否需要安装
  if (installedVersion != null) {
    if (installedVersion == latestVersion) {
      log('✅ Inno Setup 已是最新版本 ($latestVersion)');
      return;
    } else {
      log('💡 当前版本: $installedVersion，最新版本: $latestVersion');
      log('🔄 检测到新版本，将自动升级...');
      // 继续执行安装流程以升级到最新版本
    }
  } else {
    log('⚠️  未检测到 Inno Setup');
  }

  // 需要安装
  log('📥 正在下载 Inno Setup $latestVersion...');

  final tempDir = Directory.systemTemp.createTempSync('innosetup_');
  final installerPath = p.join(tempDir.path, 'innosetup-setup.exe');

  try {
    // 下载安装程序（使用代理）
    final client = HttpClient();
    final downloadUri = Uri.parse(downloadUrl);

    // 配置代理（不输出日志，因为已在脚本开始时统一输出）
    configureProxy(client, downloadUri, isFirstAttempt: false);

    final request = await client.getUrl(downloadUri);
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    final installerFile = File(installerPath);
    final sink = installerFile.openWrite();
    await response.pipe(sink);
    await sink.close();
    client.close();

    final fileSize = (await installerFile.length() / (1024 * 1024))
        .toStringAsFixed(2);
    log('✅ 下载完成 ($fileSize MB)');

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

    log('✅ Inno Setup $latestVersion 安装成功！');

    // 验证安装
    final newVersion = await _getInnoSetupVersion();
    if (newVersion == latestVersion) {
      log('✅ 安装验证通过');
    } else {
      log('⚠️  安装后版本验证失败: $newVersion');
      log('💡 Inno Setup 已安装，但版本可能不同（这通常不影响使用）');
    }
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
Future<void> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool allowNonZeroExit = false,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  if (exitCode != 0 && !allowNonZeroExit) {
    throw Exception(
      '命令 "$executable ${arguments.join(' ')}" 执行失败，退出码: $exitCode',
    );
  }
}

// 运行命令并捕获输出
Future<ProcessResult> runProcessWithOutput(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdinData,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );

  // 如果需要输入数据（如 sudo 密码）
  if (stdinData != null) {
    process.stdin.writeln(stdinData);
    await process.stdin.close();
  }

  final stdout = await process.stdout.transform(utf8.decoder).join();
  final stderr = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

// 安装 Linux 打包工具
Future<void> setupLinuxPackagingTools({required String projectRoot}) async {
  log('🔧 正在检查 Linux 打包工具...');

  // 检测包管理器类型
  final packageManager = await _detectPackageManager();
  log('📦 检测到包管理器: $packageManager');

  // 检查并安装 dpkg-deb
  await _checkAndInstallDpkg(packageManager);

  // 检查并安装 rpmbuild
  await _checkAndInstallRpm(packageManager);

  // 检查并安装 appimagetool（从 GitHub 下载最新版）
  await _checkAndInstallAppImageTool(projectRoot: projectRoot);

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
Future<void> _checkAndInstallAppImageTool({required String projectRoot}) async {
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
      await _updateAppImageToolIfNeeded(toolPath, projectRoot);
      return;
    }
  }

  log('📥 正在从 GitHub 下载最新版 appimagetool...');
  await _downloadLatestAppImageTool(projectRoot);
}

// 检查并更新 appimagetool
Future<void> _updateAppImageToolIfNeeded(
  String currentToolPath,
  String projectRoot,
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
        await _downloadLatestAppImageTool(projectRoot);
      }
    }
  } catch (e) {
    // 更新检查失败不影响使用
    log('⚠️  检查更新失败: ${simplifyError(e)}');
  }
}

// 下载最新版 appimagetool
Future<void> _downloadLatestAppImageTool(String projectRoot) async {
  const repoUrl =
      'https://api.github.com/repos/AppImage/appimagetool/releases/latest';

  final githubToken =
      Platform.environment['GITHUB_TOKEN'] ?? Platform.environment['GH_TOKEN'];

  final headers = <String, String>{'Accept': 'application/vnd.github+json'};
  if (githubToken != null && githubToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $githubToken';
  }

  try {
    final response = await http
        .get(Uri.parse(repoUrl), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('获取 Release 信息失败: HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final assets = data['assets'] as List;
    final tagName = data['tag_name'] as String;

    // 根据架构选择下载文件
    final arch = getCurrentArch();
    String assetKeyword;
    if (arch == 'arm64' || arch == 'aarch64') {
      assetKeyword = 'aarch64';
    } else {
      assetKeyword = 'x86_64';
    }

    final asset = assets.firstWhere((a) {
      final name = a['name'] as String;
      return name.contains(assetKeyword) && name.endsWith('.AppImage');
    }, orElse: () => null);

    if (asset == null) {
      throw Exception('未找到适合 $arch 架构的 appimagetool');
    }

    final downloadUrl = asset['browser_download_url'] as String;
    final fileName = asset['name'] as String;

    log('📥 下载 $fileName (版本: $tagName)...');

    // 下载文件（处理重定向）
    final client = HttpClient();
    client.autoUncompress = false;
    // 跟随重定向
    client.connectionTimeout = const Duration(seconds: 30);

    configureProxy(client, Uri.parse(downloadUrl), isFirstAttempt: false);

    HttpClientRequest request = await client.getUrl(Uri.parse(downloadUrl));
    HttpClientResponse downloadResponse = await request.close();

    // 手动处理重定向（最多 5 次）
    int redirectCount = 0;
    while (downloadResponse.isRedirect && redirectCount < 5) {
      final location = downloadResponse.headers.value('location');
      if (location == null) break;

      final redirectUri = Uri.parse(location);
      await downloadResponse.drain();

      request = await client.getUrl(redirectUri);
      downloadResponse = await request.close();
      redirectCount++;
    }

    if (downloadResponse.statusCode != 200) {
      await downloadResponse.drain();
      client.close();
      throw Exception('下载失败: HTTP ${downloadResponse.statusCode}');
    }

    final bytes = await downloadResponse.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    client.close();

    // 保存到 assets/tools 目录
    final toolDir = Directory(p.join(projectRoot, 'assets', 'tools'));
    if (!await toolDir.exists()) {
      await toolDir.create(recursive: true);
    }

    final toolPath = p.join(toolDir.path, 'appimagetool');
    final toolFile = File(toolPath);
    await toolFile.writeAsBytes(bytes);

    // 添加执行权限
    await Process.run('chmod', ['+x', toolPath]);

    final sizeInMB = (bytes.length / (1024 * 1024)).toStringAsFixed(2);
    log('✅ appimagetool 安装完成 ($sizeInMB MB)');
  } catch (e) {
    throw Exception('下载 appimagetool 失败: ${simplifyError(e)}');
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
