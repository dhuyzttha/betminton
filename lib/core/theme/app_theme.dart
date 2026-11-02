import 'package:flutter/material.dart';

class HawkEyeTheme {
  // Main backgrounds matching Badminton AI Analyzer v4.0 PRO AI screenshot & reference video
  static const Color background = Color(0xFF090E17);
  static const Color surface = Color(0xFF121A25);
  static const Color surfaceInput = Color(0xFF0B111A);
  static const Color surfaceElevated = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0xFF263345);
  static const Color panelBg = Color(0xFF010B1B);
  static const Color bottomCardBg = Color(0xFF091421);

  // Brand & Control accents from v4.0 PRO AI UI
  static const Color accentBlue = Color(0xFF0EA5E9);
  static const Color tabActiveBlue = Color(0xFF0284C7);
  static const Color runGreen = Color(0xFF10B981);
  static const Color badgeTealBg = Color(0xFF0A2E36);
  static const Color badgeTealText = Color(0xFF2DD4BF);
  static const Color checkboxPurple = Color(0xFFA855F7);
  static const Color sliderAmber = Color(0xFFF59E0B);

  // Player theme colors matching reference broadcast video
  static const Color playerTu = Color(0xFF38BDF8);     // Tú (Đội bạn - Sky Blue)
  static const Color playerCuong = Color(0xFF34D399);  // Cường (Đội bạn - Emerald Green)
  static const Color playerNam = Color(0xFFFBBF24);    // Nam (Đội mình - Amber Orange)
  static const Color playerThanh = Color(0xFFC084FC);  // Thành (Đội mình - Lavender Purple)

  // Status & Telemetry colors
  static const Color hudTimeBlue = Color(0xFF7DD3FC);
  static const Color hudActiveGreen = Color(0xFF4ADE80);
  static const Color hudYellowNumber = Color(0xFFFACC15);
  static const Color shuttleYellow = Color(0xFFFACC15);
  static const Color shuttleGlow = Color(0xFFF59E0B);
  static const Color statePaused = Color(0xFF94A3B8);

  // 2D Court Map Colors
  static const Color courtMapBg = Color(0xFF0E1B2A);
  static const Color courtFloor = Color(0xFF164846);
  static const Color courtLines = Colors.white;

  // Text hierarchy
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: accentBlue,
      cardColor: surface,
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: runGreen,
        surface: surface,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accentBlue,
        inactiveTrackColor: Color(0xFF2A3444),
        thumbColor: accentBlue,
        trackHeight: 4.5,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
