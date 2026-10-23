import 'package:flutter/material.dart';

/// Centralized YouTube-style theme system for ShreyX Tube.
/// Provides consistent colors, typography, spacing, and component styles
/// matching the observable YouTube mobile dark mode experience.
class TubeTheme {
  TubeTheme._();

  // === Surface Hierarchy (YouTube Dark Mode) ===
  static const Color background = Color(0xFF0F0F0F);      // App background
  static const Color surface = Color(0xFF1A1A1A);          // Card surfaces
  static const Color surfaceVariant = Color(0xFF272727);   // Elevated surfaces, chips
  static const Color surfaceContainer = Color(0xFF212121); // Containers
  static const Color divider = Color(0xFF333333);          // Subtle dividers
  static const Color dividerLight = Color(0xFF262626);     // Very subtle dividers

  // === Text Hierarchy ===
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textTertiary = Color(0xFF717171);
  static const Color textDisabled = Color(0xFF4D4D4D);

  // === Brand Colors ===
  static const Color accent = Color(0xFFE50914);          // ShreyX crimson
  static const Color accentLight = Color(0xFFFF2D2D);     // Lighter variant
  static const Color progressRed = Color(0xFFFF0000);     // YouTube-style red progress
  
  // === Functional Colors ===
  static const Color live = Color(0xFFFF0000);             // Live indicator
  static const Color error = Color(0xFFCF6679);            // Error state
  static const Color success = Color(0xFF4CAF50);          // Success/complete
  static const Color membersGold = Color(0xFFFFD700);      // Members-only badge
  
  // === Shimmer/Skeleton Colors ===
  static const Color shimmerBase = Color(0xFF1A1A1A);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);

  // === Typography ===
  
  /// Video title in full card (Home feed) — 15sp, semi-bold, 2 lines max
  static const TextStyle titleLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
    letterSpacing: 0.0,
  );

  /// Video title in compact card (Up Next, Search) — 14sp, medium
  static const TextStyle titleMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.3,
  );

  /// Section headers — 16sp, semi-bold
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.2,
  );

  /// Channel name, view count, date — 12sp, regular
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.2,
  );

  /// Duration badge, labels — 11sp
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.0,
  );

  /// Chip text — 13sp, medium
  static const TextStyle chipText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.0,
  );

  /// App bar title — 20sp, bold
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: 0.5,
  );

  /// Tab text — 13sp, semi-bold
  static const TextStyle tabText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textSecondary,
  );

  // === Spacing Constants ===
  static const double pagePadding = 0.0;        // Home feed is edge-to-edge
  static const double cardPaddingH = 12.0;       // Horizontal padding inside metadata area
  static const double cardPaddingV = 12.0;       // Vertical padding between cards
  static const double cardMetadataGap = 12.0;    // Gap between thumbnail and metadata
  static const double chipHeight = 32.0;         // Filter chip height
  static const double chipSpacing = 8.0;         // Gap between chips
  static const double chipPaddingH = 12.0;       // Horizontal padding inside chip
  static const double thumbnailRadius = 0.0;     // YouTube uses 0 radius on full cards, 8 on compact
  static const double thumbnailRadiusCompact = 8.0;
  static const double avatarSize = 36.0;         // Channel avatar
  static const double avatarSizeSmall = 24.0;    // Compact avatar
  static const double miniPlayerHeight = 64.0;   // Mini player bar
  static const double bottomNavHeight = 56.0;    // Bottom navigation
  static const double chipRowHeight = 48.0;      // Chip filter row including padding
  static const double durationBadgeRadius = 4.0; // Duration badge corner radius
  static const double compactThumbWidth = 136.0; // Compact card thumbnail width (modern YouTube)
  static const double compactThumbHeight = 76.5; // Compact card thumbnail height (16:9)

  // === Component Decorations ===
  
  /// Duration badge decoration
  static BoxDecoration get durationBadge => BoxDecoration(
    color: Colors.black.withValues(alpha: 0.8),
    borderRadius: BorderRadius.circular(durationBadgeRadius),
  );

  /// Filter chip decoration (unselected)
  static BoxDecoration get chipUnselected => BoxDecoration(
    color: surfaceVariant,
    borderRadius: BorderRadius.circular(chipHeight / 2),
  );

  /// Filter chip decoration (selected)
  static BoxDecoration get chipSelected => BoxDecoration(
    color: textPrimary,
    borderRadius: BorderRadius.circular(chipHeight / 2),
  );

  /// Bottom sheet decoration
  static BoxDecoration get bottomSheet => const BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  );

  /// Card surface decoration
  static BoxDecoration get cardSurface => const BoxDecoration(
    color: background,
  );

  // === ThemeData Builder ===
  
  static ThemeData buildThemeData() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        onSurface: textPrimary,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: appBarTitle,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        height: bottomNavHeight,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textPrimary);
          }
          return const TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: textTertiary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: textPrimary, size: 24);
          }
          return const IconThemeData(color: textTertiary, size: 24);
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 0.5,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: progressRed,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
        thumbColor: progressRed,
        trackHeight: 2.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textTertiary,
        indicatorColor: textPrimary,
        labelStyle: tabText,
        unselectedLabelStyle: tabText,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
    );
  }
}
