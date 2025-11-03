import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'crear_pedido_screen.dart';
import 'lista_pedidos_screen.dart';
import 'configuracion_screen.dart';
import 'crm_calendario_screen.dart'; // ← AÑADIR IMPORT

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _ultimaSincronizacion = '';

  @override
  void initState() {
    super.initState();
    _cargarDatosPrueba();
    _cargarInfoSincronizacion();
  }

  Future<void> _cargarDatosPrueba() async {
    await DatabaseHelper.instance.cargarDatosPrueba();
  }

  Future<void> _cargarInfoSincronizacion() async {
    final prefs = await SharedPreferences.getInstance();
    final ultimaSync = prefs.getInt('ultima_sincronizacion');

    if (ultimaSync != null) {
      final fecha = DateTime.fromMillisecondsSinceEpoch(ultimaSync);
      final ahora = DateTime.now();
      final diferencia = ahora.difference(fecha);

      String texto;
      if (diferencia.inMinutes < 1) {
        texto = 'Sincronizado hace unos segundos';
      } else if (diferencia.inHours < 1) {
        texto = 'Sincronizado hace ${diferencia.inMinutes} min';
      } else if (diferencia.inDays < 1) {
        texto = 'Sincronizado hace ${diferencia.inHours}h';
      } else {
        texto = 'Sincronizado hace ${diferencia.inDays}d';
      }

      if (mounted) {
        setState(() => _ultimaSincronizacion = texto);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const CrearPedidoScreen(),
      const ListaPedidosScreen(),
      const CRMCalendarioScreen(), // ← AÑADIR PANTALLA CRM
      const ConfiguracionScreen(),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_ultimaSincronizacion.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              color: const Color(0xFFCAD3E2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_done,
                    size: 14,
                    color: Color(0xFF032458),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _ultimaSincronizacion,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF032458),
                    ),
                  ),
                ],
              ),
            ),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.add_shopping_cart),
                label: 'Nuevo Pedido',
              ),
              NavigationDestination(icon: Icon(Icons.list), label: 'Pedidos'),
              NavigationDestination(
                icon: Icon(Icons.calendar_today),
                label: 'Agenda',
              ), // ← AÑADIR DESTINO
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Configuración',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
