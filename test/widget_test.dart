// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aplicacion_pedidos/main.dart';

void main() {
  testWidgets('Verifica que se muestra la pantalla de configuración', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VelneoApp());

    // Verifica que aparece el título de configuración
    expect(find.text('Configuración API Velneo'), findsOneWidget);

    // Verifica que existen los campos de entrada
    expect(find.byType(TextField), findsNWidgets(2));

    // Verifica que existe el botón de continuar
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('Verifica validación de campos vacíos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VelneoApp());

    // Intenta hacer clic en continuar sin llenar los campos
    await tester.tap(find.text('Continuar'));
    await tester.pump();

    // Verifica que aparece el mensaje de error
    expect(find.text('Por favor completa todos los campos'), findsOneWidget);
  });
}
