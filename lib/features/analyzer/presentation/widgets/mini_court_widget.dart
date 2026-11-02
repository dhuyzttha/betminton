import 'package:flutter/material.dart';
import '../../../../core/constants/bwf_dimensions.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/court_model.dart';
import '../../domain/models/player_model.dart';
import '../../domain/models/shuttlecock_model.dart';

class MiniCourtWidget extends StatelessWidget {
  final CourtModel court;
  final List<PlayerModel> players;
  final ShuttlecockModel shuttlecock;
  final double? width;
  final double? height;

  const MiniCourtWidget({
    super.key,
    required this.court,
    required this.players,
    required this.shuttlecock,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: HawkEyeTheme.courtMapBg,
        border: Border(
          left: BorderSide(color: Color(0xFF1E293B), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'COURT MAP',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 1),
          const Center(
            child: Text(
              'Đội mình',
              style: TextStyle(
                color: Color(0xFFD7DEE8),
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: CustomPaint(
              painter: _MiniCourtPainter(
                court: court,
                players: players,
                shuttlecock: shuttlecock,
              ),
            ),
          ),
          const SizedBox(height: 3),
          const Center(
            child: Text(
              'Đội bạn',
              style: TextStyle(
                color: Color(0xFFD7DEE8),
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCourtPainter extends CustomPainter {
  final CourtModel court;
  final List<PlayerModel> players;
  final ShuttlecockModel shuttlecock;

  _MiniCourtPainter({
    required this.court,
    required this.players,
    required this.shuttlecock,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Rect courtRect = Offset.zero & size;
    canvas.drawRect(courtRect, Paint()..color = HawkEyeTheme.courtFloor);

    final Paint linePaint = Paint()
      ..color = const Color(0xD9E2E8F0)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    canvas.drawRect(courtRect, linePaint);

    const double courtW = BwfDimensions.widthDoubles;
    const double courtL = BwfDimensions.length;
    final double scaleX = size.width / courtW;
    final double scaleY = size.height / courtL;

    // Doubles tramlines (0.46m)
    final double tramlineX = BwfDimensions.tramlineWidth * scaleX;
    canvas.drawLine(Offset(tramlineX, 0), Offset(tramlineX, size.height), linePaint);
    canvas.drawLine(
      Offset(size.width - tramlineX, 0),
      Offset(size.width - tramlineX, size.height),
      linePaint,
    );

    // Rear doubles service lines (0.76m)
    final double rearServiceY = BwfDimensions.doublesRearServiceDistance * scaleY;
    canvas.drawLine(Offset(0, rearServiceY), Offset(size.width, rearServiceY), linePaint);
    canvas.drawLine(
      Offset(0, size.height - rearServiceY),
      Offset(size.width, size.height - rearServiceY),
      linePaint,
    );

    // Short service lines (1.98m from net)
    final double sslTop = (BwfDimensions.netPosition - BwfDimensions.shortServiceDistance) * scaleY;
    final double sslBottom = (BwfDimensions.netPosition + BwfDimensions.shortServiceDistance) * scaleY;
    canvas.drawLine(Offset(0, sslTop), Offset(size.width, sslTop), linePaint);
    canvas.drawLine(Offset(0, sslBottom), Offset(size.width, sslBottom), linePaint);

    // Center dividing lines
    final double midX = size.width / 2.0;
    canvas.drawLine(Offset(midX, 0), Offset(midX, sslTop), linePaint);
    canvas.drawLine(Offset(midX, sslBottom), Offset(midX, size.height), linePaint);

    // Thick white net line
    final double netY = size.height / 2.0;
    canvas.drawLine(
      Offset(0, netY),
      Offset(size.width, netY),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.8,
    );

    Offset toMap(Offset bwf) {
      return Offset(
        (bwf.dx * scaleX).clamp(3.0, size.width - 3.0),
        (bwf.dy * scaleY).clamp(3.0, size.height - 3.0),
      );
    }

    // Cumulative rally shot trajectory lines & bounce dots on Court Map
    final List<Offset> shotNodes = [
      const Offset(3.45, 7.60),
      const Offset(3.95, 10.60),
      const Offset(4.35, 1.30),
      const Offset(3.55, 10.20),
      const Offset(3.85, 2.10),
      if (shuttlecock.currentBwf != null) shuttlecock.currentBwf!,
    ];

    final Paint shotLinePaint = Paint()
      ..color = const Color(0xCCEAB308)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (int i = 1; i < shotNodes.length; i++) {
      canvas.drawLine(toMap(shotNodes[i - 1]), toMap(shotNodes[i]), shotLinePaint);
    }
    for (int i = 0; i < shotNodes.length - 1; i++) {
      final pt = toMap(shotNodes[i]);
      final dotColor = shotNodes[i].dy > 6.7 ? HawkEyeTheme.playerCuong : HawkEyeTheme.playerThanh;
      canvas.drawCircle(pt, 2.5, Paint()..color = dotColor);
    }

    // Draw Player Movement Trails & White-Bordered Circles
    for (final p in players) {
      if (p.footBwf != null) {
        if (p.historyBwf.length > 1) {
          final Path trailPath = Path();
          final start = toMap(p.historyBwf[0]);
          trailPath.moveTo(start.dx, start.dy);
          for (int i = 1; i < p.historyBwf.length; i++) {
            final pt = toMap(p.historyBwf[i]);
            trailPath.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(
            trailPath,
            Paint()
              ..color = p.color.withAlpha(200)
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke,
          );
        }

        final Offset cur = toMap(p.footBwf!);
        canvas.drawCircle(cur, 5.2, Paint()..color = Colors.white);
        canvas.drawCircle(cur, 4.0, Paint()..color = p.color);
      }
    }

    // Current Shuttlecock Position on Map
    if (shuttlecock.currentBwf != null) {
      final Offset sMap = toMap(shuttlecock.currentBwf!);
      canvas.drawCircle(sMap, 4.0, Paint()..color = Colors.black87);
      canvas.drawCircle(sMap, 3.0, Paint()..color = HawkEyeTheme.shuttleYellow);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniCourtPainter oldDelegate) => true;
}
