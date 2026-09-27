import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// نظام الألوان والثيم الرسمي لمنصة "ميثاق"
/// النمط: المؤسسي الفاخر - كحلي داكن + ذهبي
class AppColors {
  AppColors._();

  // الألوان الأساسية
  static const Color navyDark = Color(0xFF0F1B2E);
  static const Color navyMedium = Color(0xFF16243B);
  static const Color navyLight = Color(0xFF1F3151);
  static const Color navySurface = Color(0xFF223655);

  static const Color gold = Color(0xFFC9A227);
  static const Color goldLight = Color(0xFFE0C158);
  static const Color goldDark = Color(0xFFA3811C);

  // ألوان الحالة
  static const Color success = Color(0xFF2ECC71);
  static const Color successBg = Color(0xFF14301F);
  static const Color danger = Color(0xFFE74C3C);
  static const Color dangerBg = Color(0xFF3A1A17);
  static const Color warning = Color(0xFFF39C12);
  static const Color warningBg = Color(0xFF3A2C10);
  static const Color info = Color(0xFF3498DB);

  // ألوان النصوص
  static const Color textPrimary = Color(0xFFF5F1E6);
  static const Color textSecondary = Color(0xFFB7C0CF);
  static const Color textMuted = Color(0xFF7C8CA3);

  static const Color divider = Color(0xFF2A3C58);

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDark],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [navyDark, navyMedium],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.almaraiTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.navyDark,
      primaryColor: AppColors.gold,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.goldLight,
        surface: AppColors.navySurface,
        error: AppColors.danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.navyDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.gold),
        titleTextStyle: GoogleFonts.almarai(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.navySurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.navyDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.almarai(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.gold, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.almarai(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.goldLight,
          textStyle: GoogleFonts.almarai(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.navyLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.6),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.navyMedium,
        selectedItemColor: AppColors.gold,
        unselectedItemColor: AppColors.textMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.navySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navyLight,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: AppColors.divider,
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.gold,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.gold,
        labelStyle: GoogleFonts.almarai(fontWeight: FontWeight.w700),
      ),
    );
  }
}
