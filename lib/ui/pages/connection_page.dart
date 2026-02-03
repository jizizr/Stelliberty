import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/providers/connection_provider.dart';
import 'package:stelliberty/clash/state/connection_states.dart';
import 'package:stelliberty/clash/model/connection_model.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/widgets/connection/connection_card.dart';
import 'package:stelliberty/ui/widgets/connection/connection_detail_dialog.dart';
import 'package:stelliberty/ui/common/modern_top_toolbar.dart';
import 'package:stelliberty/ui/constants/spacing.dart';

// 连接页布局常量
class _ConnectionGridSpacing {
  _ConnectionGridSpacing._();

  static const gridLeftEdge = 16.0;
  static const gridTopEdge = 16.0;
  static const gridRightEdge =
      16.0 - SpacingConstants.scrollbarRightCompensation;
  static const gridBottomEdge = 10.0;
  static const cardColumnSpacing = 16.0;
  static const cardRowSpacing = 16.0;

  static const gridPadding = EdgeInsets.fromLTRB(
    gridLeftEdge,
    gridTopEdge,
    gridRightEdge,
    gridBottomEdge,
  );
}

// 连接页面 - 显示当前活跃的连接
// 使用 Material Design 3 风格，与代理和订阅页面保持一致
class ConnectionPageContent extends StatefulWidget {
  const ConnectionPageContent({super.key});

  @override
  State<ConnectionPageContent> createState() => _ConnectionPageContentState();
}

class _ConnectionPageContentState extends State<ConnectionPageContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 ConnectionPage');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        final connections = connectionProvider.connections;
        final isLoading = connectionProvider.isLoading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 过滤器和控制栏（扁平化设计）
            _buildFilterBar(context, connectionProvider, connections),

            // 统一的分隔线（与代理和订阅页面相同高度）
            const Divider(height: 1, thickness: 1),

            // 连接列表
            Expanded(
              child: Padding(
                padding: SpacingConstants.scrollbarPadding,
                child: _buildConnectionList(
                  context,
                  connectionProvider,
                  connections,
                  isLoading,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 构建过滤器和控制栏（扁平化 MD3 风格）
  Widget _buildFilterBar(
    BuildContext context,
    ConnectionProvider provider,
    List<ConnectionInfo> connections,
  ) {
    final trans = context.translate;
    final totalCount = connections.length;

    return ModernTopToolbar(
      children: [
        // 过滤按钮组
        ModernTopToolbarChipGroup(
          children: [
            ModernTopToolbarChip(
              label: trans.connection.all_connections,
              isSelected: provider.filterLevel == ConnectionFilterLevel.all,
              onTap: () => provider.setFilterLevel(ConnectionFilterLevel.all),
            ),
            const SizedBox(width: 4),
            ModernTopToolbarChip(
              label: trans.connection.direct_connections,
              isSelected: provider.filterLevel == ConnectionFilterLevel.direct,
              onTap: () =>
                  provider.setFilterLevel(ConnectionFilterLevel.direct),
            ),
            const SizedBox(width: 4),
            ModernTopToolbarChip(
              label: trans.connection.proxied_connections,
              isSelected: provider.filterLevel == ConnectionFilterLevel.proxy,
              onTap: () => provider.setFilterLevel(ConnectionFilterLevel.proxy),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          // 搜索框
          child: ModernTopToolbarSearchField(
            hintText: trans.connection.search_placeholder,
            onChanged: provider.setSearchKeyword,
          ),
        ),
        const SizedBox(width: 12),
        // 操作按钮组
        ModernTopToolbarActionGroup(
          children: [
            ModernTopToolbarIconButton(
              tooltip: provider.isMonitoringPaused
                  ? trans.connection.resume_btn
                  : trans.connection.pause_btn,
              icon: provider.isMonitoringPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              onPressed: provider.togglePause,
            ),
            const SizedBox(width: 4),
            ModernTopToolbarIconButton(
              tooltip: trans.connection.close_all_connections,
              icon: Icons.clear_all_rounded,
              onPressed: totalCount > 0
                  ? () => _closeAllConnections(context, provider)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  // 构建连接列表
  Widget _buildConnectionList(
    BuildContext context,
    ConnectionProvider provider,
    List<ConnectionInfo> connections,
    bool isLoading,
  ) {
    final trans = context.translate;

    if (isLoading && connections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (connections.isEmpty) {
      Logger.debug(
        '连接页显示空状态（过滤级别：${provider.filterLevel.name}，搜索关键字：${provider.searchKeyword.isEmpty ? "无" : provider.searchKeyword}）',
      );
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.link_off_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              trans.connection.no_active_connections,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    // 固定每行两个卡片
    return GridView.builder(
      controller: _scrollController,
      padding: _ConnectionGridSpacing.gridPadding,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 固定每行两个
        crossAxisSpacing: _ConnectionGridSpacing.cardColumnSpacing,
        mainAxisSpacing: _ConnectionGridSpacing.cardRowSpacing,
        mainAxisExtent: 120.0, // 更紧凑的卡片高度
      ),
      itemCount: connections.length,
      itemBuilder: (context, index) {
        final connection = connections[index];
        return ConnectionCard(
          connection: connection,
          onTap: () => _showConnectionDetails(context, connection),
          onClose: () => _closeConnection(context, provider, connection),
        );
      },
    );
  }

  // 关闭单个连接
  void _closeConnection(
    BuildContext context,
    ConnectionProvider provider,
    ConnectionInfo connection,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final trans = context.translate;
        return AlertDialog(
          title: Text(trans.common.confirm),
          content: Text(trans.connection.close_connection_confirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(trans.common.cancel),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await provider.closeConnection(connection.id);
              },
              child: Text(trans.common.ok),
            ),
          ],
        );
      },
    );
  }

  // 关闭所有连接
  void _closeAllConnections(BuildContext context, ConnectionProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        final trans = context.translate;
        return AlertDialog(
          title: Text(trans.common.confirm),
          content: Text(trans.connection.close_all_confirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(trans.common.cancel),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await provider.closeAllConnections();
              },
              child: Text(trans.common.ok),
            ),
          ],
        );
      },
    );
  }

  // 显示连接详情
  void _showConnectionDetails(BuildContext context, ConnectionInfo connection) {
    ConnectionDetailDialog.show(context, connection);
  }
}
