import 'package:flutter/material.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/model/rule_model.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/services/log_print_service.dart';

class RulesProvider extends ChangeNotifier {
  final ClashProvider _clashProvider;

  List<RuleItem> _rules = [];
  List<RuleItem>? _cachedFilteredRules;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _searchKeyword = '';

  List<RuleItem> get rules {
    _cachedFilteredRules ??= _getFilteredRules();
    return _cachedFilteredRules!;
  }

  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  String get searchKeyword => _searchKeyword;

  RulesProvider(this._clashProvider) {
    _clashProvider.removeListener(_onClashStateChanged);
    _clashProvider.addListener(_onClashStateChanged);

    if (_clashProvider.isCoreRunning) {
      refreshRules(showLoading: true);
    } else {
      _isLoading = false;
    }
  }

  void _onClashStateChanged() {
    if (_clashProvider.isCoreRunning) {
      refreshRules(showLoading: _rules.isEmpty);
    } else {
      _rules = [];
      _cachedFilteredRules = null;
      _isLoading = false;
      _isRefreshing = false;
      _errorMessage = null;
      _searchKeyword = '';
      notifyListeners();
    }
  }

  void setSearchKeyword(String keyword) {
    if (_searchKeyword == keyword) return;
    _searchKeyword = keyword;
    _cachedFilteredRules = null;
    notifyListeners();
  }

  Future<void> refreshRules({required bool showLoading}) async {
    if (!_clashProvider.isCoreRunning) {
      return;
    }

    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    if (showLoading) {
      _isLoading = true;
    }
    _errorMessage = null;
    notifyListeners();

    try {
      final nextRules = await ClashManager.instance.getRules();
      _rules = nextRules;
      _cachedFilteredRules = null;
      Logger.debug('规则列表已更新：${_rules.length} 条');
    } catch (e) {
      _errorMessage = '刷新规则列表失败: $e';
      Logger.error(_errorMessage!);
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  List<RuleItem> _getFilteredRules() {
    if (_searchKeyword.isEmpty) {
      return _rules;
    }

    final keyword = _searchKeyword.toLowerCase();
    return _rules
        .where((rule) {
          return rule.payload.toLowerCase().contains(keyword) ||
              rule.type.toLowerCase().contains(keyword) ||
              rule.proxy.toLowerCase().contains(keyword);
        })
        .toList(growable: false);
  }
}
