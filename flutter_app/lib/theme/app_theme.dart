import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _fallbackSeed = Color(0xFF6750A4); // Deep Violet

  static ThemeData createTheme(ColorScheme? dynamicColorScheme, Brightness brightness) {
    final ColorScheme scheme = dynamicColorScheme ?? ColorScheme.fromSeed(
      seedColor: _fallbackSeed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: GoogleFonts.outfitTextTheme(
        brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.3)),
        ),
        color: scheme.surfaceContainer,
        margin: EdgeInsets.zero,
      ),
      
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
  
  static BoxDecoration glassDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.white.withOpacity(0.1),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
