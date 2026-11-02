import 'dart:ui';

enum RallyState { serve, inPlay, pointAwarded, paused }

class RallyStats {
  final RallyState state;
  final int rallyNumber;
  final int shotCount;
  final double durationSeconds;
  final double activePlaySeconds;
  final String refereeDecision; // "IN", "OUT", "FAULT", "PLAY ON"
  final Offset? landingSpotBwf;
  final Offset? landingSpotPx;

  RallyStats({
    this.state = RallyState.inPlay,
    this.rallyNumber = 1,
    this.shotCount = 1,
    this.durationSeconds = 0.0,
    this.activePlaySeconds = 0.0,
    this.refereeDecision = "PLAY ON",
    this.landingSpotBwf,
    this.landingSpotPx,
  });

  RallyStats copyWith({
    RallyState? state,
    int? rallyNumber,
    int? shotCount,
    double? durationSeconds,
    double? activePlaySeconds,
    String? refereeDecision,
    Offset? landingSpotBwf,
    Offset? landingSpotPx,
  }) {
    return RallyStats(
      state: state ?? this.state,
      rallyNumber: rallyNumber ?? this.rallyNumber,
      shotCount: shotCount ?? this.shotCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      activePlaySeconds: activePlaySeconds ?? this.activePlaySeconds,
      refereeDecision: refereeDecision ?? this.refereeDecision,
      landingSpotBwf: landingSpotBwf ?? this.landingSpotBwf,
      landingSpotPx: landingSpotPx ?? this.landingSpotPx,
    );
  }
}
