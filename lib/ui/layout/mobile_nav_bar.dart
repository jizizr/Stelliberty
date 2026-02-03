import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 移动端底部导航栏
// 提供主要功能页面的快速切换
class MobileNavBar extends StatelessWidget {
  const MobileNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context);
    final currentView = provider.currentView;
    final trans = context.translate;

    // 根据当前视图确定选中的底部导航项
    final selectedIndex = _getSelectedIndex(currentView);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        if (index == 3) {
          // "更多"按钮：显示弹出菜单
          _showMoreMenu(context, provider, trans);
        } else {
          final view = _getViewFromIndex(index);
          provider.switchView(view);
        }
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: trans.sidebar.home,
        ),
        NavigationDestination(
          icon: const Icon(Icons.lan_outlined),
          selectedIcon: const Icon(Icons.lan_rounded),
          label: trans.sidebar.proxy,
        ),
        NavigationDestination(
          icon: const Icon(Icons.link_outlined),
          selectedIcon: const Icon(Icons.link_rounded),
          label: trans.sidebar.subscriptions,
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_outlined),
          selectedIcon: const Icon(Icons.more_horiz_rounded),
          label: trans.common.more,
        ),
      ],
    );
  }

  // 显示"更多"弹出菜单
  void _showMoreMenu(
    BuildContext context,
    ContentProvider provider,
    Translations trans,
  ) {
    final currentView = provider.currentView;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 设置
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(trans.sidebar.settings),
                selected: _isSettingsView(currentView),
                onTap: () {
                  Navigator.pop(context);
                  provider.switchView(ContentView.settingsOverview);
                },
              ),
              // 连接
              ListTile(
                leading: const Icon(Icons.device_hub_outlined),
                title: Text(trans.sidebar.connections),
                selected: currentView == ContentView.connections,
                onTap: () {
                  Navigator.pop(context);
                  provider.switchView(ContentView.connections);
                },
              ),
              // 日志
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(trans.sidebar.logs),
                selected: currentView == ContentView.logs,
                onTap: () {
                  Navigator.pop(context);
                  provider.switchView(ContentView.logs);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 判断是否为设置相关视图
  bool _isSettingsView(ContentView view) {
    switch (view) {
      case ContentView.settingsOverview:
      case ContentView.settingsAppearance:
      case ContentView.settingsBehavior:
      case ContentView.settingsLanguage:
      case ContentView.settingsClashFeatures:
      case ContentView.settingsClashNetworkSettings:
      case ContentView.settingsClashPortControl:
      case ContentView.settingsClashSystemIntegration:
      case ContentView.settingsClashDnsConfig:
      case ContentView.settingsClashPerformance:
      case ContentView.settingsClashLogsDebug:
      case ContentView.settingsBackup:
      case ContentView.settingsAppUpdate:
      case ContentView.settingsAccessControl:
        return true;
      default:
        return false;
    }
  }

  // 根据当前视图获取底部导航索引
  int _getSelectedIndex(ContentView view) {
    switch (view) {
      case ContentView.home:
        return 0;
      case ContentView.proxy:
        return 1;
      case ContentView.subscriptions:
      case ContentView.overrides:
      case ContentView.rules:
        return 2;
      // 更多菜单中的页面
      case ContentView.connections:
      case ContentView.logs:
      case ContentView.settingsOverview:
      case ContentView.settingsAppearance:
      case ContentView.settingsBehavior:
      case ContentView.settingsLanguage:
      case ContentView.settingsClashFeatures:
      case ContentView.settingsClashNetworkSettings:
      case ContentView.settingsClashPortControl:
      case ContentView.settingsClashSystemIntegration:
      case ContentView.settingsClashDnsConfig:
      case ContentView.settingsClashPerformance:
      case ContentView.settingsClashLogsDebug:
      case ContentView.settingsBackup:
      case ContentView.settingsAppUpdate:
      case ContentView.settingsAccessControl:
        return 3;
    }
  }

  // 根据底部导航索引获取对应视图
  ContentView _getViewFromIndex(int index) {
    switch (index) {
      case 0:
        return ContentView.home;
      case 1:
        return ContentView.proxy;
      case 2:
        return ContentView.subscriptions;
      default:
        return ContentView.home;
    }
  }
}
