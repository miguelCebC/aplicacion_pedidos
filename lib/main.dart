import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart'; // Asegura que este archivo existe y tiene la clase LoginScreen
import 'screens/auth_screen.dart'; // Asegura que este archivo existe y tiene la clase AuthScreen

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
  }

  Future<Widget> _verificarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');

    // Si no hay comercial guardado, vamos al Login
    if (comercialId == null) {
      return const LoginScreen();
    }

    // Si hay comercial, vamos a la pantalla de PIN (AuthScreen)
    return const AuthScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRM Velneo',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false, // Quitar etiqueta debug
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],
      home: FutureBuilder<Widget>(
        future: _verificarSesion(),
        builder: (context, snapshot) {
          // Mientras carga, mostramos spinner
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF032458)),
              ),
            );
          }
          // Si hay error o es nulo, por seguridad mandamos al Login
          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }
}
