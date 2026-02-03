import 'package:stelliberty/clash/model/traffic_data_model.dart';

// 流量统计状态
class TrafficState {
  final int totalUpload; // 累计上传字节数
  final int totalDownload; // 累计下载字节数
  final DateTime? lastTimestamp;
  final TrafficData? lastTrafficData;
  final List<double> uploadHistory; // 上传速率历史（KB/s）
  final List<double> downloadHistory; // 下载速率历史（KB/s）

  const TrafficState({
    required this.totalUpload,
    required this.totalDownload,
    this.lastTimestamp,
    this.lastTrafficData,
    required this.uploadHistory,
    required this.downloadHistory,
  });

  factory TrafficState.initial() {
    return TrafficState(
      totalUpload: 0,
      totalDownload: 0,
      uploadHistory: List.generate(30, (_) => 0.0),
      downloadHistory: List.generate(30, (_) => 0.0),
    );
  }

  TrafficState copyWith({
    int? totalUpload,
    int? totalDownload,
    DateTime? lastTimestamp,
    TrafficData? lastTrafficData,
    List<double>? uploadHistory,
    List<double>? downloadHistory,
  }) {
    return TrafficState(
      totalUpload: totalUpload ?? this.totalUpload,
      totalDownload: totalDownload ?? this.totalDownload,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      lastTrafficData: lastTrafficData ?? this.lastTrafficData,
      uploadHistory: uploadHistory ?? this.uploadHistory,
      downloadHistory: downloadHistory ?? this.downloadHistory,
    );
  }
}
