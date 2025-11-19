import 'dart:convert'; // 🟢 IMPORTANTE: Necesario para jsonEncode
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';

class EditarPresupuestoScreen extends StatefulWidget {
  final Map<String, dynamic> presupuesto;

  const EditarPresupuestoScreen({super.key, required this.presupuesto});

  @override
  State<EditarPresupuestoScreen> createState() =>
      _EditarPresupuestoScreenState();
}

class _EditarPresupuestoScreenState extends State<EditarPresupuestoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];
  bool _isLoading = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  // ==============================================================
  // 🟢 NUEVO MÉTODO: MOSTRAR JSON EN POPUP (DEBUG) - VERSIÓN PRESUPUESTOS
  // ==============================================================
  Future<void> _mostrarDebugJson() async {
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faltan datos para generar el JSON')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');

    // 1. Simular el JSON de Cabecera
    final cabeceraJson = {
      'emp': '1',
      'emp_div': '1',
      'clt': _clienteSeleccionado!['id'],
      'cmr': comercialId, // O widget.presupuesto['comercial_id']
      'obs': _observacionesController.text,
      'est': widget.presupuesto['estado'] ?? 'P',
    };

    // 2. Simular el JSON de las Líneas
    // Nota: En presupuestos los campos suelen ser 'vta_pre', 'can', 'pre'
    final lineasJson = _lineas.map((l) {
      return {
        'vta_pre': widget.presupuesto['id'],
        'emp': '1',
        'art': l.articulo['id'],
        'can': l
            .cantidad, // En pedidos es 'can_ped', en presupuestos suele ser 'can'
        'pre': l.precio,
        // 🔥 CAMPO CLAVE VERIFICADO:
        'reg_iva_vta': l.tipoIva,
      };
    }).toList();

    // Convertir a String bonito
    final encoder = const JsonEncoder.withIndent('  ');
    final headerString = encoder.convert(cabeceraJson);
    final linesString = encoder.convert(lineasJson);

    if (!mounted) return;

    // Mostrar Popup
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔍 DEBUG: JSON Presupuesto'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CABECERA (PUT/POST):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  width: double.infinity,
                  child: Text(
                    headerString,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'LÍNEAS (${lineasJson.length}) (POST individuales):',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  width: double.infinity,
                  child: Text(
                    linesString,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
  // ==============================================================

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      // Cargar cliente
      final clientes = await db.obtenerClientes();
      final cliente = clientes.firstWhere(
        (c) => c['id'] == widget.presupuesto['cliente_id'],
        orElse: () => {
          'id': widget.presupuesto['cliente_id'],
          'nombre': 'Cliente no encontrado',
        },
      );

      // Cargar líneas del presupuesto
      final lineasRaw = await db.obtenerLineasPresupuesto(
        widget.presupuesto['id'],
      );
      final articulos = await db.obtenerArticulos();

      final lineasCargadas = <LineaPedidoData>[];
      for (var linea in lineasRaw) {
        final articulo = articulos.firstWhere(
          (a) => a['id'] == linea['articulo_id'],
          orElse: () => {
            'id': linea['articulo_id'],
            'nombre': 'Artículo no encontrado',
            'codigo': 'N/A',
            'precio': 0.0,
          },
        );

        // 🟢 CORRECCIÓN: Leer IVA de la BD correctamente
        String tipoIvaDb = linea['tipo_iva']?.toString() ?? 'G';

        lineasCargadas.add(
          LineaPedidoData(
            articulo: articulo,
            cantidad: (linea['cantidad'] as num).toDouble(),
            precio: (linea['precio'] as num).toDouble(),
            descuento: (linea['por_descuento'] as num?)?.toDouble() ?? 0.0,
            tipoIva: tipoIvaDb, // Usar el valor real
          ),
        );
      }

      setState(() {
        _clienteSeleccionado = cliente;
        _observacionesController.text =
            widget.presupuesto['observaciones'] ?? '';
        _lineas.addAll(lineasCargadas);
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando datos: $e');
      setState(() => _isLoading = false);
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
          tipoIva: 'G', // Valor por defecto
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

  Future<void> _guardarCambios() async {
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

      // Preparar datos del presupuesto para actualizar en la API
      final presupuestoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'comercial_id': comercialId,
        'observaciones': _observacionesController.text,
        'estado': widget.presupuesto['estado'] ?? 'P',
        // Preparamos las líneas con el campo correcto para API
        'lineas': _lineas
            .map(
              (linea) => {
                'articulo_id': linea.articulo['id'],
                'cantidad': linea.cantidad,
                'precio': linea.precio,
                'tipo_iva': linea
                    .tipoIva, // 🟢 Campo corregido (reg_iva_vta se mapea en api_service)
              },
            )
            .toList(),
      };

      // Actualizar en Velneo API
      await apiService
          .actualizarPresupuesto(widget.presupuesto['id'], presupuestoData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () =>
                throw Exception('Timeout: El servidor tardó demasiado'),
          );

      // Actualizar en BD local
      final db = DatabaseHelper.instance;
      await db.actualizarPresupuesto(widget.presupuesto['id'], {
        'cliente_id': _clienteSeleccionado!['id'],
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'sincronizado': 1,
      });

      // Actualizar líneas en BD local
      await db.eliminarLineasPresupuesto(widget.presupuesto['id']);

      for (var linea in _lineas) {
        await db.insertarLineaPresupuesto({
          'presupuesto_id': widget.presupuesto['id'],
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
          'por_descuento': linea.descuento,
          'por_iva': linea.porcentajeIva,
          'tipo_iva': linea.tipoIva, // 🟢 Guardar IVA en local
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ Presupuesto actualizado correctamente en el servidor',
          ),
          backgroundColor: Color(0xFF032458),
          duration: Duration(seconds: 2),
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
        title: Text('Editar Presupuesto #${widget.presupuesto['id']}'),
        backgroundColor: const Color(0xFF162846),
        actions: [
          // 🟢 BOTÓN DE DEBUG JSON (NUEVO)
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.orange),
            onPressed: _mostrarDebugJson,
            tooltip: 'Ver JSON a enviar',
          ),
        ],
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
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardarCambios,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF032458),
                      foregroundColor: Colors.white,
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Guardar Cambios',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
