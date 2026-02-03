import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/providers/rules_provider.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/constants/spacing.dart';
import 'package:stelliberty/ui/common/modern_top_toolbar.dart';
import 'package:stelliberty/ui/widgets/rules/rule_card.dart';

class _RulesListSpacing {
  _RulesListSpacing._();

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

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSyncingSearchController = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RulesProvider>(
      builder: (context, provider, child) {
        _syncSearchController(provider.searchKeyword);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlBar(context, provider),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: SpacingConstants.scrollbarPadding,
                child: _buildRulesList(context, provider),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlBar(BuildContext context, RulesProvider provider) {
    final trans = context.translate;

    return ModernTopToolbar(
      children: [
        Expanded(
          // 搜索框
          child: ModernTopToolbarSearchField(
            controller: _searchController,
            hintText: trans.rules.search_placeholder,
            onChanged: (value) {
              if (_isSyncingSearchController) return;
              provider.setSearchKeyword(value);
            },
          ),
        ),
        const SizedBox(width: 12),
        // 操作按钮组
        ModernTopToolbarActionGroup(
          children: [
            ModernTopToolbarIconButton(
              tooltip: trans.common.refresh,
              icon: provider.isRefreshing
                  ? Icons.hourglass_top_rounded
                  : Icons.refresh_rounded,
              onPressed: provider.isRefreshing
                  ? null
                  : () => provider.refreshRules(showLoading: false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRulesList(BuildContext context, RulesProvider provider) {
    final trans = context.translate;
    final isCoreRunning = context.select<ClashProvider, bool>(
      (p) => p.isCoreRunning,
    );

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Text(
          provider.errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (!isCoreRunning) {
      return Center(child: Text(trans.rules.core_not_running));
    }

    final rules = provider.rules;
    if (rules.isEmpty) {
      return Center(child: Text(trans.rules.empty));
    }

    return Scrollbar(
      controller: _scrollController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 800 ? 2 : 1;
          final mainAxisExtent = crossAxisCount >= 2 ? 96.0 : 88.0;

          return GridView.builder(
            controller: _scrollController,
            padding: _RulesListSpacing.gridPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: _RulesListSpacing.cardColumnSpacing,
              mainAxisSpacing: _RulesListSpacing.cardRowSpacing,
              mainAxisExtent: mainAxisExtent,
            ),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              return RuleCard(index: index + 1, rule: rules[index]);
            },
          );
        },
      ),
    );
  }

  void _syncSearchController(String searchKeyword) {
    if (_searchController.text == searchKeyword) return;

    _isSyncingSearchController = true;
    _searchController.value = TextEditingValue(
      text: searchKeyword,
      selection: TextSelection.collapsed(offset: searchKeyword.length),
    );
    _isSyncingSearchController = false;
  }
}
