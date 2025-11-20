import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';

class CrearPresupuestoScreen extends StatefulWidget {
  const CrearPresupuestoScreen({super.key});

  @override
  State<CrearPresupuestoScreen> createState() => _CrearPresupuestoScreenState();
}

class _CrearPresupuestoScreenState extends State<CrearPresupuestoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];

  // Variables para Series
  List<Map<String, dynamic>> _series = [];
  int? _serieSeleccionadaId;

  bool _isLoading = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarSeries();
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarSeries() async {
    try {
      final series = await DatabaseHelper.instance.obtenerSeries(tipo: 'V');
      if (mounted) {
        setState(() {
          _series = series;
          if (_series.isNotEmpty) {
            _serieSeleccionadaId = _series[0]['id'];
          }
        });
      }
    } catch (e) {
      print('Error cargando series: $e');
    }
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
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero selecciona un cliente')),
      );
      return;
    }

    final articulo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarArticuloDialog(),
    );

    if (articulo != null) {
      final db = DatabaseHelper.instance;
      final precioInfo = await db.obtenerPrecioYDescuento(
        _clienteSeleccionado!['id'],
        articulo['id'],
        articulo['precio'] ?? 0.0,
      );

      if (!mounted) return;

      final lineaConPrecio = await showDialog<LineaPedidoData>(
        context: context,
        builder: (dialogContext) => EditarLineaDialog(
          articulo: articulo,
          cantidad: 1,
          precio: precioInfo['precio']!,
          descuento: precioInfo['descuento']!,
          tipoIva: 'G',
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
        descuento: lineaActual.descuento,
        tipoIva: lineaActual.tipoIva,
      ),
    );

    if (lineaEditada != null) {
      setState(() {
        _lineas[index] = lineaEditada;
      });
    }
  }

  double _calcularBaseImponible() {
    return _lineas.fold(0, (total, linea) {
      final subtotal = linea.cantidad * linea.precio;
      final descuento = subtotal * (linea.descuento / 100);
      return total + (subtotal - descuento);
    });
  }

  double _calcularTotalIva() {
    return _lineas.fold(0, (totalIva, linea) {
      final subtotal = linea.cantidad * linea.precio;
      final descuento = subtotal * (linea.descuento / 100);
      final baseLinea = subtotal - descuento;
      final ivaLinea = baseLinea * (linea.porcentajeIva / 100);
      return totalIva + ivaLinea;
    });
  }

  double _calcularTotal() {
    return _calcularBaseImponible() + _calcularTotalIva();
  }

  Future<void> _guardarPresupuesto() async {
    if (_guardando) return;

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    if (_serieSeleccionadaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una serie de facturación')),
      );
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

      final presupuestoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'comercial_id': comercialId,
        'serie_id': _serieSeleccionadaId,
        'fecha': DateTime.now().toIso8601String(),
        'numero': '',
        'estado': 'P',
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'lineas': _lineas
            .map(
              (linea) => {
                'articulo_id': linea.articulo['id'],
                'cantidad': linea.cantidad,
                'precio': linea.precio,
                'por_dto': linea.descuento,
                'reg_iva_vta': linea.tipoIva,
              },
            )
            .toList(),
      };

      final resultado = await apiService.crearPresupuesto(presupuestoData);
      final presupuestoId = resultado['id'];

      final db = DatabaseHelper.instance;
      await db.insertarPresupuesto({
        'id': presupuestoId,
        'cliente_id': _clienteSeleccionado!['id'],
        'comercial_id': comercialId,
        'serie_id': _serieSeleccionadaId,
        'fecha': DateTime.now().toIso8601String(),
        'numero': '',
        'estado': 'P',
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'sincronizado': 1,
      });

      for (var linea in _lineas) {
        await db.insertarLineaPresupuesto({
          'presupuesto_id': presupuestoId,
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
          'por_descuento': linea.descuento,
          'por_iva': linea.porcentajeIva,
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Presupuesto #$presupuestoId creado correctamente'),
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
        title: const Text('Crear Presupuesto'),
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

                // 🟢 DROPDOWN DE SERIES CORREGIDO
                if (_series.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: DropdownButtonFormField<int>(
                        isExpanded: true, // 🟢 EVITAR OVERFLOW
                        decoration: const InputDecoration(
                          labelText: 'Serie de Facturación',
                          border: InputBorder.none,
                          icon: Icon(Icons.folder_open, color: Colors.grey),
                        ),
                        initialValue: _serieSeleccionadaId,
                        items: _series.map((serie) {
                          return DropdownMenuItem<int>(
                            value: serie['id'],
                            child: Text(
                              serie['nombre'],
                              overflow:
                                  TextOverflow.ellipsis, // 🟢 CORTAR TEXTO
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _serieSeleccionadaId = value;
                          });
                        },
                      ),
                    ),
                  ),
                if (_series.isNotEmpty) const SizedBox(height: 16),

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
                        foregroundColor: Colors.white,
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
                    final subtotal = linea.cantidad * linea.precio;
                    final descuento = subtotal * (linea.descuento / 100);
                    final baseLinea = subtotal - descuento;
                    final ivaLinea = baseLinea * (linea.porcentajeIva / 100);
                    final totalLinea = baseLinea + ivaLinea;

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
                        subtitle: Text(
                          '${linea.articulo['codigo']} - ${linea.cantidad} x ${linea.precio.toStringAsFixed(2)}€'
                          '${linea.descuento > 0 ? ' (-${linea.descuento}%)' : ''}'
                          '\nIVA: ${linea.tipoIva} (${linea.porcentajeIva}%)',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${totalLinea.toStringAsFixed(2)}€',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                                if (linea.descuento > 0 ||
                                    linea.porcentajeIva > 0)
                                  Text(
                                    'Base: ${baseLinea.toStringAsFixed(2)}€',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'editar',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'eliminar',
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
                                if (value == 'editar') {
                                  _editarLinea(index);
                                } else if (value == 'eliminar') {
                                  _eliminarLinea(index);
                                }
                              },
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // Card de totales
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  color: const Color(0xFF032458).withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Base Imponible:'),
                            Text(
                              '${_calcularBaseImponible().toStringAsFixed(2)}€',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('IVA:'),
                            Text(
                              '${_calcularTotalIva().toStringAsFixed(2)}€',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL:',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
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
                      ],
                    ),
                  ),
                ),

                // Botón guardar
                ElevatedButton(
                  onPressed: _guardando ? null : _guardarPresupuesto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF032458),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'GUARDAR PRESUPUESTO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
