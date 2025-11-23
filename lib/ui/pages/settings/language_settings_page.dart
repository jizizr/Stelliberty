import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/ui/widgets/language_selector.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/utils/logger.dart';

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 LanguageSettingsPage');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context, listen: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 自定义标题栏
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    provider.switchView(ContentView.settingsOverview),
              ),
              const SizedBox(width: 8),
              Text(
                context.translate.language.settings,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        // 可滚动内容
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 3.0, 5.0), // 统一在此处设置边距
            child: Scrollbar(
              thumbVisibility: true,
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                // 移除内部 padding
                physics: const BouncingScrollPhysics(),
                child: const LanguageSelector(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
