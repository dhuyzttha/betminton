import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/court_model.dart';
import '../../domain/models/player_model.dart';
import '../../domain/models/shuttlecock_model.dart';
import '../../domain/models/rally_stats.dart';

class HawkEyePainter extends CustomPainter {
  final CourtModel court;
  final List<PlayerModel> players;
  final ShuttlecockModel shuttlecock;
  final RallyStats rallyStats;
  final Size originalVideoSize;
  final bool drawCourtGrid;
  final bool showShuttleSpeed;

  HawkEyePainter({
    required this.court,
    required this.players,
    required this.shuttlecock,
    required this.rallyStats,
    required this.originalVideoSize,
    this.drawCourtGrid = false,
    this.showShuttleSpeed = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalVideoSize.width <= 0 || originalVideoSize.height <= 0) return;

    // Preserve native video aspect ratio inside the viewport using BoxFit.contain
    final FittedSizes fitted = applyBoxFit(BoxFit.contain, originalVideoSize, size);
    if (fitted.destination.width <= 0 || fitted.destination.height <= 0) return;

    final Rect dstRect = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final double scaleX = dstRect.width / originalVideoSize.width;
    final double scaleY = dstRect.height / originalVideoSize.height;

    canvas.save();
    canvas.clipRect(dstRect);
    canvas.translate(dstRect.left, dstRect.top);
    canvas.scale(scaleX, scaleY);

    if (drawCourtGrid && court.corners.length == 4) {
      final Path courtPath = Path()
        ..moveTo(court.corners[0].dx, court.corners[0].dy)
        ..lineTo(court.corners[1].dx, court.corners[1].dy)
        ..lineTo(court.corners[2].dx, court.corners[2].dy)
        ..lineTo(court.corners[3].dx, court.corners[3].dy)
        ..close();

      canvas.drawPath(
        courtPath,
        Paint()
          ..color = const Color(0x55164846)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        courtPath,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final Offset netLeft = Offset.lerp(court.corners[0], court.corners[3], 0.5)!;
      final Offset netRight = Offset.lerp(court.corners[1], court.corners[2], 0.5)!;
      canvas.drawLine(
        netLeft,
        netRight,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..strokeWidth = 1.8,
      );
    }

    final List<Rect> placedBadges = [];

    // 1. Draw Players: Double Ground Ring + Center Dot & Rounded Name Badge
    for (final player in players) {
      if (player.bbox != null && player.footPx != null) {
        final Color pColor = player.color;
        final Offset footPos = player.footPx!;
        final double ringW = (player.bbox!.width * 0.85).clamp(34.0, 68.0);
        final double ringH = (ringW * 0.28).clamp(9.0, 20.0);

        // Outer translucent ring
        canvas.drawOval(
          Rect.fromCenter(center: footPos, width: ringW + 8, height: ringH + 4),
          Paint()
            ..color = pColor.withAlpha(110)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );

        // Inner crisp ring + center foot dot
        canvas.drawOval(
          Rect.fromCenter(center: footPos, width: ringW, height: ringH),
          Paint()
            ..color = pColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(footPos, 3.0, Paint()..color = pColor);

        // Floating Rounded Name Badge above head
        final textSpan = TextSpan(
          text: player.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();

        final double badgeW = textPainter.width + 18.0;
        const double badgeH = 24.0;
        final double badgeX = (player.bbox!.center.dx - badgeW / 2.0)
            .clamp(8.0, originalVideoSize.width - badgeW - 8.0);
        double badgeY = (player.bbox!.top - badgeH - 5.0)
            .clamp(8.0, originalVideoSize.height - badgeH - 8.0);

        Rect candidateRect = Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH);
        for (final existing in placedBadges) {
          if (candidateRect.overlaps(existing.inflate(3.0))) {
            badgeY = (existing.top - badgeH - 4.0).clamp(8.0, originalVideoSize.height - 40.0);
            candidateRect = Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH);
          }
        }
        placedBadges.add(candidateRect);

        final RRect badgeRRect = RRect.fromRectAndRadius(
          candidateRect,
          const Radius.circular(4.5),
        );

        canvas.drawRRect(badgeRRect, Paint()..color = const Color(0xD810161E));
        canvas.drawRRect(
          badgeRRect,
          Paint()
            ..color = pColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        textPainter.paint(
          canvas,
          Offset(
            badgeX + (badgeW - textPainter.width) / 2.0,
            badgeY + (badgeH - textPainter.height) / 2.0,
          ),
        );
      }
    }

    // 2. Draw Smooth Parabolic Shuttlecock Arc
    if (showShuttleSpeed && shuttlecock.trajectory.length > 1) {
      final Path ribbonPath = Path();
      ribbonPath.moveTo(shuttlecock.trajectory[0].px.dx, shuttlecock.trajectory[0].px.dy);
      for (int i = 1; i < shuttlecock.trajectory.length; i++) {
        final prev = shuttlecock.trajectory[i - 1].px;
        final curr = shuttlecock.trajectory[i].px;
        final mid = Offset((prev.dx + curr.dx) / 2.0, (prev.dy + curr.dy) / 2.0);
        ribbonPath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      }
      final last = shuttlecock.trajectory.last.px;
      ribbonPath.lineTo(last.dx, last.dy);

      canvas.drawPath(
        ribbonPath,
        Paint()
          ..color = HawkEyeTheme.shuttleYellow
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // 3. Draw Shuttlecock Head Marker
    if (shuttlecock.currentPx != null) {
      final Offset sPos = shuttlecock.currentPx!;
      canvas.drawCircle(sPos, 5.2, Paint()..color = const Color(0xDD111827));
      canvas.drawCircle(sPos, 4.0, Paint()..color = HawkEyeTheme.shuttleYellow);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HawkEyePainter oldDelegate) => true;
}
