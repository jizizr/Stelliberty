import 'package:flutter/material.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/storage/preferences.dart';
import 'package:stelliberty/ui/common/modern_dropdown_menu.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_dropdown_button.dart';

// 语言模式枚举，定义可用的语言选项
enum AppLanguageMode {
  system('system'),
  zh('zh'),
  en('en');

  const AppLanguageMode(this.value);

  // 用于持久化存储的字符串值
  final String value;

  // 获取本地化显示名称
  String displayName(BuildContext context) {
    switch (this) {
      case AppLanguageMode.system:
        return context.translate.language.modeSystem;
      case AppLanguageMode.zh:
        return context.translate.language.modeZh;
      case AppLanguageMode.en:
        return context.translate.language.modeEn;
    }
  }

  // 将存储的字符串解析为对应的语言模式
  static AppLanguageMode fromString(String value) {
    for (final mode in AppLanguageMode.values) {
      if (mode.value == value) return mode;
    }
    return AppLanguageMode.system; // 默认跟随系统
  }
}

// 语言选择器组件，允许用户选择应用语言
class LanguageSelector extends StatefulWidget {
  const LanguageSelector({super.key});

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  bool _isHoveringOnLanguageMenu = false;
  AppLanguageMode _currentLanguage = AppLanguageMode.system;

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  // 加载当前语言设置
  void _loadCurrentLanguage() {
    final savedLanguage = AppPreferences.instance.getLanguageMode();
    setState(() {
      _currentLanguage = AppLanguageMode.fromString(savedLanguage);
    });
  }

  // 切换语言
  void _changeLanguage(AppLanguageMode mode) async {
    setState(() {
      _currentLanguage = mode;
    });

    // 保存语言设置到存储
    await AppPreferences.instance.setLanguageMode(mode.value);

    // 应用语言切换
    switch (mode) {
      case AppLanguageMode.system:
        LocaleSettings.useDeviceLocale();
        break;
      case AppLanguageMode.zh:
        LocaleSettings.setLocale(AppLocale.zhCn);
        break;
      case AppLanguageMode.en:
        LocaleSettings.setLocale(AppLocale.en);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ModernFeatureCard(
        isSelected: false,
        onTap: () {},
        enableHover: false,
        enableTap: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(Icons.language_outlined),
                const SizedBox(
                  width: ModernFeatureCardSpacing.featureIconToTextSpacing,
                ),
                Text(
                  context.translate.language.settings,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _isHoveringOnLanguageMenu = true),
              onExit: (_) => setState(() => _isHoveringOnLanguageMenu = false),
              child: ModernDropdownMenu<AppLanguageMode>(
                items: AppLanguageMode.values,
                selectedItem: _currentLanguage,
                onSelected: _changeLanguage,
                itemToString: (mode) => mode.displayName(context),
                child: CustomDropdownButton(
                  text: _currentLanguage.displayName(context),
                  isHovering: _isHoveringOnLanguageMenu,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
