import 'package:flutter/material.dart';

const kBrandGreen = Color(0xFF00A884);
const kBrandGreenDark = Color(0xFF00876B);
const kSeenBlue = Color(0xFF53BDEB);

// Dark theme colors
const kDarkBg = Color(0xFF111B21);
const kDarkSurface = Color(0xFF1F2C34);
const kDarkCard = Color(0xFF202C33);
const kDarkBubbleMine = Color(0xFF005C4B);
const kDarkBubbleOther = Color(0xFF1F2C34);
const kDarkText = Color(0xFFE9EDEF);
const kDarkSubText = Color(0xFF8696A0);
const kDarkDivider = Color(0xFF2A3942);
const kDarkInput = Color(0xFF2A3942);

// Light theme colors
const kLightBg = Color(0xFFDADADA);
const kLightSurface = Color(0xFFFFFFFF);
const kLightCard = Color(0xFFFFFFFF);
const kLightBubbleMine = Color(0xFFD9FDD3);
const kLightBubbleOther = Color(0xFFFFFFFF);
const kLightText = Color(0xFF111B21);
const kLightSubText = Color(0xFF667781);
const kLightInput = Color(0xFFFFFFFF);

ThemeData buildDarkTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kDarkBg,
      colorScheme: const ColorScheme.dark(
        primary: kBrandGreen,
        surface: kDarkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kDarkSurface,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: kDarkText),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: kDarkInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        hintStyle: TextStyle(color: kDarkSubText),
      ),
      iconTheme: const IconThemeData(color: kDarkSubText),
    );

ThemeData buildLightTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: kLightBg,
      colorScheme: const ColorScheme.light(
        primary: kBrandGreen,
        surface: kLightSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kBrandGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: kLightText),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: kLightInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        hintStyle: TextStyle(color: kLightSubText),
      ),
      iconTheme: const IconThemeData(color: kLightSubText),
    );
