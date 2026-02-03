import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/services/app_list_service.dart';
import 'package:stelliberty/clash/state/access_control_states.dart';
import 'package:stelliberty/storage/preferences.dart';
import 'package:stelliberty/services/log_print_service.dart';

// 应用访问控制状态管理
// 仅 Android 平台支持
class AccessControlProvider extends ChangeNotifier {
  AccessControlMode _mode = AccessControlMode.disabled;
  Set<String> _selectedPackages = {};
  List<AppInfo> _installedApps = [];
  bool _isLoading = true;
  bool _isLoadingApps = false;
  String _searchQuery = '';
  bool _showSystemApps = false;

  // 应用图标缓存
  final Map<String, Uint8List?> _cachedIcons = {};

  AccessControlMode get mode => _mode;
  Set<String> get selectedPackages => _selectedPackages;
  List<AppInfo> get installedApps => _installedApps;
  bool get isLoading => _isLoading;
  bool get isLoadingApps => _isLoadingApps;
  String get searchQuery => _searchQuery;
  bool get showSystemApps => _showSystemApps;

  // 是否支持当前平台
  bool get isSupported => AppListService.isSupported;

  // 是否启用访问控制
  bool get isEnabled => _mode != AccessControlMode.disabled;

  // 获取当前配置
  AccessControlConfig get config =>
      AccessControlConfig(mode: _mode, selectedPackages: _selectedPackages);

  // 过滤后的应用列表
  List<AppInfo> get filteredApps {
    var apps = _installedApps;

    // 过滤系统应用
    if (!_showSystemApps) {
      apps = apps.where((app) => !app.isSystem).toList();
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      apps = apps.where((app) {
        return app.label.toLowerCase().contains(query) ||
            app.packageName.toLowerCase().contains(query);
      }).toList();
    }

    return apps;
  }

  // 已选中的应用数量
  int get selectedCount => _selectedPackages.length;

  AccessControlProvider() {
    _initialize();
  }

  // 初始化
  Future<void> _initialize() async {
    if (!isSupported) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _loadSettings();
    _isLoading = false;
    notifyListeners();
  }

  // 从本地存储加载设置
  void _loadSettings() {
    final prefs = AppPreferences.instance;
    final modeValue = prefs.getAccessControlMode();
    _mode = AccessControlModeExtension.fromAndroidValue(modeValue);
    _selectedPackages = prefs.getAccessControlPackages();
  }

  // 加载已安装应用列表
  Future<void> loadInstalledApps() async {
    if (!isSupported || _isLoadingApps) return;

    _isLoadingApps = true;
    notifyListeners();

    try {
      _installedApps = await AppListService.getInstalledApps();
      // 按标签排序
      _installedApps.sort((a, b) => a.label.compareTo(b.label));
      Logger.info('已加载 ${_installedApps.length} 个应用');
    } catch (e) {
      Logger.error('加载应用列表失败: $e');
    } finally {
      _isLoadingApps = false;
      notifyListeners();
    }
  }

  // 获取应用图标
  Future<Uint8List?> getAppIcon(String packageName) async {
    if (_cachedIcons.containsKey(packageName)) {
      return _cachedIcons[packageName];
    }

    final icon = await AppListService.getAppIcon(packageName);
    _cachedIcons[packageName] = icon;
    return icon;
  }

  // 更新访问控制模式
  Future<void> updateMode(AccessControlMode newMode) async {
    if (_mode == newMode) return;

    _mode = newMode;
    notifyListeners();

    await AppPreferences.instance.setAccessControlMode(
      newMode.toAndroidValue(),
    );
    Logger.info('访问控制模式已更新: $newMode');
  }

  // 切换应用选中状态
  Future<void> togglePackage(String packageName) async {
    if (_selectedPackages.contains(packageName)) {
      _selectedPackages.remove(packageName);
    } else {
      _selectedPackages.add(packageName);
    }
    notifyListeners();

    await AppPreferences.instance.setAccessControlPackages(_selectedPackages);
  }

  // 选中所有过滤后的应用
  Future<void> selectAll() async {
    for (final app in filteredApps) {
      _selectedPackages.add(app.packageName);
    }
    notifyListeners();

    await AppPreferences.instance.setAccessControlPackages(_selectedPackages);
  }

  // 取消选中所有应用
  Future<void> deselectAll() async {
    _selectedPackages.clear();
    notifyListeners();

    await AppPreferences.instance.setAccessControlPackages(_selectedPackages);
  }

  // 更新搜索查询
  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // 切换显示系统应用
  void toggleShowSystemApps() {
    _showSystemApps = !_showSystemApps;
    notifyListeners();
  }

  // 检查应用是否被选中
  bool isPackageSelected(String packageName) {
    return _selectedPackages.contains(packageName);
  }

  // 清除图标缓存
  void clearIconCache() {
    _cachedIcons.clear();
  }
}
