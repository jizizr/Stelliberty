import 'dart:async';
import 'dart:io';
import 'common.dart';

// HTTP 下载选项
class DownloadOptions {
  final int maxRetries;
  final Duration timeout;
  final bool showProgress;
  final void Function(int current, int total)? onProgress;

  const DownloadOptions({
    this.maxRetries = 5,
    this.timeout = const Duration(minutes: 5),
    this.showProgress = true,
    this.onProgress,
  });
}

// 带重试机制的 HTTP 下载
Future<List<int>> downloadWithRetry(
  Uri url, {
  required void Function(HttpClient) configureClient,
  DownloadOptions options = const DownloadOptions(),
  String? fileName,
}) async {
  Exception? lastException;
  final displayName = fileName ?? url.pathSegments.last;

  for (int attempt = 1; attempt <= options.maxRetries; attempt++) {
    HttpClient? client;

    try {
      if (attempt > 1) {
        log('🔄 重试下载 $displayName (第 $attempt 次)...');
        // 重试前等待
        await Future.delayed(Duration(seconds: 2));
      } else if (options.showProgress) {
        log('📥 正在下载 $displayName...');
      }

      client = HttpClient();
      configureClient(client);

      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        options.timeout,
        onTimeout: () => throw TimeoutException('下载超时'),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final bodyBytes = await response.fold<List<int>>(<int>[], (
        previous,
        element,
      ) {
        final result = previous..addAll(element);
        // 调用进度回调
        options.onProgress?.call(result.length, response.contentLength);
        return result;
      });

      client.close();

      if (options.showProgress) {
        final sizeInMB = (bodyBytes.length / (1024 * 1024)).toStringAsFixed(2);
        log('✅ $displayName 下载完成 ($sizeInMB MB)');
      }

      return bodyBytes;
    } catch (e) {
      client?.close();
      lastException = e is Exception ? e : Exception(e.toString());
      final simpleError = simplifyError(e);

      if (attempt < options.maxRetries) {
        log(
          '⚠️  $displayName 下载失败 (尝试 $attempt/${options.maxRetries}): $simpleError',
        );
      } else {
        log('❌ $displayName 下载失败 (已重试 ${options.maxRetries} 次): $simpleError');
      }
    }
  }

  throw Exception(
    '$displayName 下载失败，已重试 ${options.maxRetries} 次: ${lastException?.toString()}',
  );
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
