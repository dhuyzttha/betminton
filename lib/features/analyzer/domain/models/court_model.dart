import 'dart:ui';
import '../../../../core/constants/bwf_dimensions.dart';
import '../../../../core/math/homography_matrix.dart';

enum CourtMode { singles, doubles }

class CourtModel {
  final CourtMode mode;
  final List<Offset> corners; // [Top-Left, Top-Right, Bottom-Right, Bottom-Left]
  final HomographyMatrix? homography;
  final HomographyMatrix? inverseHomography;

  CourtModel({
    required this.mode,
    required this.corners,
    this.homography,
    this.inverseHomography,
  });

  double get width =>
      mode == CourtMode.singles ? BwfDimensions.widthSingles : BwfDimensions.widthDoubles;
  double get length => BwfDimensions.length;

  factory CourtModel.initial(CourtMode mode, {Size videoSize = const Size(978, 576)}) {
    final double w = videoSize.width > 0 ? videoSize.width : 978.0;
    final double h = videoSize.height > 0 ? videoSize.height : 576.0;

    final initialCorners = [
      Offset(w * 0.22, h * 0.42), // Top-Left (Far-Left)
      Offset(w * 0.78, h * 0.42), // Top-Right (Far-Right)
      Offset(w * 0.90, h * 0.78), // Bottom-Right (Near-Right)
      Offset(w * 0.10, h * 0.78), // Bottom-Left (Near-Left)
    ];

    return CourtModel(
      mode: mode,
      corners: initialCorners,
    ).copyWithCorners(initialCorners);
  }

  CourtModel copyWithCorners(List<Offset> newCorners, {CourtMode? newMode}) {
    final activeMode = newMode ?? mode;
    final activeWidth = activeMode == CourtMode.singles
        ? BwfDimensions.widthSingles
        : BwfDimensions.widthDoubles;

    final List<Offset> worldPoints = [
      const Offset(0.0, 0.0),
      Offset(activeWidth, 0.0),
      Offset(activeWidth, length),
      Offset(0.0, length),
    ];

    final HomographyMatrix? h = HomographyMatrix.compute(newCorners, worldPoints);
    final HomographyMatrix? hInv = h?.inverse();

    return CourtModel(
      mode: activeMode,
      corners: newCorners,
      homography: h,
      inverseHomography: hInv,
    );
  }
}
