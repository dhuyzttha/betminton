/// Standard BWF (Badminton World Federation) Court Specifications
/// All linear measurements are in metric meters.
class BwfDimensions {
  static const double length = 13.40;
  static const double widthSingles = 5.18;
  static const double widthDoubles = 6.10;
  
  static const double netPosition = 6.70; // Center dividing line
  static const double shortServiceDistance = 1.98; // From net
  static const double shortServiceLineFar = 6.70 - 1.98; // 4.72m
  static const double shortServiceLineNear = 6.70 + 1.98; // 8.68m
  
  static const double doublesRearServiceDistance = 0.76; // From back boundary
  static const double doublesRearServiceFar = 0.76;
  static const double doublesRearServiceNear = 13.40 - 0.76; // 12.64m
  
  static const double tramlineWidth = 0.46; // Alley between singles & doubles sideline
  
  static const double netHeightCenter = 1.524;
  static const double netHeightPosts = 1.550;
}
