import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/providers/language_provider.dart';
import 'package:stelliberty/ui/common/modern_dropdown_menu.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';
import 'package:stelliberty/ui/common/modern_dropdown_button.dart';

// 语言选择器组件，允许用户选择应用语言
class LanguageSelector extends StatefulWidget {
  const LanguageSelector({super.key});

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  bool _isHoveringOnLanguageMenu = false;

  @override
  Widget build(BuildContext context) {
    final trans = context.translate;
    final languageProvider = context.watch<LanguageProvider>();
    final currentDisplayName = languageProvider.languageMode.displayName(context);

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
                  trans.language.settings,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _isHoveringOnLanguageMenu = true),
              onExit: (_) => setState(() => _isHoveringOnLanguageMenu = false),
              child: ModernDropdownMenu<AppLanguageMode>(
                items: languageProvider.availableLanguages,
                selectedItem: languageProvider.languageMode,
                onSelected: (mode) => languageProvider.setLanguageMode(mode),
                itemToString: (mode) => mode.displayName(context),
                child: CustomDropdownButton(
                  text: currentDisplayName,
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
