import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_pedido_screen.dart';
import 'crear_pedido_screen.dart';

class ListaPedidosScreen extends StatefulWidget {
  const ListaPedidosScreen({super.key});

  @override
  State<ListaPedidosScreen> createState() => ListaPedidosScreenState();
}

class ListaPedidosScreenState extends State<ListaPedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _pedidosFiltrados = [];

  // 🟢 NUEVO: Mapa para guardar nombres de clientes (ID -> Nombre)
  final Map<int, String> _clientesNombres = {};

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
    // Sync fondo
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarFondo());
    _searchController.addListener(_filtrarPedidos);
  }

  Future<void> _sincronizarFondo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final key = prefs.getString('velneo_api_key');
      final comercialId = prefs.getInt('comercial_id');
      if (url == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        key!,
      );
      final pedidos = await api.obtenerPedidos(comercialId);

      if (pedidos.isNotEmpty) {
        await DatabaseHelper.instance.insertarPedidosLote(pedidos.cast());
        await DatabaseHelper.instance.insertarLineasPedidoLote(
          (await api.obtenerTodasLineasPedido()).cast(),
        );
        if (mounted) _cargarPedidos();
      }
    } catch (e) {
      print("Error sync pedidos: $e");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> recargarPedidos() => _cargarPedidos();

  Future<void> _cargarPedidos() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');
      final db = DatabaseHelper.instance;

      // 1. Cargar Pedidos
      var pedidos = await db.obtenerPedidos();
      if (comercialId != null) {
        pedidos = pedidos.where((p) => p['cmr'] == comercialId).toList();
      }

      // 🟢 2. Cargar Clientes para obtener nombres
      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var c in clientes) {
        _clientesNombres[c['id']] = c['nombre'];
      }

      setState(() {
        _pedidos = pedidos;
        _pedidosFiltrados = pedidos;
        _isLoading = false;
      });

      // Reaplicar filtro si hay búsqueda activa
      if (_searchController.text.isNotEmpty) _filtrarPedidos();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 🟢 Helper para obtener nombre
  String _obtenerNombreCliente(int? id) {
    if (id == null) return 'Cliente desconocido';
    return _clientesNombres[id] ?? 'Cliente no encontrado ($id)';
  }

  void _filtrarPedidos() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _pedidosFiltrados = _pedidos);
      return;
    }
    setState(() {
      _pedidosFiltrados = _pedidos.where((p) {
        final n = (p['numero'] ?? '').toString().toLowerCase();
        final o = (p['observaciones'] ?? '').toString().toLowerCase();
        final i = p['id'].toString();
        // 🟢 Buscar también por nombre de cliente
        final c = _obtenerNombreCliente(p['cliente_id']).toLowerCase();

        return n.contains(query) ||
            o.contains(query) ||
            i.contains(query) ||
            c.contains(query);
      }).toList();
    });
  }

  String _fmtFecha(String f) {
    try {
      final d = DateTime.parse(f);
      return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
      return f;
    }
  }

  Future<void> _sincronizarPendientes() async {
    final pendientes = _pedidos.where((p) => p['sincronizado'] == 0).toList();
    if (pendientes.isEmpty) return;

    setState(() => _sincronizando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final key = prefs.getString('velneo_api_key');
      if (url == null) return;
      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        key!,
      );
      final db = DatabaseHelper.instance;

      for (var p in pendientes) {
        final lineas = await db.obtenerLineasPedido(p['id']);

        // Preparar datos (incluyendo dirección si existe en local)
        final pedidoMap = {
          'cliente_id': p['cliente_id'],
          'fecha': p['fecha'],
          'observaciones': p['observaciones'],
          'total': p['total'],
          'cmr': p['cmr'],
          'serie_id': p['serie_id'],
          'direccion_entrega_id':
              p['direccion_entrega_id'], // 🟢 Enviar dirección
          'lineas': lineas
              .map(
                (l) => {
                  'articulo_id': l['articulo_id'],
                  'cantidad': l['cantidad'],
                  'precio': l['precio'],
                  'dto1': l['dto1'],
                  'dto2': l['dto2'],
                  'dto3': l['dto3'],
                  'tipo_iva': l['tipo_iva'],
                },
              )
              .toList(),
        };

        await api.crearPedido(pedidoMap);
        await db.actualizarPedidoSincronizado(p['id'], 1);
      }
      await _cargarPedidos();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sincronización exitosa')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int count = _pedidos.where((p) => p['sincronizado'] == 0).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar pedido...', // 🟢 Texto actualizado
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
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
                        : const Icon(Icons.cloud_upload, color: Colors.white),
                    onPressed: _sincronizando ? null : _sincronizarPendientes,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargarPedidos,
                  child: ListView.builder(
                    itemCount: _pedidosFiltrados.length,
                    itemBuilder: (ctx, i) {
                      final p = _pedidosFiltrados[i];
                      final sync = p['sincronizado'] == 1;

                      // 🟢 Obtener nombre cliente
                      final nombreCliente = _obtenerNombreCliente(
                        p['cliente_id'],
                      );

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            p['numero']?.toString().isNotEmpty == true
                                ? '${p['numero']}'
                                : 'Pedido #${p['id']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          // 🟢 SUBTÍTULO MEJORADO CON NOMBRE CLIENTE
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombreCliente,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              Text('${_fmtFecha(p['fecha'])}'),
                              if (p['observaciones'] != null &&
                                  p['observaciones'].toString().isNotEmpty)
                                Text(
                                  p['observaciones'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Text(
                            '${p['total']?.toStringAsFixed(2) ?? "0.00"}€',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetallePedidoScreen(pedido: p),
                            ),
                          ).then((_) => _cargarPedidos()),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
