import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;

void main() {
  runApp(const VelneoApp());
}

class VelneoApp extends StatelessWidget {
  const VelneoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pedidos Velneo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF032458),
          primary: const Color(0xFF032458),
          secondary: const Color(0xFF162846),
          surface: const Color(0xFFFFFFFF),
          background: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF032458),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF032458),
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFCAD3E2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFCAD3E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF032458), width: 2),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF032458),
          indicatorColor: const Color(0xFF162846),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              );
            }
            return const TextStyle(color: Color(0xFFCAD3E2), fontSize: 12);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Colors.white);
            }
            return const IconThemeData(color: Color(0xFFCAD3E2));
          }),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// Gestor de base de datos local
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('velneo_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFilePath = path_helper.join(dbPath, filePath);

    return await openDatabase(dbFilePath, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT,
        telefono TEXT,
        direccion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        precio REAL NOT NULL,
        stock INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT NOT NULL,
        rol TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY,
        cliente_id INTEGER NOT NULL,
        usuario_id INTEGER,
        fecha TEXT NOT NULL,
        estado TEXT,
        observaciones TEXT,
        total REAL,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE lineas_pedido (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id INTEGER NOT NULL,
        articulo_id INTEGER NOT NULL,
        cantidad REAL NOT NULL,
        precio REAL NOT NULL,
        FOREIGN KEY (pedido_id) REFERENCES pedidos (id),
        FOREIGN KEY (articulo_id) REFERENCES articulos (id)
      )
    ''');
  }

  Future<int> insertarCliente(Map<String, dynamic> cliente) async {
    final db = await database;
    return await db.insert(
      'clientes',
      cliente,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerClientes([String? busqueda]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'clientes',
        where: 'nombre LIKE ? OR id LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('clientes', orderBy: 'nombre');
  }

  Future<int> insertarArticulo(Map<String, dynamic> articulo) async {
    final db = await database;
    return await db.insert(
      'articulos',
      articulo,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerArticulos([
    String? busqueda,
  ]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'articulos',
        where: 'nombre LIKE ? OR codigo LIKE ? OR id LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('articulos', orderBy: 'nombre');
  }

  Future<int> insertarUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert(
      'usuarios',
      usuario,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertarPedido(Map<String, dynamic> pedido) async {
    final db = await database;
    return await db.insert(
      'pedidos',
      pedido,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertarLineaPedido(Map<String, dynamic> linea) async {
    final db = await database;
    return await db.insert('lineas_pedido', linea);
  }

  Future<List<Map<String, dynamic>>> obtenerPedidos() async {
    final db = await database;
    return await db.query('pedidos', orderBy: 'fecha DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerLineasPedido(int pedidoId) async {
    final db = await database;
    return await db.query(
      'lineas_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<void> limpiarBaseDatos() async {
    final db = await database;
    await db.delete('lineas_pedido');
    await db.delete('pedidos');
    await db.delete('articulos');
    await db.delete('clientes');
    await db.delete('usuarios');
  }

  Future<void> cargarDatosPrueba() async {
    final db = await database;

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM clientes'),
    );

    if (count != null && count > 0) return;

    await db.insert('clientes', {
      'id': 1,
      'nombre': 'Juan Pérez',
      'email': 'juan@email.com',
      'telefono': '600123456',
      'direccion': 'Calle Mayor 1, Madrid',
    });

    await db.insert('clientes', {
      'id': 2,
      'nombre': 'María García',
      'email': 'maria@email.com',
      'telefono': '600234567',
      'direccion': 'Av. Principal 25, Barcelona',
    });

    await db.insert('clientes', {
      'id': 3,
      'nombre': 'Carlos López',
      'email': 'carlos@email.com',
      'telefono': '600345678',
      'direccion': 'Plaza España 10, Valencia',
    });

    await db.insert('articulos', {
      'id': 101,
      'codigo': 'ART001',
      'nombre': 'Portátil HP',
      'descripcion': 'Portátil HP 15.6"',
      'precio': 599.99,
      'stock': 15,
    });

    await db.insert('articulos', {
      'id': 102,
      'codigo': 'ART002',
      'nombre': 'Ratón Logitech',
      'descripcion': 'Ratón inalámbrico',
      'precio': 29.99,
      'stock': 50,
    });

    await db.insert('articulos', {
      'id': 103,
      'codigo': 'ART003',
      'nombre': 'Teclado Mecánico',
      'descripcion': 'Teclado RGB',
      'precio': 89.99,
      'stock': 30,
    });

    await db.insert('articulos', {
      'id': 104,
      'codigo': 'ART004',
      'nombre': 'Monitor LG 24"',
      'descripcion': 'Monitor Full HD',
      'precio': 179.99,
      'stock': 20,
    });

    await db.insert('articulos', {
      'id': 105,
      'codigo': 'ART005',
      'nombre': 'Webcam HD',
      'descripcion': 'Webcam 1080p',
      'precio': 49.99,
      'stock': 40,
    });
  }
}

// Servicio API
class VelneoAPIService {
  final String baseUrl;
  final String apiKey;

  VelneoAPIService(this.baseUrl, this.apiKey);

  Future<List<dynamic>> obtenerClientes() async {
    final response = await http.get(
      Uri.parse('$baseUrl/clientes'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error al obtener clientes: ${response.statusCode}');
  }

  Future<List<dynamic>> obtenerArticulos() async {
    final response = await http.get(
      Uri.parse('$baseUrl/articulos'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error al obtener artículos: ${response.statusCode}');
  }

  Future<List<dynamic>> obtenerUsuarios() async {
    final response = await http.get(
      Uri.parse('$baseUrl/usuarios'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error al obtener usuarios: ${response.statusCode}');
  }

  Future<List<dynamic>> obtenerPedidos() async {
    final response = await http.get(
      Uri.parse('$baseUrl/pedidos'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error al obtener pedidos: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> crearPedido(Map<String, dynamic> pedido) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pedidos'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: json.encode(pedido),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Error al crear pedido: ${response.statusCode}');
  }
}

// Pantalla principal
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatosPrueba();
  }

  Future<void> _cargarDatosPrueba() async {
    await DatabaseHelper.instance.cargarDatosPrueba();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const CrearPedidoScreen(),
      const ListaPedidosScreen(),
      const ConfiguracionScreen(),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
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
            icon: Icon(Icons.settings),
            label: 'Configuración',
          ),
        ],
      ),
    );
  }
}

// Pantalla de configuración
class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isSyncing = false;
  String _syncStatus = '';

  Future<void> _sincronizarDatos() async {
    if (_urlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos primero')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Conectando...';
    });

    try {
      final apiService = VelneoAPIService(
        _urlController.text,
        _apiKeyController.text,
      );
      final db = DatabaseHelper.instance;

      setState(() => _syncStatus = 'Descargando clientes...');
      final clientes = await apiService.obtenerClientes();
      for (var cliente in clientes) {
        await db.insertarCliente(cliente);
      }

      setState(() => _syncStatus = 'Descargando artículos...');
      final articulos = await apiService.obtenerArticulos();
      for (var articulo in articulos) {
        await db.insertarArticulo(articulo);
      }

      setState(() => _syncStatus = 'Descargando usuarios...');
      final usuarios = await apiService.obtenerUsuarios();
      for (var usuario in usuarios) {
        await db.insertarUsuario(usuario);
      }

      setState(() => _syncStatus = 'Descargando pedidos...');
      final pedidos = await apiService.obtenerPedidos();
      for (var pedido in pedidos) {
        await db.insertarPedido(pedido);
      }

      setState(() {
        _isSyncing = false;
        _syncStatus = '';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sincronización completa: ${clientes.length} clientes, ${articulos.length} artículos',
          ),
          backgroundColor: const Color(0xFF032458),
        ),
      );
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncStatus = '';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de sincronización: $e'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  Future<void> _limpiarDatos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar todos los datos locales?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await DatabaseHelper.instance.limpiarBaseDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos eliminados'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
    }
  }

  Future<void> _cargarDatosPrueba() async {
    await DatabaseHelper.instance.limpiarBaseDatos();
    await DatabaseHelper.instance.cargarDatosPrueba();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Datos de prueba cargados'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Conexión API Velneo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL del Servidor',
              hintText: 'https://tu-servidor.com/api',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          if (_isSyncing) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Text(
              _syncStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _sincronizarDatos,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar con Velneo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Base de Datos Local',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _cargarDatosPrueba,
            icon: const Icon(Icons.data_object),
            label: const Text('Cargar Datos de Prueba'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF032458),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _limpiarDatos,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Limpiar Base de Datos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFFF44336),
            ),
          ),
        ],
      ),
    );
  }
}

// Pantalla crear pedido
class CrearPedidoScreen extends StatefulWidget {
  const CrearPedidoScreen({super.key});

  @override
  State<CrearPedidoScreen> createState() => _CrearPedidoScreenState();
}

class _CrearPedidoScreenState extends State<CrearPedidoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];
  bool _isLoading = false;

  void _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarClienteDialog(),
    );
    if (cliente != null) {
      setState(() => _clienteSeleccionado = cliente);
    }
  }

  void _agregarLinea() async {
    final articulo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarArticuloDialog(),
    );
    if (articulo != null) {
      final lineaConPrecio = await showDialog<LineaPedidoData>(
        context: context,
        builder: (dialogContext) => EditarLineaDialog(
          articulo: articulo,
          cantidad: 1,
          precio: articulo['precio'] ?? 0.0,
        ),
      );

      if (lineaConPrecio != null) {
        setState(() {
          _lineas.add(lineaConPrecio);
        });
      }
    }
  }

  double _calcularTotal() {
    return _lineas.fold(
      0,
      (total, linea) => total + (linea.cantidad * linea.precio),
    );
  }

  Future<void> _guardarPedido() async {
    if (_clienteSeleccionado == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    if (_lineas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un artículo')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      final pedidoId = await db.insertarPedido({
        'cliente_id': _clienteSeleccionado!['id'],
        'fecha': DateTime.now().toIso8601String(),
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'estado': 'Pendiente',
        'sincronizado': 0,
      });

      for (var linea in _lineas) {
        await db.insertarLineaPedido({
          'pedido_id': pedidoId,
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
        });
      }

      setState(() => _isLoading = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Pedido guardado localmente!'),
          backgroundColor: Color(0xFF032458),
        ),
      );

      setState(() {
        _clienteSeleccionado = null;
        _observacionesController.clear();
        _lineas.clear();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo Pedido')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  child: ListTile(
                    title: Text(
                      _clienteSeleccionado?['nombre'] ?? 'Seleccionar cliente',
                      style: TextStyle(
                        fontWeight: _clienteSeleccionado != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: _clienteSeleccionado != null
                        ? Text(
                            'ID: ${_clienteSeleccionado!['id']} - ${_clienteSeleccionado!['telefono'] ?? ''}',
                          )
                        : const Text('Toca para buscar'),
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Artículos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _agregarLinea,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_lineas.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text(
                          'No hay artículos.\nToca "Agregar" para añadir productos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  ..._lineas.asMap().entries.map((entry) {
                    int index = entry.key;
                    return LineaPedidoWidget(
                      linea: entry.value,
                      onDelete: () {
                        setState(() => _lineas.removeAt(index));
                      },
                      onEdit: () async {
                        final lineaEditada = await showDialog<LineaPedidoData>(
                          context: context,
                          builder: (dialogContext) => EditarLineaDialog(
                            articulo: entry.value.articulo,
                            cantidad: entry.value.cantidad,
                            precio: entry.value.precio,
                          ),
                        );
                        if (lineaEditada != null) {
                          setState(() {
                            _lineas[index] = lineaEditada;
                          });
                        }
                      },
                      onUpdate: () {
                        setState(() {});
                      },
                    );
                  }),
                if (_lineas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFFCAD3E2),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF032458),
                            ),
                          ),
                          Text(
                            '${_calcularTotal().toStringAsFixed(2)}€',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF032458),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _guardarPedido,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                  child: const Text(
                    'GUARDAR PEDIDO',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
    );
  }
}

// Diálogo para editar línea de pedido
class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString(),
    );
    _precioController = TextEditingController(text: widget.precio.toString());
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Línea'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.articulo['nombre'],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            widget.articulo['codigo'],
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _cantidadController,
            decoration: const InputDecoration(
              labelText: 'Cantidad',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _precioController,
            decoration: const InputDecoration(
              labelText: 'Precio Unitario (€)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final cantidad = double.tryParse(_cantidadController.text) ?? 1;
            final precio = double.tryParse(_precioController.text) ?? 0;

            Navigator.pop(
              context,
              LineaPedidoData(
                articulo: widget.articulo,
                cantidad: cantidad,
                precio: precio,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// Pantalla de detalle del pedido
class DetallePedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const DetallePedidoScreen({super.key, required this.pedido});

  @override
  State<DetallePedidoScreen> createState() => _DetallePedidoScreenState();
}

class _DetallePedidoScreenState extends State<DetallePedidoScreen> {
  List<LineaDetalle> _lineas = [];
  Map<String, dynamic>? _cliente;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    final db = DatabaseHelper.instance;

    final lineasRaw = await db.obtenerLineasPedido(widget.pedido['id']);

    final clientes = await db.obtenerClientes();
    final cliente = clientes.firstWhere(
      (c) => c['id'] == widget.pedido['cliente_id'],
      orElse: () => {
        'id': widget.pedido['cliente_id'],
        'nombre': 'Cliente no encontrado',
      },
    );

    // Cargar todos los artículos una vez
    final articulos = await db.obtenerArticulos();

    // Crear objetos LineaDetalle con los datos del artículo
    final lineasConArticulo = <LineaDetalle>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {
          'id': linea['articulo_id'],
          'nombre': 'Artículo no encontrado',
          'codigo': 'N/A',
        },
      );

      lineasConArticulo.add(
        LineaDetalle(
          articuloNombre: articulo['nombre'],
          articuloCodigo: articulo['codigo'],
          cantidad: linea['cantidad'],
          precio: linea['precio'],
        ),
      );
    }

    setState(() {
      _lineas = lineasConArticulo;
      _cliente = cliente;
      _isLoading = false;
    });
  }

  String _formatearFecha(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pedido #${widget.pedido['id']}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información del Pedido',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF032458),
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildInfoRow('Cliente', _cliente?['nombre'] ?? 'N/A'),
                        _buildInfoRow(
                          'Fecha',
                          _formatearFecha(widget.pedido['fecha']),
                        ),
                        _buildInfoRow(
                          'Estado',
                          widget.pedido['estado'] ?? 'Pendiente',
                        ),
                        if (widget.pedido['observaciones'] != null &&
                            widget.pedido['observaciones']
                                .toString()
                                .isNotEmpty)
                          _buildInfoRow(
                            'Observaciones',
                            widget.pedido['observaciones'],
                          ),
                        Row(
                          children: [
                            const Text(
                              'Sincronizado: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Icon(
                              widget.pedido['sincronizado'] == 1
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: widget.pedido['sincronizado'] == 1
                                  ? const Color(0xFF032458)
                                  : const Color(0xFFF44336),
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Líneas del Pedido',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 8),
                ..._lineas.map((linea) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            linea.articuloNombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Código: ${linea.articuloCodigo}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Cantidad: ${linea.cantidad}'),
                              Text('Precio: ${linea.precio}€'),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Subtotal: ${(linea.cantidad * linea.precio).toStringAsFixed(2)}€',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF032458),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFCAD3E2),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF032458),
                          ),
                        ),
                        Text(
                          '${widget.pedido['total']?.toStringAsFixed(2) ?? '0.00'}€',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF032458),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// Clase auxiliar para líneas de detalle
class LineaDetalle {
  final String articuloNombre;
  final String articuloCodigo;
  final double cantidad;
  final double precio;

  LineaDetalle({
    required this.articuloNombre,
    required this.articuloCodigo,
    required this.cantidad,
    required this.precio,
  });
}

// Diálogo buscar cliente
class BuscarClienteDialog extends StatefulWidget {
  const BuscarClienteDialog({super.key});

  @override
  State<BuscarClienteDialog> createState() => _BuscarClienteDialogState();
}

class _BuscarClienteDialogState extends State<BuscarClienteDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _clientes = [];

  @override
  void initState() {
    super.initState();
    _buscarClientes();
  }

  Future<void> _buscarClientes([String? busqueda]) async {
    final db = DatabaseHelper.instance;
    final clientes = await db.obtenerClientes(busqueda);
    setState(() => _clientes = clientes);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar cliente',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _buscarClientes(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _buscarClientes,
            ),
          ),
          Expanded(
            child: _clientes.isEmpty
                ? const Center(
                    child: Text(
                      'No hay clientes.\nVe a Configuración y carga datos de prueba.',
                    ),
                  )
                : ListView.builder(
                    itemCount: _clientes.length,
                    itemBuilder: (listContext, index) {
                      final cliente = _clientes[index];
                      return ListTile(
                        title: Text(cliente['nombre']),
                        subtitle: Text(
                          'ID: ${cliente['id']} - ${cliente['telefono'] ?? ''}',
                        ),
                        onTap: () => Navigator.pop(context, cliente),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Diálogo buscar artículo
class BuscarArticuloDialog extends StatefulWidget {
  const BuscarArticuloDialog({super.key});

  @override
  State<BuscarArticuloDialog> createState() => _BuscarArticuloDialogState();
}

class _BuscarArticuloDialogState extends State<BuscarArticuloDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _articulos = [];

  @override
  void initState() {
    super.initState();
    _buscarArticulos();
  }

  Future<void> _buscarArticulos([String? busqueda]) async {
    final db = DatabaseHelper.instance;
    final articulos = await db.obtenerArticulos(busqueda);
    setState(() => _articulos = articulos);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar artículo',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _buscarArticulos(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _buscarArticulos,
            ),
          ),
          Expanded(
            child: _articulos.isEmpty
                ? const Center(
                    child: Text(
                      'No hay artículos.\nVe a Configuración y carga datos de prueba.',
                    ),
                  )
                : ListView.builder(
                    itemCount: _articulos.length,
                    itemBuilder: (listContext, index) {
                      final articulo = _articulos[index];
                      return ListTile(
                        title: Text(articulo['nombre']),
                        subtitle: Text(
                          '${articulo['codigo']} - ${articulo['precio']}€ (Stock: ${articulo['stock']})',
                        ),
                        onTap: () => Navigator.pop(context, articulo),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Modelo de línea de pedido
class LineaPedidoData {
  final Map<String, dynamic> articulo;
  double cantidad;
  double precio;

  LineaPedidoData({
    required this.articulo,
    required this.cantidad,
    required this.precio,
  });
}

// Widget línea de pedido
class LineaPedidoWidget extends StatelessWidget {
  final LineaPedidoData linea;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onUpdate;

  const LineaPedidoWidget({
    super.key,
    required this.linea,
    required this.onDelete,
    this.onEdit,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          linea.articulo['nombre'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${linea.articulo['codigo']} - ${linea.precio}€ x ${linea.cantidad}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF032458)),
                      onPressed: onEdit,
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFF44336)),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Subtotal: ${(linea.cantidad * linea.precio).toStringAsFixed(2)}€',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF032458),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pantalla lista de pedidos
class ListaPedidosScreen extends StatefulWidget {
  const ListaPedidosScreen({super.key});

  @override
  State<ListaPedidosScreen> createState() => _ListaPedidosScreenState();
}

class _ListaPedidosScreenState extends State<ListaPedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    final db = DatabaseHelper.instance;
    final pedidos = await db.obtenerPedidos();
    setState(() => _pedidos = pedidos);
  }

  String _formatearFecha(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarPedidos,
          ),
        ],
      ),
      body: _pedidos.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay pedidos',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _pedidos.length,
              itemBuilder: (context, index) {
                final pedido = _pedidos[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: pedido['sincronizado'] == 1
                          ? const Color(0xFF032458)
                          : const Color(0xFFF44336),
                      child: Icon(
                        pedido['sincronizado'] == 1
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      'Pedido #${pedido['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cliente ID: ${pedido['cliente_id']}'),
                        Text(_formatearFecha(pedido['fecha'])),
                        if (pedido['total'] != null)
                          Text(
                            'Total: ${pedido['total'].toStringAsFixed(2)}€',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF032458),
                            ),
                          ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        pedido['estado'] ?? 'Pendiente',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: const Color(0xFFCAD3E2),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DetallePedidoScreen(pedido: pedido),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
