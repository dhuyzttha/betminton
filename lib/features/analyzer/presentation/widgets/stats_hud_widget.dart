import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/rally_stats.dart';
import '../../domain/models/shuttlecock_model.dart';

class StatsHudWidget extends StatelessWidget {
  final RallyStats stats;
  final ShuttlecockModel shuttlecock;

  const StatsHudWidget({
    super.key,
    required this.stats,
    required this.shuttlecock,
  });

  String _formatTime(double totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final double remainingSeconds = (totalSeconds - (minutes * 60)).clamp(0.0, 59.9);
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = stats.state == RallyState.inPlay;
    final String rallyTimeStr = _formatTime(stats.durationSeconds);
    final String activeTimeStr = _formatTime(
      stats.activePlaySeconds > 0 ? stats.activePlaySeconds : stats.durationSeconds,
    );

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: HawkEyeTheme.panelBg,
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // 1. THỜI GIAN PHA CẦU (Sky Blue #7DD3FC matching reference video)
          Expanded(
            child: _buildColumn(
              title: 'THỜI GIAN PHA CẦU',
              value: rallyTimeStr,
              valueColor: HawkEyeTheme.hudTimeBlue,
            ),
          ),
          _buildDivider(),

          // 2. PHA SỐ
          Expanded(
            child: _buildColumn(
              title: 'PHA SỐ',
              value: '${stats.rallyNumber}',
              valueColor: Colors.white,
            ),
          ),
          _buildDivider(),

          // 3. LƯỢT CẦU ĐỔI HƯỚNG (Yellow #FACC15)
          Expanded(
            child: _buildColumn(
              title: 'LƯỢT CẦU ĐỔI HƯỚNG',
              value: '${stats.shotCount}',
              valueColor: HawkEyeTheme.hudYellowNumber,
            ),
          ),
          _buildDivider(),

          // 4. THỜI GIAN CHƠI THỰC
          Expanded(
            child: _buildColumn(
              title: 'THỜI GIAN CHƠI THỰC',
              value: activeTimeStr,
              valueColor: Colors.white,
            ),
          ),
          _buildDivider(),

          // 5. TRẠNG THÁI
          Expanded(
            child: _buildColumn(
              title: 'TRẠNG THÁI',
              value: isActive ? 'ĐANG ĐÁNH' : 'NGHỈ',
              valueColor: isActive ? HawkEyeTheme.hudActiveGreen : HawkEyeTheme.statePaused,
              isStatus: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn({
    required String title,
    required String value,
    required Color valueColor,
    bool isStatus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: HawkEyeTheme.textSecondary,
                fontSize: 8.0,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: valueColor,
                fontSize: isStatus ? 11.5 : 13.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1.0,
      height: 28,
      color: const Color(0xFF1E293B),
    );
  }
}
