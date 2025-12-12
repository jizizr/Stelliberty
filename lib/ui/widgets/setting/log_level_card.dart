import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_dropdown_menu.dart';
import 'package:stelliberty/ui/common/modern_dropdown_button.dart';

// 日志等级枚举
enum LogLevel {
  silent('silent', Icons.volume_off),
  error('error', Icons.error_outline),
  warning('warning', Icons.warning_amber_outlined),
  info('info', Icons.info_outline),
  debug('debug', Icons.bug_report_outlined);

  const LogLevel(this.value, this.icon);

  final String value;
  final IconData icon;

  static LogLevel fromString(String value) {
    for (final level in LogLevel.values) {
      if (level.value == value) return level;
    }
    return LogLevel.info;
  }

  String getDisplayName(BuildContext context) {
    switch (this) {
      case LogLevel.silent:
        return context.translate.logLevel.silent;
      case LogLevel.error:
        return context.translate.logLevel.error;
      case LogLevel.warning:
        return context.translate.logLevel.warning;
      case LogLevel.info:
        return context.translate.logLevel.info;
      case LogLevel.debug:
        return context.translate.logLevel.debug;
    }
  }
}

// 日志等级配置卡片
class LogLevelCard extends StatefulWidget {
  const LogLevelCard({super.key});

  @override
  State<LogLevelCard> createState() => _LogLevelCardState();
}

class _LogLevelCardState extends State<LogLevelCard> {
  late LogLevel _logLevel;
  bool _isHoveringOnLogLevelMenu = false;

  @override
  void initState() {
    super.initState();
    _logLevel = LogLevel.fromString(ClashManager.instance.clashCoreLogLevel);
  }

  @override
  Widget build(BuildContext context) {
    return ModernFeatureCard(
      isSelected: false,
      onTap: () {},
      enableHover: false,
      enableTap: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧图标和标题
          Row(
            children: [
              const Icon(Icons.article_outlined),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.translate.clashFeatures.logLevel.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    context.translate.clashFeatures.logLevel.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          // 右侧下拉菜单
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringOnLogLevelMenu = true),
            onExit: (_) => setState(() => _isHoveringOnLogLevelMenu = false),
            child: ModernDropdownMenu<LogLevel>(
              items: LogLevel.values,
              selectedItem: _logLevel,
              onSelected: (level) {
                setState(() => _logLevel = level);
                final clashProvider = Provider.of<ClashProvider>(
                  context,
                  listen: false,
                );
                clashProvider.configService.setClashCoreLogLevel(level.value);
              },
              itemToString: (level) => level.getDisplayName(context),
              child: CustomDropdownButton(
                text: _logLevel.getDisplayName(context),
                isHovering: _isHoveringOnLogLevelMenu,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
