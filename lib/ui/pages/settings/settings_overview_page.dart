import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stelliberty/utils/logger.dart';

export 'behavior_settings_page.dart';

class SettingsOverviewPage extends StatefulWidget {
  const SettingsOverviewPage({super.key});

  @override
  State<SettingsOverviewPage> createState() => _SettingsOverviewPageState();
}

class _SettingsOverviewPageState extends State<SettingsOverviewPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 SettingsOverviewPage');
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = '${context.translate.about.version} v${packageInfo.version}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context, listen: false);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.translate.common.settings,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(Icons.palette_outlined),
            title: Text(context.translate.theme.title),
            subtitle: Text(context.translate.theme.description),
            onTap: () => provider.switchView(ContentView.settingsAppearance),
            // 只移除点击时的水波纹扩散效果，保留悬停效果
            splashColor: Colors.transparent,
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(Icons.language_outlined),
            title: Text(context.translate.language.title),
            subtitle: Text(context.translate.language.description),
            onTap: () => provider.switchView(ContentView.settingsLanguage),
            // 只移除点击时的水波纹扩散效果，保留悬停效果
            splashColor: Colors.transparent,
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(Icons.settings_suggest_outlined),
            title: Text(context.translate.clashFeatures.title),
            subtitle: Text(context.translate.clashFeatures.description),
            onTap: () => provider.switchView(ContentView.settingsClashFeatures),
            // 只移除点击时的水波纹扩散效果，保留悬停效果
            splashColor: Colors.transparent,
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(Icons.apps_outlined),
            title: Text(context.translate.behavior.title),
            subtitle: Text(context.translate.behavior.description),
            onTap: () => provider.switchView(ContentView.settingsBehavior),
            // 只移除点击时的水波纹扩散效果，保留悬停效果
            splashColor: Colors.transparent,
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: const Icon(Icons.info_outline),
            title: Text(context.translate.about.title),
            subtitle: Text(_version.isEmpty ? '…' : _version),
            onTap: null,
            splashColor: Colors.transparent,
          ),
        ],
      ),
    );
  }
}
