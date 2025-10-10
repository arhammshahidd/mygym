import 'package:flutter/material.dart';

class AppTheme {
  // Color definitions
  static const Color appBackgroundColor = Color(0xFF3D3D3D); // Dark gray background
  static const Color primaryColor = Color(0xFFDF8A35); // Orange for buttons and borders
  static const Color cardBackgroundColor = Color(0xFF7A7A7A); // Medium gray for cards/boxes
  static const Color textColor = Color(0xFFFFFFFF); // White text
  static const Color selectedTabColor = Color(0xFFDF8A35); // Orange for selected tabs
  static const Color unselectedTabColor = Color(0xFFFFFFFF); // White for unselected tabs

  static ThemeData get darkTheme {
    return ThemeData(
      // App background
      scaffoldBackgroundColor: appBackgroundColor,
      
      // Color scheme
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
        surface: cardBackgroundColor,
        background: appBackgroundColor,
        onPrimary: textColor,
        onSecondary: textColor,
        onSurface: textColor,
        onBackground: textColor,
      ),
      
      // App bar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: appBackgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      
      // Card theme
      cardTheme: const CardThemeData(
        color: cardBackgroundColor,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      
      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textColor,
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      
      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
        ),
      ),
      
      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: textColor),
        hintStyle: TextStyle(color: textColor.withOpacity(0.7)),
      ),
      
      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textColor, fontSize: 32, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
        titleSmall: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: textColor, fontSize: 16),
        bodyMedium: TextStyle(color: textColor, fontSize: 14),
        bodySmall: TextStyle(color: textColor, fontSize: 12),
        labelLarge: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
        labelMedium: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
        labelSmall: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      
      // Bottom navigation bar theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: appBackgroundColor,
        selectedItemColor: textColor, // White for selected items
        unselectedItemColor: textColor, // White for unselected items
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      
      // Divider theme
      dividerTheme: const DividerThemeData(
        color: primaryColor,
        thickness: 1,
      ),
      
      // Icon theme - Global icon color
      iconTheme: const IconThemeData(
        color: textColor,
        size: 24,
      ),
      
      // Primary icon theme
      primaryIconTheme: const IconThemeData(
        color: textColor,
        size: 24,
      ),
      
      // List tile theme
      listTileTheme: const ListTileThemeData(
        tileColor: cardBackgroundColor,
        textColor: textColor,
        iconColor: textColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.grey;
        }),
        trackColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.withOpacity(0.5);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      
      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(textColor),
        side: const BorderSide(color: primaryColor, width: 2),
      ),
      
      // Radio theme
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.grey;
        }),
      ),
      
      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withOpacity(0.3),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withOpacity(0.2),
      ),
      
      // Progress indicator theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: cardBackgroundColor,
        circularTrackColor: cardBackgroundColor,
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: cardBackgroundColor,
        selectedColor: primaryColor,
        labelStyle: const TextStyle(color: textColor),
        secondaryLabelStyle: const TextStyle(color: textColor),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: primaryColor),
        ),
      ),
      
      // Floating action button theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: textColor,
        elevation: 6,
      ),
      
      // Dialog theme
      dialogTheme: const DialogThemeData(
        backgroundColor: cardBackgroundColor,
        titleTextStyle: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: textColor, fontSize: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      
      // Snack bar theme
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: cardBackgroundColor,
        contentTextStyle: TextStyle(color: textColor),
        actionTextColor: primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      
      // Bottom sheet theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      
      // Tab bar theme
      tabBarTheme: const TabBarThemeData(
        labelColor: textColor, // White for selected tabs
        unselectedLabelColor: textColor, // White for unselected tabs
        indicatorColor: primaryColor, // Orange indicator
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, color: textColor),
      ),
    );
  }
}
