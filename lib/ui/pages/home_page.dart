import 'package:flutter/material.dart';
import 'package:stelliberty/ui/widgets/home/clash_info_card.dart';
import 'package:stelliberty/ui/widgets/home/proxy_mode_card.dart';
import 'package:stelliberty/ui/widgets/home/proxy_switch_card.dart';
import 'package:stelliberty/ui/widgets/home/traffic_stats_card.dart';
import 'package:stelliberty/utils/logger.dart';

// 主页 - 代理控制中心
class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  @override
  void initState() {
    super.initState();
    Logger.info('初始化 HomePageContent');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 3.0, 5.0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ProxySwitchCard()),
                  const SizedBox(width: 24),
                  Expanded(child: ClashInfoCard()),
                ],
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: TrafficStatsCard()),
                  const SizedBox(width: 24),
                  Expanded(child: ProxyModeCard()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
