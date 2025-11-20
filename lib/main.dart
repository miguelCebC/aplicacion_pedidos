import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/auth_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VelneoApp());
}

class VelneoApp extends StatefulWidget {
  const VelneoApp({super.key});

  @override
  State<VelneoApp> createState() => _VelneoAppState();
}

class _VelneoAppState extends State<VelneoApp> {
  @override
  void initState() {
    super.initState();
    // Iniciar sincronización en segundo plano
    //_sincronizarEnSegundoPlano();
  }

  Future<Widget> _verificarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');

    if (comercialId == null) {
      // No hay sesión, ir a login completo
      return const LoginScreen();
    }

    // Hay sesión guardada, ir a pantalla de autenticación
    return const AuthScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRM Velneo',
      theme: AppTheme.theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],
      home: FutureBuilder<Widget>(
        future: _verificarSesion(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }
}
