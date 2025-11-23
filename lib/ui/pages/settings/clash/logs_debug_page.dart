import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/content_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/widgets/setting/log_level_card.dart';
import 'package:stelliberty/ui/widgets/setting/test_url_card.dart';
import 'package:stelliberty/ui/widgets/setting/user_agent_card.dart';
import 'package:stelliberty/utils/logger.dart';

class LogsDebugPage extends StatefulWidget {
  const LogsDebugPage({super.key});

  @override
  State<LogsDebugPage> createState() => _LogsDebugPageState();
}

class _LogsDebugPageState extends State<LogsDebugPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 LogsDebugPage');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context, listen: false);
    final theme = Theme.of(context);

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
                    provider.switchView(ContentView.settingsClashFeatures),
              ),
              const SizedBox(width: 8),
              Text(
                context.translate.clashFeatures.logsDebug.pageTitle,
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        ),
        // 可滚动内容
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 3.0, 5.0),
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LogLevelCard(),
                    SizedBox(height: 16),
                    TestUrlCard(),
                    SizedBox(height: 16),
                    UserAgentCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
