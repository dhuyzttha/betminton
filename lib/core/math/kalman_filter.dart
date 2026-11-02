import 'dart:ui';

/// 4-Dimensional Kalman Filter for Shuttlecock Motion Tracking on Mobile.
/// State: [x, y, vx, vy]^T
/// Handles sensor dropouts, fast accelerations, and motion blur interpolation.
class ShuttlecockKalmanFilter {
  final double dt;

  // State vector
  double _x = 0.0;
  double _y = 0.0;
  double _vx = 0.0;
  double _vy = 0.0;

  // Covariance matrix P (4x4)
  final List<List<double>> _p = [
    [10.0, 0.0, 0.0, 0.0],
    [0.0, 10.0, 0.0, 0.0],
    [0.0, 0.0, 10.0, 0.0],
    [0.0, 0.0, 0.0, 10.0],
  ];

  final double qPos;
  final double qVel;
  final double rMeas;

  bool _initialized = false;
  int _consecutiveDroppedFrames = 0;

  ShuttlecockKalmanFilter({
    this.dt = 1.0 / 30.0,
    this.qPos = 0.05,
    this.qVel = 0.5,
    this.rMeas = 2.0,
  });

  bool get isInitialized => _initialized;
  int get droppedFrames => _consecutiveDroppedFrames;

  void reset() {
    _initialized = false;
    _consecutiveDroppedFrames = 0;
    _x = 0;
    _y = 0;
    _vx = 0;
    _vy = 0;
  }

  void initialize(Offset point) {
    _x = point.dx;
    _y = point.dy;
    _vx = 0.0;
    _vy = 0.0;
    _initialized = true;
    _consecutiveDroppedFrames = 0;
  }

  /// Predict step: State propagation through constant velocity model
  Offset predict() {
    if (!_initialized) return Offset.zero;

    _x += _vx * dt;
    _y += _vy * dt;

    // Gravity / air resistance damping on badminton shuttlecock
    _vx *= 0.98;
    _vy += 9.8 * dt * 2.0;

    // Covariance update: P = F * P * F^T + Q
    _p[0][0] += _p[2][2] * dt * dt + qPos;
    _p[1][1] += _p[3][3] * dt * dt + qPos;
    _p[2][2] += qVel;
    _p[3][3] += qVel;

    return Offset(_x, _y);
  }

  /// Correct step: Updates state with sensor measurement
  Offset update(Offset measurement) {
    if (!_initialized) {
      initialize(measurement);
      return measurement;
    }

    _consecutiveDroppedFrames = 0;

    final double resX = measurement.dx - _x;
    final double resY = measurement.dy - _y;

    final double sX = _p[0][0] + rMeas;
    final double sY = _p[1][1] + rMeas;

    final double kX0 = _p[0][0] / sX;
    final double kX2 = _p[2][0] / sX;
    final double kY1 = _p[1][1] / sY;
    final double kY3 = _p[3][1] / sY;

    _x += kX0 * resX;
    _vx += kX2 * resX;
    _y += kY1 * resY;
    _vy += kY3 * resY;

    _p[0][0] *= (1.0 - kX0);
    _p[1][1] *= (1.0 - kY1);
    _p[2][2] *= (1.0 - kX2);
    _p[3][3] *= (1.0 - kY3);

    return Offset(_x, _y);
  }

  Offset forwardExtrapolate() {
    _consecutiveDroppedFrames++;
    return predict();
  }

  Offset get currentPosition => Offset(_x, _y);
  Offset get currentVelocity => Offset(_vx, _vy);
  double get speedMagnitude => Offset(_vx, _vy).distance;
}
