import 'package:flutter/material.dart';

class AppTheme {
  // Paleta de colores corporativa
  static const Color colorPrincipal = Color(0xFF032458);
  static const Color colorSecundario = Color(0xFF162846);
  static const Color colorResalto = Color(0xFFCAD3E2);
  static const Color colorFondo = Color(0xFFFFFFFF);
  static const Color colorAlertaPrincipal = Color(0xFFF44336);
  static const Color colorAlertaSecundario = Color(0xFFBA000D);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colorPrincipal,
        primary: colorPrincipal,
        secondary: colorSecundario,
        surface: colorFondo,
        background: colorFondo,
      ),
      scaffoldBackgroundColor: colorFondo,
      appBarTheme: const AppBarTheme(
        backgroundColor: colorPrincipal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorPrincipal,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: colorResalto),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: colorResalto),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: colorPrincipal, width: 2),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: colorPrincipal, // Color de fondo del botón
        foregroundColor: Colors.white, // Color del icono (foreground)
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorPrincipal,
        indicatorColor: colorSecundario,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            );
          }
          return const TextStyle(color: colorResalto, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: colorResalto);
        }),
      ),
    );
  }
}
