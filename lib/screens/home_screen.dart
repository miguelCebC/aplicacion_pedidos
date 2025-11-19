import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crm_calendario_screen.dart';
import 'pedidos_screen.dart';
import 'presupuestos_screen.dart';
import 'leads_screen.dart';
import 'configuracion_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _comercialNombre = '';

  final List<Widget> _screens = const [
    CRMCalendarioScreen(),
    PedidosScreen(),
    PresupuestosScreen(),
    LeadsScreen(),
  ];

  final List<String> _titles = const [
    'Agenda',
    'Pedidos',
    'Presupuestos',
    'Leads',
  ];

  @override
  void initState() {
    super.initState();
    _cargarNombreComercial();
  }

  Future<void> _cargarNombreComercial() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _comercialNombre = prefs.getString('comercial_nombre') ?? 'Usuario';
    });
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('comercial_id');
      await prefs.remove('comercial_nombre');
      await prefs.remove('usuario_app_id');
      await prefs.remove('usuario_app_nombre');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _abrirConfiguracion() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConfiguracionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: const Color(0xFF162846),
        foregroundColor: Colors.white,
        actions: [
          // Botón de configuración
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: _abrirConfiguracion,
          ),
          // Menú de usuario
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            tooltip: _comercialNombre,
            onSelected: (value) {
              if (value == 'cerrar_sesion') {
                _cerrarSesion();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _comercialNombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Comercial',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'cerrar_sesion',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: Color(0xFF162846),
        indicatorColor: Colors.white.withOpacity(0.1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today, color: Colors.white),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart, color: Colors.white),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description, color: Colors.white),
            label: 'Presupuestos',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Colors.white),
            label: 'Leads',
          ),
        ],
      ),
    );
  }
}
