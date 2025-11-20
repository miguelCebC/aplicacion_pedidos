import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalogo_articulos_screen.dart';
import 'catalogo_clientes_screen.dart';
import 'lista_pedidos_screen.dart';
import 'configuracion_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _nombreComercial = '';

  // 🟢 1. LISTA DE PANTALLAS (Orden: Artículos, Pedidos, Clientes)
  final List<Widget> _screens = [
    const CatalogoArticulosScreen(),
    const ListaPedidosScreen(),
    const CatalogoClientesScreen(), // 🟢 AQUI estaba el error, ahora apunta a Clientes
  ];

  // Títulos para la barra superior
  final List<String> _titles = [
    'Catálogo de Artículos',
    'Mis Pedidos',
    'Cartera de Clientes',
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombreComercial = prefs.getString('comercial_nombre') ?? 'Comercial';
    });
  }

  Future<void> _cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🟢 2. BARRA SUPERIOR RECUPERADA
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]), // Título dinámico
        backgroundColor: const Color(0xFF032458), // 🟢 Color Azul Corporativo
        foregroundColor: Colors.white, // Texto blanco
        elevation: 0,
        // El botón del menú (hamburguesa) aparece automático porque hay un Drawer
        actions: [
          // Botón rápido de configuración
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConfiguracionScreen(),
                ),
              );
            },
          ),
        ],
      ),

      // CUERPO
      body: IndexedStack(index: _selectedIndex, children: _screens),

      // 🟢 3. BARRA DE NAVEGACIÓN INFERIOR
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF032458), // Azul al seleccionar
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            // Ítem 0: Artículos
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Artículos',
            ),
            // Ítem 1: Pedidos
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined),
              activeIcon: Icon(Icons.shopping_cart),
              label: 'Pedidos',
            ),
            // Ítem 2: Clientes (Corregido)
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Clientes',
            ),
          ],
        ),
      ),

      // MENÚ LATERAL (Drawer)
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF032458), // Azul corporativo en la cabecera
              ),
              accountName: Text(
                _nombreComercial,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              accountEmail: const Text('Kyro CRM'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Color(0xFF032458)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync, color: Color(0xFF032458)),
              title: const Text('Sincronizar Datos'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConfiguracionScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            const Spacer(), // Empuja el botón de salir al final
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _cerrarSesion();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
