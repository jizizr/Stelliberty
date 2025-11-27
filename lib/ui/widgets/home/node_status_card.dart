import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/data/clash_model.dart';
import 'package:stelliberty/ui/widgets/home/base_card.dart';
import 'package:stelliberty/ui/widgets/home/info_container.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 节点状态卡片
//
// 显示当前使用的代理节点名称和网络延迟
class NodeStatusCard extends StatelessWidget {
  const NodeStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final clashProvider = context.watch<ClashProvider>();
    final isRunning = clashProvider.isRunning;
    final mode = clashProvider.mode;

    // 获取当前节点信息
    final nodeInfo = _getCurrentNodeInfo(clashProvider);

    // 获取节点显示名称
    String nodeName = nodeInfo.nodeName;
    if (!isRunning) {
      nodeName = context.translate.home.nodeNotRunning;
    } else if (mode == 'direct') {
      nodeName = context.translate.home.nodeDirectMode;
    }

    // 获取延迟显示
    final delayInfo = _getDelayDisplay(context, nodeInfo, isRunning);

    return BaseCard(
      icon: Icons.cell_tower_outlined,
      title: context.translate.home.nodeStatus,
      child: InfoContainer(
        rows: [
          // 当前节点
          InfoRow.text(
            label: context.translate.home.currentNode,
            description: nodeName,
            value: '',
          ),
          // 网络延迟
          InfoRow.text(
            label: context.translate.home.networkDelay,
            description: delayInfo.text,
            value: '',
            valueStyle: TextStyle(color: delayInfo.color),
            actionIcon: (isRunning && !nodeInfo.isTesting)
                ? Icons.refresh
                : null,
            onActionTap: (isRunning && !nodeInfo.isTesting)
                ? () =>
                      _testDelay(context, clashProvider, nodeInfo.originalName)
                : null,
            actionTooltip: context.translate.home.testDelay,
          ),
        ],
      ),
    );
  }

  // 获取延迟显示信息
  _DelayDisplay _getDelayDisplay(
    BuildContext context,
    _NodeInfo nodeInfo,
    bool isRunning,
  ) {
    if (!isRunning) {
      return _DelayDisplay(
        text: '-',
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }

    if (nodeInfo.isTesting) {
      return _DelayDisplay(
        text: context.translate.home.delayTesting,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (nodeInfo.delay < 0) {
      return _DelayDisplay(
        text: context.translate.home.delayUnknown,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }

    if (nodeInfo.delay == 0) {
      return _DelayDisplay(
        text: context.translate.home.delayDirect,
        color: Colors.green,
      );
    }

    return _DelayDisplay(
      text: '${nodeInfo.delay} ms',
      color: _getDelayColor(nodeInfo.delay),
    );
  }

  // 获取当前节点信息
  _NodeInfo _getCurrentNodeInfo(ClashProvider clashProvider) {
    if (!clashProvider.isRunning) {
      return _NodeInfo(
        nodeName: '-',
        originalName: '-',
        delay: -1,
        isTesting: false,
      );
    }

    final mode = clashProvider.mode;

    // 直连模式
    if (mode == 'direct') {
      return _NodeInfo(
        nodeName: 'DIRECT',
        originalName: 'DIRECT',
        delay: 0,
        isTesting: false,
      );
    }

    // 全局模式：从 GLOBAL 组获取当前节点
    if (mode == 'global') {
      final globalGroup = clashProvider.allProxyGroups.firstWhere(
        (g) => g.name == 'GLOBAL',
        orElse: () =>
            ProxyGroup(name: 'GLOBAL', type: 'Selector', now: null, all: []),
      );

      if (globalGroup.now != null && globalGroup.now!.isNotEmpty) {
        final groupName = globalGroup.now!;
        final resolvedName = clashProvider.resolveProxyNodeName(groupName);
        // 尝试多个可能的键名
        var node = clashProvider.proxyNodes[resolvedName];
        node ??= clashProvider.proxyNodes[groupName];

        return _NodeInfo(
          nodeName: resolvedName,
          originalName: resolvedName,
          delay: node?.delay ?? -1,
          isTesting:
              clashProvider.testingNodes.contains(resolvedName) ||
              clashProvider.testingNodes.contains(groupName),
        );
      }
    }

    // 规则模式：获取第一个可见代理组的当前节点
    if (clashProvider.proxyGroups.isNotEmpty) {
      final firstGroup = clashProvider.proxyGroups.first;
      if (firstGroup.now != null && firstGroup.now!.isNotEmpty) {
        final groupName = firstGroup.now!;
        final resolvedName = clashProvider.resolveProxyNodeName(groupName);
        // 尝试多个可能的键名
        var node = clashProvider.proxyNodes[resolvedName];
        node ??= clashProvider.proxyNodes[groupName];

        return _NodeInfo(
          nodeName: resolvedName,
          originalName: resolvedName,
          delay: node?.delay ?? -1,
          isTesting:
              clashProvider.testingNodes.contains(resolvedName) ||
              clashProvider.testingNodes.contains(groupName),
        );
      }
    }

    return _NodeInfo(
      nodeName: '-',
      originalName: '-',
      delay: -1,
      isTesting: false,
    );
  }

  // 测试延迟
  Future<void> _testDelay(
    BuildContext context,
    ClashProvider clashProvider,
    String nodeName,
  ) async {
    if (nodeName == '-' || nodeName == 'DIRECT') return;
    await clashProvider.testProxyDelay(nodeName);
  }

  // 根据延迟返回对应颜色
  Color _getDelayColor(int delay) {
    if (delay < 100) {
      return Colors.green;
    } else if (delay < 300) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}

// 节点信息数据类
class _NodeInfo {
  final String nodeName;
  final String originalName; // 用于测试延迟的原始节点名
  final int delay;
  final bool isTesting;

  _NodeInfo({
    required this.nodeName,
    required this.originalName,
    required this.delay,
    required this.isTesting,
  });
}

// 延迟显示数据类
class _DelayDisplay {
  final String text;
  final Color color;

  _DelayDisplay({required this.text, required this.color});
}
