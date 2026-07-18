import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Brand colors — ChangYai white & green (Teal)
  static const Color primaryColor = Color(0xFF0D9488); // Teal 600
  static const Color secondaryColor = Color(0xFF0F766E); // Teal 700 (เข้มกว่า)
  static const Color accentColor = Color(0xFF14B8A6); // Teal 500
  static const Color softGreen = Color(0xFFCCFBF1); // Teal 100
  static const Color paleGreen = Color(0xFFF0FDFA); // Teal 50

  // สีสถานะ — สงวนไว้สำหรับบอกสถานะเท่านั้น ไม่เอาไปใช้เป็นสีแบรนด์
  static const Color urgentColor = Color(0xFFD32F2F); // Red
  static const Color warningColor = Color(0xFFE65100); // Orange
  static const Color successColor = Color(0xFF2E7D32); // Green

  /// พื้นหลังขาวอมเขียวจาง ๆ ทำให้พื้นผิวสีขาวแยกชั้นโดยไม่ต้องใช้เงาหนัก
  static const Color _scaffoldLight = Color(0xFFF5FAF8);
  static const Color _borderLight = Color(0xFFDCE9E6);

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: Brightness.light,
  ).copyWith(
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: secondaryColor,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: const Color(0xFF17332F),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: paleGreen,
    surfaceContainer: const Color(0xFFE8F5F2),
    outline: const Color(0xFF76908B),
    outlineVariant: _borderLight,
  );

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: _lightScheme,
    scaffoldBackgroundColor: _scaffoldLight,
    canvasColor: Colors.white,
    dividerColor: _borderLight,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF17332F),
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: _borderLight)),
      titleTextStyle: TextStyle(
        color: Color(0xFF17332F),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderLight),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: secondaryColor,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: secondaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: secondaryColor),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: softGreen,
      side: const BorderSide(color: _borderLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(color: Color(0xFF365B55)),
      checkmarkColor: secondaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.white,
      indicatorColor: softGreen,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      selectedIconTheme: const IconThemeData(color: secondaryColor),
      selectedLabelTextStyle: const TextStyle(
        color: secondaryColor,
        fontWeight: FontWeight.w700,
      ),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF536A66)),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xFF536A66)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: softGreen,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(color: Color(0xFF365B55), fontSize: 12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: secondaryColor,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: secondaryColor,
      selectedColor: secondaryColor,
      selectedTileColor: paleGreen,
    ),
    dividerTheme: const DividerThemeData(
      color: _borderLight,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
    ),
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    // โหมดมืดเลือกสเต็ปเอง ไม่ใช่พลิกสีจากโหมดสว่าง
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
    ),
  );
}
