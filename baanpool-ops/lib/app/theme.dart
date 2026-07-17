import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Brand colors — Maintenance ขาว-เขียวอมฟ้า (Teal)
  static const Color primaryColor = Color(0xFF0D9488); // Teal 600
  static const Color secondaryColor = Color(0xFF0F766E); // Teal 700 (เข้มกว่า)

  // สีสถานะ — สงวนไว้สำหรับบอกสถานะเท่านั้น ไม่เอาไปใช้เป็นสีแบรนด์
  static const Color urgentColor = Color(0xFFD32F2F); // Red
  static const Color warningColor = Color(0xFFE65100); // Orange
  static const Color successColor = Color(0xFF2E7D32); // Green

  /// พื้นหลังขาวอมเขียวจางๆ — ให้การ์ดสีขาวลอยขึ้นมาอ่านง่าย
  static const Color _scaffoldLight = Color(0xFFF6FAF9);

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: _scaffoldLight,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: _scaffoldLight,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE3EBEA)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
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
