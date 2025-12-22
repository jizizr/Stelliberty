import 'dart:io';

// 日志函数
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
