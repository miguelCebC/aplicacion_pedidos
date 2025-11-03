import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';
import '../widgets/linea_pedido_widget.dart';

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
      // Obtener configuración de Velneo
      final prefs = await SharedPreferences.getInstance();
      String url =
          prefs.getString('velneo_url') ??
          'tecerp.nunsys.com:4311/TORRAL/TecERPv7_dat_dat/v1';
      final String apiKey = prefs.getString('velneo_api_key') ?? '1234';
      final comercialId = prefs.getInt('comercial_id'); // ← AÑADIR AQUÍ

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      print('🚀 Iniciando creación de pedido...');

      // 1. CREAR PEDIDO EN VELNEO PRIMERO
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

      // Agregar comercial si está configurado
      if (comercialId != null) {
        pedidoVelneoData['cmr'] = comercialId;
        print('🎯 Comercial asignado al pedido: $comercialId');
      } else {
        print('⚠️ No hay comercial configurado');
      }

      // Crear en Velneo con timeout
      final resultado = await apiService
          .crearPedido(pedidoVelneoData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception(
              'Timeout: El servidor tardó demasiado en responder',
            ),
          );

      final pedidoIdVelneo = resultado['id'];
      print('✓ Pedido creado en Velneo con ID: $pedidoIdVelneo');

      // 2. GUARDAR EN BASE DE DATOS LOCAL CON EL ID DE VELNEO
      final db = DatabaseHelper.instance;

      await db.insertarPedido({
        'id': pedidoIdVelneo, // ← Usar el ID de Velneo
        'cliente_id': _clienteSeleccionado!['id'],
        'cmr': comercialId, // ← AÑADIR AQUÍ
        'fecha': DateTime.now().toIso8601String(),
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'estado': 'Sincronizado',
        'sincronizado': 1, // Ya está sincronizado
      });
      // 3. GUARDAR LÃNEAS EN LOCAL
      for (var linea in _lineas) {
        await db.insertarLineaPedido({
          'pedido_id': pedidoIdVelneo, //  Usar el ID de Velneo
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
        });
      }

      setState(() => _isLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Pedido #$pedidoIdVelneo creado y sincronizado\n'
            '${resultado['lineas_creadas']} líneas guardadas',
          ),
          backgroundColor: const Color(0xFF032458),
          duration: const Duration(seconds: 3),
        ),
      );

      // Limpiar formulario
      setState(() {
        _clienteSeleccionado = null;
        _observacionesController.clear();
        _lineas.clear();
      });
    } catch (e) {
      setState(() => _isLoading = false);

      print('âŒ Error al crear pedido: $e');

      if (!mounted) return;

      // Mostrar error detallado
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al crear pedido'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No se pudo crear el pedido en Velneo:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  e.toString().replaceAll('Exception: ', ''),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Verifica:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• Conexión a internet'),
                const Text('• Configuración de URL y API Key'),
                const Text('• Que el cliente existe en Velneo'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // Navegar a configuración
                DefaultTabController.of(context).animateTo(2);
              },
              child: const Text('Ir a Configuración'),
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
        title: const Text('Nuevo Pedido'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Creando pedido en Velneo...',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Esto puede tardar unos segundos',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
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
                  onPressed: _isLoading ? null : _guardarPedido,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                  child: const Text(
                    'CREAR PEDIDO EN VELNEO',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El pedido se creará directamente en Velneo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
    );
  }
}
