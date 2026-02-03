import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:stelliberty/clash/model/traffic_data_model.dart';
import 'package:stelliberty/clash/manager/clash_manager.dart';
import 'package:stelliberty/clash/state/traffic_states.dart';
import 'package:stelliberty/services/log_print_service.dart';
import 'package:stelliberty/storage/preferences.dart';

// 流量统计状态管理
// 订阅流量数据流，管理累计流量和波形图历史
class TrafficProvider extends ChangeNotifier {
  final ClashManager _clashManager = ClashManager.instance;
  StreamSubscription<TrafficData>? _trafficSubscription;
  Timer? _retryTimer;
  Timer? _persistTimer;

  TrafficState _state = TrafficState.initial();
  DateTime? _lastTimestamp;

  static const String _kTrafficTotalUpload = 'traffic_total_upload';
  static const String _kTrafficTotalDownload = 'traffic_total_download';

  // Getters
  int get totalUpload => _state.totalUpload;
  int get totalDownload => _state.totalDownload;
  TrafficData? get lastTrafficData => _state.lastTrafficData;
  List<double> get uploadHistory => UnmodifiableListView(_state.uploadHistory);
  List<double> get downloadHistory =>
      UnmodifiableListView(_state.downloadHistory);

  TrafficProvider() {
    _initializePersistedState();
    _subscribeToTrafficStream();
  }

  // 订阅流量数据流
  void _subscribeToTrafficStream() {
    final stream = _clashManager.trafficStream;

    if (stream != null) {
      _trafficSubscription = stream.listen(
        (trafficData) {
          _handleTrafficData(trafficData);
        },
        onError: (error) {
          Logger.error('流量数据流错误：$error');
        },
      );
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _retryTimer?.cancel();
      _retryTimer = Timer(
        const Duration(seconds: 1),
        _subscribeToTrafficStream,
      );
    }
  }

  // 处理流量数据
  void _handleTrafficData(TrafficData data) {
    final now = data.timestamp;
    int nextTotalUpload = _state.totalUpload;
    int nextTotalDownload = _state.totalDownload;

    if (_lastTimestamp != null) {
      final interval = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
      if (interval > 0 && interval < 10) {
        nextTotalUpload += (data.upload * interval).round();
        nextTotalDownload += (data.download * interval).round();
      }
    }
    _lastTimestamp = now;

    final nextUploadHistory = List<double>.from(_state.uploadHistory);
    nextUploadHistory.removeAt(0);
    nextUploadHistory.add(data.upload / 1024.0);

    final nextDownloadHistory = List<double>.from(_state.downloadHistory);
    nextDownloadHistory.removeAt(0);
    nextDownloadHistory.add(data.download / 1024.0);

    final nextTrafficData = data.copyWithTotal(
      totalUpload: nextTotalUpload,
      totalDownload: nextTotalDownload,
    );

    _state = _state.copyWith(
      totalUpload: nextTotalUpload,
      totalDownload: nextTotalDownload,
      lastTimestamp: now,
      lastTrafficData: nextTrafficData,
      uploadHistory: nextUploadHistory,
      downloadHistory: nextDownloadHistory,
    );

    _schedulePersist();
    notifyListeners();
  }

  // 重置累计流量
  void resetTotalTraffic() {
    final now = DateTime.now();
    final cachedTrafficData = _state.lastTrafficData;
    final fallbackTrafficData = TrafficData(
      upload: 0,
      download: 0,
      timestamp: now,
    );

    _state = _state.copyWith(
      totalUpload: 0,
      totalDownload: 0,
      lastTimestamp: now,
      lastTrafficData: (cachedTrafficData ?? fallbackTrafficData).copyWithTotal(
        totalUpload: 0,
        totalDownload: 0,
      ),
    );
    _lastTimestamp = now;

    Logger.info('累计流量已重置');
    unawaited(_persistTrafficState());
    notifyListeners();
  }

  void _initializePersistedState() {
    final prefs = AppPreferences.instance;

    _state = TrafficState.initial().copyWith(
      totalUpload: prefs.getInt(_kTrafficTotalUpload) ?? 0,
      totalDownload: prefs.getInt(_kTrafficTotalDownload) ?? 0,
      lastTrafficData: TrafficData.zero.copyWithTotal(
        totalUpload: prefs.getInt(_kTrafficTotalUpload) ?? 0,
        totalDownload: prefs.getInt(_kTrafficTotalDownload) ?? 0,
      ),
    );
  }

  void _schedulePersist() {
    if (_persistTimer?.isActive ?? false) {
      return;
    }
    _persistTimer = Timer(const Duration(seconds: 10), () {
      unawaited(_persistTrafficState());
    });
  }

  Future<void> _persistTrafficState() async {
    final prefs = AppPreferences.instance;

    await prefs.setInt(_kTrafficTotalUpload, _state.totalUpload);
    await prefs.setInt(_kTrafficTotalDownload, _state.totalDownload);
  }

  @override
  void dispose() {
    _trafficSubscription?.cancel();
    _retryTimer?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}
