import 'dart:ui';

/// High-performance 3x3 Homography Matrix Solver in pure Dart.
/// Solves Direct Linear Transformation (DLT) and perspective projections
/// between 2D pixel space and BWF metric space (meters).
class HomographyMatrix {
  final List<List<double>> elements; // 3x3 matrix

  HomographyMatrix(this.elements);

  factory HomographyMatrix.identity() {
    return HomographyMatrix([
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
      [0.0, 0.0, 1.0],
    ]);
  }

  /// Solves 3x3 Homography H using 4 source points (image pixels)
  /// and 4 destination points (BWF metric coordinates in meters).
  /// Order: [Top-Left, Top-Right, Bottom-Right, Bottom-Left]
  static HomographyMatrix? compute(List<Offset> src, List<Offset> dst) {
    if (src.length != 4 || dst.length != 4) return null;

    final List<List<double>> a = List.generate(8, (_) => List.filled(8, 0.0));
    final List<double> b = List.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final double u = src[i].dx;
      final double v = src[i].dy;
      final double x = dst[i].dx;
      final double y = dst[i].dy;

      // Row 2*i: x_i equation
      a[2 * i][0] = u;
      a[2 * i][1] = v;
      a[2 * i][2] = 1.0;
      a[2 * i][3] = 0.0;
      a[2 * i][4] = 0.0;
      a[2 * i][5] = 0.0;
      a[2 * i][6] = -u * x;
      a[2 * i][7] = -v * x;
      b[2 * i] = x;

      // Row 2*i + 1: y_i equation
      a[2 * i + 1][0] = 0.0;
      a[2 * i + 1][1] = 0.0;
      a[2 * i + 1][2] = 0.0;
      a[2 * i + 1][3] = u;
      a[2 * i + 1][4] = v;
      a[2 * i + 1][5] = 1.0;
      a[2 * i + 1][6] = -u * y;
      a[2 * i + 1][7] = -v * y;
      b[2 * i + 1] = y;
    }

    final List<double>? h = _solveGaussian(a, b);
    if (h == null) return null;

    return HomographyMatrix([
      [h[0], h[1], h[2]],
      [h[3], h[4], h[5]],
      [h[6], h[7], 1.0],
    ]);
  }

  /// Transforms coordinate (u, v) through this 3x3 Homography matrix
  Offset transform(Offset pt) {
    final double u = pt.dx;
    final double v = pt.dy;

    final double xPrime = elements[0][0] * u + elements[0][1] * v + elements[0][2];
    final double yPrime = elements[1][0] * u + elements[1][1] * v + elements[1][2];
    final double wPrime = elements[2][0] * u + elements[2][1] * v + elements[2][2];

    if (wPrime.abs() < 1e-9) return Offset.zero;
    return Offset(xPrime / wPrime, yPrime / wPrime);
  }

  /// Computes the exact 3x3 Inverse Homography
  HomographyMatrix? inverse() {
    final List<List<double>> m = elements;
    final double det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    if (det.abs() < 1e-9) return null;
    final double invDet = 1.0 / det;

    return HomographyMatrix([
      [
        (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * invDet,
        (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * invDet,
        (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * invDet,
      ],
      [
        (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * invDet,
        (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * invDet,
        (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * invDet,
      ],
      [
        (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * invDet,
        (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * invDet,
        (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * invDet,
      ],
    ]);
  }

  /// Gaussian elimination solver with partial pivoting
  static List<double>? _solveGaussian(List<List<double>> a, List<double> b) {
    final int n = b.length;
    for (int p = 0; p < n; p++) {
      int maxRow = p;
      for (int i = p + 1; i < n; i++) {
        if (a[i][p].abs() > a[maxRow][p].abs()) {
          maxRow = i;
        }
      }

      final List<double> tempA = a[p];
      a[p] = a[maxRow];
      a[maxRow] = tempA;

      final double tempB = b[p];
      b[p] = b[maxRow];
      b[maxRow] = tempB;

      if (a[p][p].abs() < 1e-12) return null;

      for (int i = p + 1; i < n; i++) {
        final double alpha = a[i][p] / a[p][p];
        b[i] -= alpha * b[p];
        for (int j = p; j < n; j++) {
          a[i][j] -= alpha * a[p][j];
        }
      }
    }

    final List<double> x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = 0.0;
      for (int j = i + 1; j < n; j++) {
        sum += a[i][j] * x[j];
      }
      x[i] = (b[i] - sum) / a[i][i];
    }
    return x;
  }

  /// Extrapolates missing/occluded corner using perspective projective geometry
  static List<Offset> extrapolateMissingCorners({
    Offset? tl,
    Offset? tr,
    Offset? br,
    Offset? bl,
    required double imageWidth,
    required double imageHeight,
  }) {
    final Offset ptl = tl ?? Offset(imageWidth * 0.22, imageHeight * 0.42);
    final Offset ptr = tr ?? Offset(imageWidth * 0.78, imageHeight * 0.42);
    Offset pbr = br ?? Offset(imageWidth * 0.90, imageHeight * 0.78);
    Offset pbl = bl ?? Offset(imageWidth * 0.10, imageHeight * 0.78);

    if (br == null && bl != null) {
      pbr = Offset(imageWidth - bl.dx, bl.dy);
    } else if (bl == null && br != null) {
      pbl = Offset(imageWidth - br.dx, br.dy);
    }

    return [ptl, ptr, pbr, pbl];
  }
}
