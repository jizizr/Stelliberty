import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'common.dart';
import 'http_utils.dart';
import 'process.dart';

// GitHub 仓库配置
const githubRepo = "MetaCubeX/mihomo";

Future<void> downloadAndSetupCore({
  required String targetDir,
  required String platform,
  required String arch,
}) async {
  if (platform == 'android') {
    log('⚠️  Android 平台暂未实现自动下载 Mihomo 核心，请手动处理。');
    return;
  }

  // Mihomo 核心下载链接使用：darwin (非 macos)、amd64 (非 x64)
  final downloadPlatform = platform == 'macos' ? 'darwin' : platform;
  final downloadArch = arch == 'x64' ? 'amd64' : arch;

  String assetKeyword = '$downloadPlatform-$downloadArch';
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

// 下载 AppImageTool（Linux 打包工具）
Future<void> downloadAppImageTool({
  required String projectRoot,
  required String arch, // x64 或 arm64
}) async {
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

    // AppImageTool 使用 x86_64/aarch64 命名
    final assetKeyword = arch == 'arm64' ? 'aarch64' : 'x86_64';

    final asset = assets.firstWhere((a) {
      final name = a['name'] as String;
      return name.contains(assetKeyword) && name.endsWith('.AppImage');
    }, orElse: () => null);

    if (asset == null) {
      throw Exception('未找到适合 $assetKeyword 架构的 appimagetool');
    }

    final downloadUrl = asset['browser_download_url'] as String;
    final fileName = asset['name'] as String;

    log('📥 下载 $fileName (版本: $tagName)...');

    // 下载文件（处理重定向）
    final client = HttpClient();
    client.autoUncompress = false;
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
    await runProcess('chmod', ['+x', toolPath]);

    final sizeInMB = (bytes.length / (1024 * 1024)).toStringAsFixed(2);
    log('✅ appimagetool 安装完成 ($sizeInMB MB)');
  } catch (e) {
    throw Exception('下载 appimagetool 失败: ${simplifyError(e)}');
  }
}

// 下载 Inno Setup（Windows 打包工具）
Future<String> downloadInnoSetup({required String tempDir}) async {
  log('📡 正在获取 Inno Setup 最新版本信息...');

  // 从环境变量获取 GitHub Token
  final githubToken =
      Platform.environment['GITHUB_TOKEN'] ?? Platform.environment['GH_TOKEN'];

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

  if (response.statusCode != 200) {
    throw Exception('获取版本信息失败: HTTP ${response.statusCode}');
  }

  final data = json.decode(response.body);
  final tagName = data['tag_name'] as String; // 例如: "is-6_6_1"

  // 解析版本号（is-6_6_1 -> 6.6.1）
  final latestVersion = tagName.replaceFirst('is-', '').replaceAll('_', '.');

  // 构建下载 URL
  final downloadUrl =
      'https://github.com/jrsoftware/issrc/releases/download/$tagName/innosetup-$latestVersion.exe';

  log('✅ 最新版本: $latestVersion');
  log('📥 正在下载 Inno Setup $latestVersion...');

  final installerPath = p.join(tempDir, 'innosetup-setup.exe');

  // 下载安装程序（使用代理）
  final client = HttpClient();
  final downloadUri = Uri.parse(downloadUrl);

  // 配置代理（不输出日志，因为已在脚本开始时统一输出）
  configureProxy(client, downloadUri, isFirstAttempt: false);

  final request = await client.getUrl(downloadUri);
  final httpResponse = await request.close();

  if (httpResponse.statusCode != 200) {
    throw Exception('下载失败: HTTP ${httpResponse.statusCode}');
  }

  final installerFile = File(installerPath);
  final sink = installerFile.openWrite();
  await httpResponse.pipe(sink);
  await sink.close();
  client.close();

  final fileSize = (await installerFile.length() / (1024 * 1024))
      .toStringAsFixed(2);
  log('✅ 下载完成 ($fileSize MB)');

  return installerPath;
}
