import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/player_model.dart';

/// Renders the exact 4-Player Bottom Telemetry Bar (Tú, Cường, Nam, Thành)
/// placed directly underneath the Left Video Viewport in the Broadcast Split-Screen layout.
class ControlPanelWidget extends StatelessWidget {
  final List<PlayerModel> players;

  const ControlPanelWidget({
    super.key,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      decoration: const BoxDecoration(
        color: HawkEyeTheme.bottomCardBg,
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1.0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: players.map((p) => Expanded(child: _buildPlayerCard(p))).toList(),
      ),
    );
  }

  Widget _buildPlayerCard(PlayerModel p) {
    final String totalDistStr =
        '${p.totalDistanceMeters.toStringAsFixed(1).replaceAll('.', ',')} m';
    final String rallyDistStr =
        '${p.rallyDistanceMeters.toStringAsFixed(1).replaceAll('.', ',')} m pha này';
    final double progress = (p.rallyDistanceMeters / 12.0).clamp(0.08, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Vertical Colored Pill Accent Bar
          Container(
            width: 3.5,
            decoration: BoxDecoration(
              color: p.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Player Name (in player's color) & Team Name below
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        p.name,
                        maxLines: 1,
                        style: TextStyle(
                          color: p.color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        p.team,
                        maxLines: 1,
                        style: const TextStyle(
                          color: HawkEyeTheme.textSecondary,
                          fontSize: 8.0,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),

                // 2. Large Total Distance ("5,0 m")
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    totalDistStr,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                ),

                // 3. "cả trận" (left) & "X,X m pha này" (right) + Rounded Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'cả trận',
                              style: TextStyle(
                                color: HawkEyeTheme.textSecondary,
                                fontSize: 7.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              rallyDistStr,
                              style: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 7.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 4.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFF263345),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
