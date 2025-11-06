import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';

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
  bool _guardando = false;

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarClienteDialog(),
    );
    if (cliente != null) {
      setState(() => _clienteSeleccionado = cliente);
    }
  }

  Future<void> _agregarLinea() async {
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

  void _eliminarLinea(int index) {
    setState(() {
      _lineas.removeAt(index);
    });
  }

  Future<void> _editarLinea(int index) async {
    final lineaActual = _lineas[index];
    final lineaEditada = await showDialog<LineaPedidoData>(
      context: context,
      builder: (dialogContext) => EditarLineaDialog(
        articulo: lineaActual.articulo,
        cantidad: lineaActual.cantidad,
        precio: lineaActual.precio,
      ),
    );

    if (lineaEditada != null) {
      setState(() {
        _lineas[index] = lineaEditada;
      });
    }
  }

  double _calcularTotal() {
    return _lineas.fold(
      0,
      (total, linea) => total + (linea.cantidad * linea.precio),
    );
  }

  Future<void> _guardarPedido() async {
    if (_guardando) return;

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    if (_lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un artículo')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';
      final comercialId = prefs.getInt('comercial_id');

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);

      final pedidoVelneoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'fecha': DateTime.now().toIso8601String(),
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'lineas': _lineas
            .map(
              (linea) => {
                'articulo_id': linea.articulo['id'],
                'cantidad': linea.cantidad,
                'precio': linea.precio,
              },
            )
            .toList(),
      };

      if (comercialId != null) {
        pedidoVelneoData['cmr'] = comercialId;
      }

      final resultado = await apiService
          .crearPedido(pedidoVelneoData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception(
              'Timeout: El servidor tardó demasiado en responder',
            ),
          );

      final pedidoIdVelneo = resultado['id'];

      // Guardar en BD local
      final db = DatabaseHelper.instance;
      await db.insertarPedido({
        'id': pedidoIdVelneo,
        'cliente_id': _clienteSeleccionado!['id'],
        'cmr': comercialId,
        'fecha': DateTime.now().toIso8601String(),
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'estado': 'Sincronizado',
        'sincronizado': 1,
      });

      for (var linea in _lineas) {
        await db.insertarLineaPedido({
          'pedido_id': pedidoIdVelneo,
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Pedido #$pedidoIdVelneo creado correctamente'),
          backgroundColor: const Color(0xFF032458),
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceAll('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Pedido'),
        backgroundColor: const Color(0xFF162846),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Cliente
                Card(
                  child: ListTile(
                    title: Text(
                      _clienteSeleccionado?['nombre'] ??
                          'Seleccionar cliente *',
                      style: TextStyle(
                        fontWeight: _clienteSeleccionado != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: _clienteSeleccionado != null
                        ? Text('ID: ${_clienteSeleccionado!['id']}')
                        : null,
                    leading: const Icon(Icons.business),
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),

                // Observaciones
                TextField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                // Título y botón agregar artículo
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF032458),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Lista de artículos
                if (_lineas.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No hay artículos',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Toca "Agregar" para añadir productos',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._lineas.asMap().entries.map((entry) {
                    final index = entry.key;
                    final linea = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF032458).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Color(0xFF032458),
                          ),
                        ),
                        title: Text(
                          linea.articulo['nombre'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Código: ${linea.articulo['codigo']}'),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Cantidad: ${linea.cantidad}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Precio: ${linea.precio.toStringAsFixed(2)}€',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${(linea.cantidad * linea.precio).toStringAsFixed(2)}€',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Eliminar',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editarLinea(index);
                                } else if (value == 'delete') {
                                  _eliminarLinea(index);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                // Total
                if (_lineas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF032458).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF032458),
                        width: 2,
                      ),
                    ),
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
                          '${_calcularTotal().toStringAsFixed(2)} €',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF032458),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Botón guardar
                ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarPedido,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Crear Pedido'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '* Campos obligatorios',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
