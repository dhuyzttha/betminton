import 'dart:ui';

class TrajectoryPoint {
  final int frame;
  final Offset px;
  final Offset bwf;
  final double speedKmh;
  final bool interpolated;

  TrajectoryPoint({
    required this.frame,
    required this.px,
    required this.bwf,
    required this.speedKmh,
    this.interpolated = false,
  });
}

class ShuttlecockModel {
  final Offset? currentPx;
  final Offset? currentBwf;
  final double currentSpeedKmh;
  final double maxSpeedKmh;
  final List<TrajectoryPoint> trajectory;
  final bool isTracking;

  ShuttlecockModel({
    this.currentPx,
    this.currentBwf,
    this.currentSpeedKmh = 0.0,
    this.maxSpeedKmh = 0.0,
    this.trajectory = const [],
    this.isTracking = false,
  });

  ShuttlecockModel copyWith({
    Offset? currentPx,
    Offset? currentBwf,
    double? currentSpeedKmh,
    double? maxSpeedKmh,
    List<TrajectoryPoint>? trajectory,
    bool? isTracking,
  }) {
    return ShuttlecockModel(
      currentPx: currentPx ?? this.currentPx,
      currentBwf: currentBwf ?? this.currentBwf,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      trajectory: trajectory ?? this.trajectory,
      isTracking: isTracking ?? this.isTracking,
    );
  }
}
