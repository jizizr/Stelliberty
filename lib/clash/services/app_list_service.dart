import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../state/access_control_states.dart';

// 应用列表服务：通过 MethodChannel 获取已安装应用信息。
// 仅 Android 平台支持。
class AppListService {
  static const MethodChannel _channel = MethodChannel(
    'io.github.stelliberty/app_list',
  );

  // 是否支持当前平台
  static bool get isSupported => Platform.isAndroid;

  // 获取已安装应用列表
  static Future<List<AppInfo>> getInstalledApps() async {
    if (!isSupported) return [];
    final result = await _channel.invokeMethod<String>('getInstalledApps');
    if (result == null) return [];
    final List<dynamic> jsonList = jsonDecode(result) as List<dynamic>;
    return jsonList
        .map((e) => AppInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 获取应用图标
  // 返回 PNG 格式的字节数据
  static Future<Uint8List?> getAppIcon(String packageName) async {
    if (!isSupported) return null;
    final result = await _channel.invokeMethod<Uint8List>('getAppIcon', {
      'packageName': packageName,
    });
    return result;
  }
}
