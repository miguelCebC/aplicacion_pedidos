import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
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

  Future<void> _sincronizarEnSegundoPlano() async {
    try {
      print('🔄 Iniciando sincronización automática en segundo plano...');

      final prefs = await SharedPreferences.getInstance();
      String? url = prefs.getString('velneo_url');
      String? apiKey = prefs.getString('velneo_api_key');
      final comercialId = prefs.getInt('comercial_id');

      // Si no hay configuración, no sincronizar
      if (url == null || apiKey == null || url.isEmpty || apiKey.isEmpty) {
        print('⚠️ No hay configuración de API, omitiendo sincronización');
        return;
      }

      // Verificar última sincronización
      final ultimaSync = prefs.getInt('ultima_sincronizacion') ?? 0;
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final diferencia = ahora - ultimaSync;
      final horasDesdeUltimaSync = diferencia / (1000 * 60 * 60);

      // Solo sincronizar si han pasado más de 4 horas (ajustable)
      if (horasDesdeUltimaSync < 4) {
        print(
          '⏭️ Sincronización reciente (hace ${horasDesdeUltimaSync.toStringAsFixed(1)}h), omitiendo',
        );
        return;
      }

      // Asegurar protocolo en URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      print('📥 Descargando artículos...');
      final articulosLista = await apiService.obtenerArticulos();

      print('📥 Descargando clientes y comerciales...');
      final resultadoClientes = await apiService.obtenerClientes();
      final clientesLista = resultadoClientes['clientes'] as List;
      final comercialesLista = resultadoClientes['comerciales'] as List;

      print('💾 Guardando artículos...');
      await db.limpiarArticulos();
      const batchSize = 500;
      for (var i = 0; i < articulosLista.length; i += batchSize) {
        final end = (i + batchSize < articulosLista.length)
            ? i + batchSize
            : articulosLista.length;
        await db.insertarArticulosLote(
          articulosLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      print('💾 Guardando clientes...');
      await db.limpiarClientes();
      for (var i = 0; i < clientesLista.length; i += batchSize) {
        final end = (i + batchSize < clientesLista.length)
            ? i + batchSize
            : clientesLista.length;
        await db.insertarClientesLote(
          clientesLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      print('💾 Guardando comerciales...');
      await db.limpiarComerciales();
      for (var i = 0; i < comercialesLista.length; i += batchSize) {
        final end = (i + batchSize < comercialesLista.length)
            ? i + batchSize
            : comercialesLista.length;
        await db.insertarComercialesLote(
          comercialesLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );
      print('✅ Sincronización en segundo plano completada');
    } catch (e) {
      print('❌ Error en sincronización en segundo plano: $e');
    }
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
