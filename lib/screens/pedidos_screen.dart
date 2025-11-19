import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_pedido_screen.dart';
import 'crear_pedido_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _pedidosFiltrados = [];
  final Map<int, String> _clientesNombres = {};
  bool _isLoading = true;
  bool _sincronizando = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _searchController.addListener(_filtrarPedidos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    final db = DatabaseHelper.instance;

    // Cargar pedidos
    final pedidos = await db.obtenerPedidos();

    // Cargar clientes para mostrar nombres
    final clientes = await db.obtenerClientes();
    _clientesNombres.clear();
    for (var cliente in clientes) {
      _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
    }

    setState(() {
      _pedidos = pedidos;
      _pedidosFiltrados = pedidos;
      _isLoading = false;
    });
  }

  void _filtrarPedidos() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _pedidosFiltrados = _pedidos;
      } else {
        _pedidosFiltrados = _pedidos.where((pedido) {
          final clienteNombre = _obtenerNombreCliente(
            pedido['cliente_id'],
          ).toLowerCase();
          final observaciones = (pedido['observaciones'] ?? '')
              .toString()
              .toLowerCase();
          final numero = (pedido['numero'] ?? '').toString();

          return clienteNombre.contains(query) ||
              observaciones.contains(query) ||
              numero.contains(query);
        }).toList();
      }
    });
  }

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null) return 'Sin cliente';
    return _clientesNombres[clienteId] ?? 'Cliente desconocido';
  }

  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return 'Sin fecha';
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (e) {
      return fecha;
    }
  }

  Future<void> _sincronizarPedidosPendientes() async {
    final pedidosPendientes = _pedidos
        .where((p) => p['sincronizado'] == 0)
        .toList();

    if (pedidosPendientes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay pedidos pendientes de sincronizar'),
          backgroundColor: Color(0xFF032458),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sincronizar Pedidos'),
        content: Text(
          '¿Deseas sincronizar ${pedidosPendientes.length} pedido(s) pendiente(s) con Velneo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF032458),
            ),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _sincronizando = true);
    await Future.delayed(const Duration(milliseconds: 100));

    int exitosos = 0;
    int fallidos = 0;
    final errores = <String>[];

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      for (var pedido in pedidosPendientes) {
        try {
          final lineas = await db.obtenerLineasPedido(pedido['id']);

          if (lineas.isEmpty) {
            throw Exception('El pedido no tiene líneas');
          }

          final pedidoData = {
            'cliente_id': pedido['cliente_id'],
            'fecha': pedido['fecha'],
            'observaciones': pedido['observaciones'] ?? '',
            'total': pedido['total'],
            'lineas': lineas
                .map(
                  (linea) => {
                    'articulo_id': linea['articulo_id'],
                    'cantidad': linea['cantidad'],
                    'precio': linea['precio'],
                  },
                )
                .toList(),
          };

          await apiService
              .crearPedido(pedidoData)
              .timeout(const Duration(seconds: 45));

          await db.actualizarPedidoSincronizado(pedido['id'], 1);
          exitosos++;

          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          fallidos++;
          final errorMsg = e.toString().replaceAll('Exception: ', '');
          errores.add('Pedido #${pedido['id']}: $errorMsg');
        }
      }

      setState(() => _sincronizando = false);
      await _cargarDatos();

      if (!mounted) return;

      if (fallidos == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $exitosos pedido(s) sincronizado(s) correctamente',
            ),
            backgroundColor: const Color(0xFF032458),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Resultado de Sincronización'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('✅ Exitosos: $exitosos'),
                  Text('❌ Fallidos: $fallidos'),
                  if (errores.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Errores:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...errores.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(e, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _sincronizando = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFF44336),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // LÍNEA 325-349: Reemplazar todo el Widget build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Barra de búsqueda con botón de sincronización
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar pedidos...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botón de sincronización
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF032458),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: _sincronizando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.sync, color: Colors.white),
                    onPressed: _sincronizando ? null : _sincronizarPedidos,
                    tooltip: 'Sincronizar pedidos',
                  ),
                ),
              ],
            ),
          ),
          // Lista de pedidos
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pedidosFiltrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchController.text.isEmpty
                              ? Icons.shopping_cart_outlined
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No hay pedidos'
                              : 'No se encontraron resultados',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _pedidosFiltrados.length,
                    itemBuilder: (context, index) {
                      final pedido = _pedidosFiltrados[index];
                      final esSincronizado = pedido['sincronizado'] == 1;
                      final numeroPed = pedido['numero']?.toString() ?? '';
                      final textoNumero = numeroPed.isNotEmpty
                          ? numeroPed
                          : 'Pedido #${pedido['id']}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    DetallePedidoScreen(pedido: pedido),
                              ),
                            );
                            _cargarDatos();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: esSincronizado
                                        ? const Color(
                                            0xFF032458,
                                          ).withOpacity(0.1)
                                        : const Color(
                                            0xFFF44336,
                                          ).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    esSincronizado
                                        ? Icons.check_circle
                                        : Icons.pending,
                                    color: esSincronizado
                                        ? const Color(0xFF032458)
                                        : const Color(0xFFF44336),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        textoNumero,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _obtenerNombreCliente(
                                          pedido['cliente_id'],
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 14,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatearFecha(pedido['fecha']),
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CrearPedidoScreen()),
          );
          if (resultado == true) {
            _cargarDatos();
          }
        },
        backgroundColor: const Color(0xFF032458),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _sincronizarPedidos() async {
    setState(() => _sincronizando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      // Descargar TODOS los pedidos (sin filtro de comercial)
      final pedidosLista = await apiService.obtenerPedidos();
      await db.limpiarPedidos();
      await db.insertarPedidosLote(pedidosLista.cast<Map<String, dynamic>>());

      // Descargar TODAS las líneas de pedido
      final lineasPedido = await apiService.obtenerTodasLineasPedido();
      await db.insertarLineasPedidoLote(
        lineasPedido.cast<Map<String, dynamic>>(),
      );

      setState(() => _sincronizando = false);
      await _cargarDatos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${pedidosLista.length} pedidos sincronizados'),
          backgroundColor: const Color(0xFF032458),
        ),
      );
    } catch (e) {
      setState(() => _sincronizando = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }
}
