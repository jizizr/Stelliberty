import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/manager/manager.dart';
import 'package:stelliberty/clash/data/traffic_data_model.dart';
import 'package:stelliberty/ui/widgets/home/base_card.dart';
import 'package:stelliberty/ui/common/empty.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 流量统计卡片
//
// 显示累计上传/下载流量和实时速度波形图
class TrafficStatsCard extends StatefulWidget {
  const TrafficStatsCard({super.key});

  @override
  State<TrafficStatsCard> createState() => _TrafficStatsCardState();
}

class _TrafficStatsCardState extends State<TrafficStatsCard> {
  // 存储最近的速度历史数据（上传/下载）
  final List<double> _uploadHistory = List.generate(30, (_) => 0.0);
  final List<double> _downloadHistory = List.generate(30, (_) => 0.0);

  // 累计流量统计（字节）
  int _totalUpload = 0;
  int _totalDownload = 0;

  // 降采样计数器：减少波形图重绘频率
  int _updateCounter = 0;
  static const _updateInterval = 3; // 每 3 次数据只更新 1 次波形

  @override
  Widget build(BuildContext context) {
    // 使用 select 精确监听 isRunning 状态，避免不必要的重建
    final isRunning = context.select<ClashManager, bool>(
      (manager) => manager.isRunning,
    );

    return BaseCard(
      icon: Icons.data_usage,
      title: context.translate.home.trafficStats,
      trailing: _buildTotalTrafficDisplay(context),
      child: isRunning
          ? StreamBuilder<TrafficData>(
              stream: context.read<ClashManager>().trafficStream,
              initialData: TrafficData.zero,
              builder: (context, snapshot) {
                final traffic = snapshot.data ?? TrafficData.zero;

                // 降采样：只处理部分数据更新波形
                _updateCounter++;
                final shouldUpdateWave = _updateCounter >= _updateInterval;
                if (shouldUpdateWave) {
                  _updateCounter = 0;
                  _updateHistory(traffic);
                  // 累加流量统计
                  _totalUpload += traffic.upload;
                  _totalDownload += traffic.download;
                }

                return _buildTrafficContent(
                  context,
                  traffic,
                  isRunning,
                  shouldUpdateWave: shouldUpdateWave,
                );
              },
            )
          : _buildTrafficContent(context, TrafficData.zero, isRunning),
    );
  }

  // 构建右上角累计流量显示
  Widget _buildTotalTrafficDisplay(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.arrow_upward,
          size: 12,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 2),
        Text(
          _formatBytes(_totalUpload),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 11,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.arrow_downward,
          size: 12,
          color: Colors.green.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 2),
        Text(
          _formatBytes(_totalDownload),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 11,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  void _updateHistory(TrafficData traffic) {
    // 更新速度历史，移除最旧的数据，添加最新的
    _uploadHistory.removeAt(0);
    _uploadHistory.add(traffic.upload / 1024.0); // KB/s

    _downloadHistory.removeAt(0);
    _downloadHistory.add(traffic.download / 1024.0); // KB/s
  }

  // 格式化字节数显示（自动选择 B、KB、MB、GB）
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb < 100 ? 1 : 0)}MB';
    } else {
      final gb = bytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)}GB';
    }
  }

  // 格式化速度显示（自动选择 B/s、KB/s、MB/s、GB/s）
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      // < 1 KB/s，显示 B/s
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      // < 1 MB/s，显示 KB/s
      final kb = bytesPerSecond / 1024;
      return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)} KB/s';
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      // < 1 GB/s，显示 MB/s
      final mb = bytesPerSecond / (1024 * 1024);
      return '${mb.toStringAsFixed(mb < 100 ? 1 : 0)} MB/s';
    } else {
      // >= 1 GB/s，显示 GB/s
      final gb = bytesPerSecond / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB/s';
    }
  }

  Widget _buildTrafficContent(
    BuildContext context,
    TrafficData traffic,
    bool isRunning, {
    bool shouldUpdateWave = true,
  }) {
    return Column(
      children: [
        // 波形图 - 使用 RepaintBoundary 隔离重绘区域
        RepaintBoundary(
          child: SizedBox(
            width: double.infinity,
            height: 120,
            child: shouldUpdateWave
                ? CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _TrafficWavePainter(
                      uploadHistory: _uploadHistory,
                      downloadHistory: _downloadHistory,
                      uploadColor: Theme.of(context).colorScheme.primary,
                      downloadColor: Colors.green,
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _TrafficWavePainter(
                      uploadHistory: _uploadHistory,
                      downloadHistory: _downloadHistory,
                      uploadColor: Theme.of(context).colorScheme.primary,
                      downloadColor: Colors.green,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 16),

        // 速度统计和重置按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左侧：重置按钮
            if (isRunning)
              _ResetButton(onPressed: () => _resetTraffic(context))
            else
              empty,

            // 右侧：上传下载速度 - 使用 Flexible 避免溢出
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 上传速度
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.upload,
                          size: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _formatSpeed(traffic.upload.toDouble()),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 下载速度
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download,
                          size: 16,
                          color: Colors.green.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _formatSpeed(traffic.download.toDouble()),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 重置流量统计（无需确认对话框）
  void _resetTraffic(BuildContext context) {
    final clashManager = context.read<ClashManager>();
    clashManager.resetTrafficStats();
    // 清空历史数据和累计统计
    setState(() {
      _uploadHistory.fillRange(0, _uploadHistory.length, 0);
      _downloadHistory.fillRange(0, _downloadHistory.length, 0);
      _totalUpload = 0;
      _totalDownload = 0;
    });
  }
}

/// 重置按钮组件
class _ResetButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _ResetButton({required this.onPressed});

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restart_alt,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                context.translate.home.reset,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 流量波形图绘制器
class _TrafficWavePainter extends CustomPainter {
  final List<double> uploadHistory;
  final List<double> downloadHistory;
  final Color uploadColor;
  final Color downloadColor;

  _TrafficWavePainter({
    required this.uploadHistory,
    required this.downloadHistory,
    required this.uploadColor,
    required this.downloadColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 找到最大值用于归一化
    final allValues = [...uploadHistory, ...downloadHistory];
    final maxValue = allValues.reduce((a, b) => a > b ? a : b);
    final normalizedMax = maxValue > 0 ? maxValue : 1.0;

    // 绘制下载曲线（绿色，在下层）
    _drawWave(canvas, size, downloadHistory, downloadColor, normalizedMax);

    // 绘制上传曲线（主题色，在上层）
    _drawWave(canvas, size, uploadHistory, uploadColor, normalizedMax);
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    List<double> history,
    Color color,
    double maxValue,
  ) {
    if (history.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (history.length - 1);

    // 起始点
    final firstY = size.height - (history[0] / maxValue * size.height * 0.8);
    path.moveTo(0, firstY);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, firstY);

    // 绘制曲线
    for (int i = 1; i < history.length; i++) {
      final x = i * stepX;
      final y = size.height - (history[i] / maxValue * size.height * 0.8);

      // 使用二次贝塞尔曲线使波形更平滑
      final prevX = (i - 1) * stepX;
      final prevY =
          size.height - (history[i - 1] / maxValue * size.height * 0.8);
      final controlX = (prevX + x) / 2;

      path.quadraticBezierTo(controlX, prevY, x, y);
      fillPath.quadraticBezierTo(controlX, prevY, x, y);
    }

    // 填充区域
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // 绘制线条
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrafficWavePainter oldDelegate) {
    return uploadHistory != oldDelegate.uploadHistory ||
        downloadHistory != oldDelegate.downloadHistory;
  }
}
