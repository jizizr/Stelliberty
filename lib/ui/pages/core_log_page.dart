import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/model/log_message_model.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/clash/providers/core_log_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/widgets/core_log/core_log_card.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/ui/common/modern_top_toolbar.dart';
import 'package:stelliberty/ui/constants/spacing.dart';

// 日志页布局常量
class _LogListSpacing {
  _LogListSpacing._();

  static const listLeftEdge = 16.0;
  static const listTopEdge = 16.0;
  static const listRightEdge =
      16.0 - SpacingConstants.scrollbarRightCompensation;
  static const listBottomEdge = 10.0;

  static const cardHeight = 72.0; // 日志卡片高度
  static const cardSpacing = 16.0; // 日志卡片间距

  static const listPadding = EdgeInsets.fromLTRB(
    listLeftEdge,
    listTopEdge,
    listRightEdge,
    listBottomEdge,
  );
}

// 日志页面：展示核心实时日志流。
// 使用 Provider 管理状态，避免切换页面时丢失日志。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isFirstLoad = true; // 标记是否是首次加载

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 LogPage');

    // 延迟加载日志列表（给顶栏先渲染的机会）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clashProvider = context.watch<ClashProvider>();
    final isRunning = clashProvider.isCoreRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 过滤器和控制栏（立即显示，不依赖 Provider 数据）
        _isFirstLoad
            ? _buildFilterBarSkeleton(context)
            : _buildFilterBar(context),

        // 统一的分隔线
        const Divider(height: 1, thickness: 1),

        // 日志列表（延迟渲染）
        Expanded(
          child: Padding(
            padding: SpacingConstants.scrollbarPadding,
            child: _isFirstLoad
                ? _buildLoadingState(context)
                : (isRunning
                      ? _buildLogList(context)
                      : _buildEmptyState(context)),
          ),
        ),
      ],
    );
  }

  // 构建过滤器栏骨架屏（立即显示，无需等待数据）
  Widget _buildFilterBarSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // 过滤器占位符
          Container(
            width: 400,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(
                ModernTopToolbarTokens.radius,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 搜索框占位符
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(
                  ModernTopToolbarTokens.radius,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 按钮组占位符
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(
                    ModernTopToolbarTokens.radius,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 40,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(
                    ModernTopToolbarTokens.radius,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 构建过滤器和控制栏（扁平化 MD3 风格）
  Widget _buildFilterBar(BuildContext context) {
    final trans = context.translate;

    return Consumer<LogProvider>(
      builder: (context, provider, child) {
        return ModernTopToolbar(
          children: [
            // 过滤按钮组
            ModernTopToolbarChipGroup(
              children: [
                ModernTopToolbarChip(
                  label: trans.logs.all_levels,
                  isSelected: provider.filterLevel == null,
                  onTap: () => provider.setFilterLevel(null),
                ),
                const SizedBox(width: 4),
                ModernTopToolbarChip(
                  label: ClashLogLevel.debug.getDisplayName(context),
                  isSelected: provider.filterLevel == ClashLogLevel.debug,
                  onTap: () => provider.setFilterLevel(ClashLogLevel.debug),
                ),
                const SizedBox(width: 4),
                ModernTopToolbarChip(
                  label: ClashLogLevel.info.getDisplayName(context),
                  isSelected: provider.filterLevel == ClashLogLevel.info,
                  onTap: () => provider.setFilterLevel(ClashLogLevel.info),
                ),
                const SizedBox(width: 4),
                ModernTopToolbarChip(
                  label: ClashLogLevel.warning.getDisplayName(context),
                  isSelected: provider.filterLevel == ClashLogLevel.warning,
                  onTap: () => provider.setFilterLevel(ClashLogLevel.warning),
                ),
                const SizedBox(width: 4),
                ModernTopToolbarChip(
                  label: ClashLogLevel.error.getDisplayName(context),
                  isSelected: provider.filterLevel == ClashLogLevel.error,
                  onTap: () => provider.setFilterLevel(ClashLogLevel.error),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              // 搜索框
              child: ModernTopToolbarSearchField(
                hintText: trans.logs.search_placeholder,
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
                  tooltip: trans.logs.clear_logs,
                  icon: Icons.delete_outline_rounded,
                  onPressed: provider.logs.isEmpty ? null : provider.clearLogs,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // 构建日志列表
  Widget _buildLogList(BuildContext context) {
    return Consumer<LogProvider>(
      builder: (context, provider, child) {
        final trans = context.translate;
        final filteredLogs = provider.filteredLogs;

        if (filteredLogs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  provider.logs.isEmpty
                      ? trans.logs.empty_logs
                      : trans.logs.empty_filtered,
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

        return GridView.builder(
          controller: _scrollController,
          padding: _LogListSpacing.listPadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1, // 单列显示
            mainAxisSpacing: _LogListSpacing.cardSpacing,
            mainAxisExtent: _LogListSpacing.cardHeight,
          ),
          itemCount: filteredLogs.length,
          addAutomaticKeepAlives: false, // 减少内存占用
          addRepaintBoundaries: true, // 优化重绘性能
          itemBuilder: (context, index) {
            // 倒序显示日志（最新在顶部）
            final reversedIndex = filteredLogs.length - 1 - index;
            return LogCard(log: filteredLogs[reversedIndex]);
          },
        );
      },
    );
  }

  // 构建加载状态（首次进入页面时）
  Widget _buildLoadingState(BuildContext context) {
    final trans = context.translate;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            trans.logs.loading_logs,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // 构建空状态（Clash 未运行）
  Widget _buildEmptyState(BuildContext context) {
    final trans = context.translate;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            trans.logs.clash_not_running,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            trans.logs.start_clash_to_view_logs,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
