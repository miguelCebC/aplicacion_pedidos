import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
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
      final comercialId = prefs.getInt('comercial_id'); // ← LÍNEA DE TU CÓDIGO
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
        final batch = articulosLista
            .sublist(i, end)
            .cast<Map<String, dynamic>>();
        await db.insertarArticulosLote(batch);
      }

      print('💾 Guardando clientes...');
      await db.limpiarClientes();
      for (var i = 0; i < clientesLista.length; i += batchSize) {
        final end = (i + batchSize < clientesLista.length)
            ? i + batchSize
            : clientesLista.length;
        final batch = clientesLista
            .sublist(i, end)
            .cast<Map<String, dynamic>>();
        await db.insertarClientesLote(batch);
      }

      print('💾 Guardando comerciales...');
      await db.limpiarComerciales();
      if (comercialesLista.isNotEmpty) {
        await db.insertarComercialesLote(
          comercialesLista.cast<Map<String, dynamic>>(),
        );
      }

      // === SINCRONIZAR DATOS CRM ===
      // Solo la primera vez o si las tablas están vacías
      final provinciasExistentes = await db.obtenerProvincias();

      if (provinciasExistentes.isEmpty) {
        print('📥 Descargando datos CRM (primera vez)...');

        print('📥 Descargando provincias...');
        final provinciasLista = await apiService.obtenerProvincias();
        await db.limpiarProvincias();
        await db.insertarProvinciasLote(
          provinciasLista.cast<Map<String, dynamic>>(),
        );

        print('📥 Descargando zonas técnicas...');
        final zonasLista = await apiService.obtenerZonasTecnicas();
        await db.limpiarZonasTecnicas();
        await db.insertarZonasTecnicasLote(
          zonasLista.cast<Map<String, dynamic>>(),
        );

        print('📥 Descargando poblaciones...');
        final poblacionesLista = await apiService.obtenerPoblaciones();
        await db.limpiarPoblaciones();
        await db.insertarPoblacionesLote(
          poblacionesLista.cast<Map<String, dynamic>>(),
        );

        print('📥 Descargando campañas...');
        final campanasLista = await apiService.obtenerCampanas();
        await db.limpiarCampanas();
        await db.insertarCampanasLote(
          campanasLista.cast<Map<String, dynamic>>(),
        );

        print('📥 Descargando leads...');
        final leadsLista = await apiService.obtenerLeads();
        await db.limpiarLeads();
        await db.insertarLeadsLote(leadsLista.cast<Map<String, dynamic>>());

        print('✅ Datos CRM sincronizados');
        print('   🗺️ ${provinciasLista.length} provincias');
        print('   📍 ${zonasLista.length} zonas técnicas');
        print('   🏘️ ${poblacionesLista.length} poblaciones');
        print('   📢 ${campanasLista.length} campañas');
        print('   🎯 ${leadsLista.length} leads');
      }

      // Sincronizar agenda siempre (puede cambiar frecuentemente)
      if (comercialId != null) {
        print('📥 Actualizando agenda del comercial $comercialId...');
        final agendasLista = await apiService.obtenerAgenda(comercialId);
        await db.limpiarAgenda();
        await db.insertarAgendasLote(agendasLista.cast<Map<String, dynamic>>());
        print('   📅 ${agendasLista.length} eventos de agenda');
      }
      // [Dentro de _sincronizarEnSegundoPlano en main.dart]

      // ... (después de sincronizar comerciales)
      print('💾 Guardando comerciales...');
      await db.limpiarComerciales();
      // ...

      // 🟢 AÑADIR ESTA LÓGICA 🟢
      // Sincronizar Pedidos y Presupuestos
      print('📥 Descargando pedidos...');
      final pedidosLista = await apiService.obtenerPedidos();
      await db.limpiarPedidos(); // <-- Limpia pedidos Y líneas
      await db.insertarPedidosLote(pedidosLista.cast<Map<String, dynamic>>());

      int totalLineasPedido = 0;
      for (var pedido in pedidosLista) {
        final lineas = await apiService.obtenerLineasPedido(pedido['id']);
        for (var linea in lineas) {
          await db.insertarLineaPedido(linea);
          totalLineasPedido++;
        }
      }
      print('   📦 ${pedidosLista.length} pedidos y $totalLineasPedido líneas');

      print('📥 Descargando presupuestos...');
      final presupuestosLista = await apiService.obtenerPresupuestos();
      await db.limpiarPresupuestos(); // <-- Limpia presupuestos Y líneas
      await db.insertarPresupuestosLote(
        presupuestosLista.cast<Map<String, dynamic>>(),
      );

      int totalLineasPresupuesto = 0;
      for (var presupuesto in presupuestosLista) {
        final lineas = await apiService.obtenerLineasPresupuesto(
          presupuesto['id'],
        );
        for (var linea in lineas) {
          await db.insertarLineaPresupuesto(linea);
          totalLineasPresupuesto++;
        }
      }
      print(
        '   📋 ${presupuestosLista.length} presupuestos y $totalLineasPresupuesto líneas',
      );
      // 🟢 FIN DE LA NUEVA LÓGICA 🟢

      // === SINCRONIZAR DATOS CRM ===
      // ... (el resto de tu función) ...
      // Guardar timestamp de sincronización
      await prefs.setInt('ultima_sincronizacion', ahora);
      // Guardar timestamp de sincronización
      await prefs.setInt('ultima_sincronizacion', ahora);
      print('✅ Sincronización automática completada');
      print('   📦 ${articulosLista.length} artículos');
      print('   👥 ${clientesLista.length} clientes');
      print('   💼 ${comercialesLista.length} comerciales');
    } catch (e) {
      print('❌ Error en sincronización automática: $e');
      // No mostrar error al usuario, es en segundo plano
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pedidos Velneo',
      theme: AppTheme.theme,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<bool>(
        future: _verificarPrimeraVez(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final esPrimeraVez = snapshot.data ?? true;
          return esPrimeraVez ? const LoginScreen() : const HomeScreen();
        },
      ),
    );
  }

  Future<bool> _verificarPrimeraVez() async {
    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');
    return comercialId == null;
  }
}
