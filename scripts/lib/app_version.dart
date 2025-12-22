import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

// 读取版本号
Future<Map<String, String>> readVersionInfo(String projectRoot) async {
  final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!await pubspecFile.exists()) {
    throw Exception('未找到 pubspec.yaml 文件');
  }

  final content = await pubspecFile.readAsString();
  final yaml = loadYaml(content);

  final name = yaml['name'] as String? ?? 'app';
  final version = yaml['version'] as String? ?? '0.0.0';

  // 解析版本号（格式：1.0.0+1 或 1.0.0-beta+1）
  final versionParts = version.split('+');
  final versionNumber = versionParts[0]; // 例如 1.0.0 或 1.0.0-beta

  return {'name': name, 'version': versionNumber};
}
