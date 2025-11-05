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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 🟢 2. Volver a la lista de 4 pestañas
  final List<String> _tabs = [
    'Nuevo Pedido',
    'Lista Pedidos',
    'CRM',
    'Configuración',
  ];

  // 🟢 3. Volver a los 4 iconos
  final List<IconData> _tabIcons = [
    Icons.add_shopping_cart,
    Icons.list_alt,
    Icons.calendar_today,
    Icons.settings,
  ];

  // 🟢 4. Volver a las 4 pantallas
  final List<Widget> _tabViews = [
    const CrearPedidoScreen(),
    const ListaPedidosScreen(),
    const CRMCalendarioScreen(),
    const ConfiguracionScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length, // Se actualiza solo
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      appBar: AppBar(
        title: const Text('Gestión de Pedidos'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: List.generate(_tabs.length, (index) {
            return Tab(icon: Icon(_tabIcons[index]), text: _tabs[index]);
          }),
        ),
      ),
      body: TabBarView(controller: _tabController, children: _tabViews),
    );
  }
}
