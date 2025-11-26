import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'catalogo_articulos_screen.dart';
import 'catalogo_clientes_screen.dart';
import 'lista_pedidos_screen.dart';
import 'configuracion_screen.dart';
import 'login_screen.dart';
import 'crear_pedido_screen.dart';
import 'crear_cliente_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _nombreComercial = '';

  // Keys para poder recargar las listas desde aquí
  final GlobalKey<CatalogoClientesScreenState> _clientesKey = GlobalKey();
  final GlobalKey<ListaPedidosScreenState> _pedidosKey = GlobalKey();

  late List<Widget> _screens;
  final List<String> _titles = ['Artículos', 'Pedidos', 'Clientes'];

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();

    // Configurar listener de cierre forzoso
    VelneoAPIService.onCierreForzoso = (mensaje) {
      _mostrarDialogoCierre(mensaje);
    };

    _screens = [
      const CatalogoArticulosScreen(),
      ListaPedidosScreen(key: _pedidosKey),
      CatalogoClientesScreen(key: _clientesKey),
    ];

    // 🟢 INICIAR SINCRONIZACIÓN COMPLETA EN SEGUNDO PLANO
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizarGlobalEnSegundoPlano();
    });
  }

  void _mostrarDialogoCierre(String mensaje) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.signal_wifi_off, color: Colors.red),
                SizedBox(width: 10),
                Text('Sin Conexión'),
              ],
            ),
            content: Text(
              '$mensaje\n\nLa aplicación se cerrará por seguridad.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  SystemNavigator.pop();
                },
                child: const Text(
                  'CERRAR APLICACIÓN',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombreComercial = prefs.getString('comercial_nombre') ?? 'Comercial';
    });
  }

  // 🟢 LÓGICA DE SINCRONIZACIÓN COMPLETA (Igual que Configuración)
  Future<void> _sincronizarGlobalEnSegundoPlano() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      final comercialId = prefs.getInt('comercial_id');

      if (url == null || apiKey == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⬇️ Sincronizando datos completos...'),
            duration: Duration(seconds: 4), // Un poco más de tiempo visible
            backgroundColor: Color(0xFF032458),
          ),
        );
      }

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );
      final db = DatabaseHelper.instance;

      print('🚀 [HOME] Iniciando Sincronización Completa en 2º Plano...');

      // 1. Conexión
      if (!await api.probarConexion()) {
        print('⚠️ [HOME] No hay conexión con la API.');
        return;
      }

      // 2. Artículos (por lotes)
      final articulosLista = await api.obtenerArticulos();
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

      // 2.1 Familias
      await db.limpiarFamilias();
      await db.insertarFamiliasLote(
        (await api.obtenerFamilias()).cast<Map<String, dynamic>>(),
      );

      // 3. Clientes y Comerciales
      final resultadoClientes = await api.obtenerClientes();
      final clientesList = resultadoClientes['clientes'] as List;
      final comercialesList = resultadoClientes['comerciales'] as List;

      await db.limpiarClientes();
      for (var i = 0; i < clientesList.length; i += batchSize) {
        final end = (i + batchSize < clientesList.length)
            ? i + batchSize
            : clientesList.length;
        await db.insertarClientesLote(
          clientesList.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesList.cast<Map<String, dynamic>>(),
      );

      // 3.1 Contactos (Teléfonos/Emails)
      final contactos = await api.obtenerContactos();
      await db.insertarContactosLote(contactos);

      // 4. Series y Formas de Pago
      await db.limpiarSeries();
      await db.insertarSeriesLote(
        (await api.obtenerSeries()).cast<Map<String, dynamic>>(),
      );
      await db.insertarFormasPagoLote(
        (await api.obtenerFormasPago()).cast<Map<String, dynamic>>(),
      );

      // 5. Direcciones
      await db.limpiarDirecciones();
      await db.insertarDireccionesLote(
        (await api.obtenerDirecciones()).cast<Map<String, dynamic>>(),
      );

      // 6. CRM (Maestros)
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        (await api.obtenerTiposVisita()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(
        (await api.obtenerProvincias()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(
        (await api.obtenerZonasTecnicas()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        (await api.obtenerPoblaciones()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarCampanas();
      await db.insertarCampanasLote(
        (await api.obtenerCampanas()).cast<Map<String, dynamic>>(),
      );

      // 7. Transaccional
      // Leads
      await db.limpiarLeads();
      await db.insertarLeadsLote(
        (await api.obtenerLeads()).cast<Map<String, dynamic>>(),
      );

      // Agenda
      await db.limpiarAgenda();
      await db.insertarAgendasLote(
        (await api.obtenerAgenda(comercialId)).cast<Map<String, dynamic>>(),
      );

      // Pedidos
      await db.limpiarPedidos();
      await db.insertarPedidosLote(
        (await api.obtenerPedidos()).cast<Map<String, dynamic>>(),
      );
      await db.insertarLineasPedidoLote(
        (await api.obtenerTodasLineasPedido()).cast<Map<String, dynamic>>(),
      );

      // Presupuestos
      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        (await api.obtenerPresupuestos()).cast<Map<String, dynamic>>(),
      );
      await db.insertarLineasPresupuestoLote(
        (await api.obtenerTodasLineasPresupuesto())
            .cast<Map<String, dynamic>>(),
      );

      // 8. Tarifas
      await db.limpiarTarifasCliente();
      await db.insertarTarifasClienteLote(
        (await api.obtenerTarifasCliente()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarTarifasArticulo();
      await db.insertarTarifasArticuloLote(
        (await api.obtenerTarifasArticulo()).cast<Map<String, dynamic>>(),
      );

      // 9. Movimientos (Histórico)
      await db.limpiarMovimientos();
      final movimientos = await api.obtenerMovimientos();
      for (var i = 0; i < movimientos.length; i += batchSize) {
        final end = (i + batchSize < movimientos.length)
            ? i + batchSize
            : movimientos.length;
        await db.insertarMovimientosLote(
          movimientos.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      // 10. IVA
      final configIva = await api.obtenerConfiguracionIVA();
      if (configIva.isNotEmpty) {
        await prefs.setDouble('iva_general', configIva['iva_general']!);
        await prefs.setDouble('iva_reducido', configIva['iva_reducido']!);
        await prefs.setDouble(
          'iva_superreducido',
          configIva['iva_superreducido']!,
        );
        await prefs.setDouble('iva_exento', configIva['iva_exento']!);
      }

      // Finalizar
      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      print('✅ [HOME] Sincronización completa finalizada.');

      if (mounted) {
        // 🟢 CLAVE: RECARGAR LAS PANTALLAS HIJAS
        // Esto hace que aparezcan los nombres de clientes en los pedidos
        _pedidosKey.currentState?.recargarPedidos();
        _clientesKey.currentState?.recargarClientes();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos actualizados y listos'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("⚠️ Error en sync fondo: $e");
    }
  }

  void _cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _onFabPressed() async {
    if (_selectedIndex == 1) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CrearPedidoScreen()),
      );
      if (result == true) _pedidosKey.currentState?.recargarPedidos();
    } else if (_selectedIndex == 2) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CrearClienteScreen()),
      );
      if (result == true) _clientesKey.currentState?.recargarClientes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      floatingActionButton: (_selectedIndex == 1 || _selectedIndex == 2)
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              backgroundColor: const Color(0xFF032458),
              child: Icon(
                _selectedIndex == 1 ? Icons.add : Icons.add,
                color: Colors.white,
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF032458),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Artículos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Pedidos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF032458)),
              accountName: Text(
                _nombreComercial,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: null,
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFF032458)),
              title: const Text('Configuración'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfiguracionScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            // const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red),
              ),
              onTap: _cerrarSesion,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
