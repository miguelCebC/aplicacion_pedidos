import 'package:flutter/material.dart';
import '../database_helper.dart';
import 'editar_presupuesto_screen.dart';

class DetallePresupuestoScreen extends StatefulWidget {
  final Map<String, dynamic> presupuesto;

  const DetallePresupuestoScreen({super.key, required this.presupuesto});

  @override
  State<DetallePresupuestoScreen> createState() =>
      _DetallePresupuestoScreenState();
}

class _DetallePresupuestoScreenState extends State<DetallePresupuestoScreen> {
  List<Map<String, dynamic>> _lineas = [];
  Map<String, dynamic>? _cliente;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    final db = DatabaseHelper.instance;

    final lineasRaw = await db.obtenerLineasPresupuesto(
      widget.presupuesto['id'],
    );

    final clientes = await db.obtenerClientes();
    final cliente = clientes.firstWhere(
      (c) => c['id'] == widget.presupuesto['cliente_id'],
      orElse: () => {
        'id': widget.presupuesto['cliente_id'],
        'nombre': 'Cliente no encontrado',
      },
    );

    final articulos = await db.obtenerArticulos();

    final lineasConArticulo = <Map<String, dynamic>>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {
          'id': linea['articulo_id'],
          'nombre': 'Artículo no encontrado',
          'codigo': 'N/A',
        },
      );

      lineasConArticulo.add({
        'articulo_nombre': articulo['nombre'],
        'articulo_codigo': articulo['codigo'],
        'cantidad': linea['cantidad'],
        'precio': linea['precio'],
        'por_descuento': linea['por_descuento'] ?? 0.0,
        'por_iva': linea['por_iva'] ?? 0.0,
      });
    }

    setState(() {
      _lineas = lineasConArticulo;
      _cliente = cliente;
      _isLoading = false;
    });
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

  String _getNombreEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'A':
        return 'Aceptado';
      case 'P':
        return 'Pendiente';
      case 'R':
        return 'Rechazado';
      default:
        return 'Desconocido';
    }
  }

  double _calcularSubtotalLinea(Map<String, dynamic> linea) {
    final cantidad = (linea['cantidad'] as num?)?.toDouble() ?? 0.0;
    final precio = (linea['precio'] as num?)?.toDouble() ?? 0.0;
    return cantidad * precio;
  }

  double _calcularTotalLinea(Map<String, dynamic> linea) {
    final subtotal = _calcularSubtotalLinea(linea);
    final descuento = (linea['por_descuento'] as num?)?.toDouble() ?? 0.0;
    final porIva = (linea['por_iva'] as num?)?.toDouble() ?? 0.0;

    final baseLinea = subtotal - (subtotal * descuento / 100);
    final ivaLinea = baseLinea * porIva / 100;

    return baseLinea + ivaLinea;
  }

  double _calcularTotalPresupuesto() {
    return _lineas.fold(0.0, (sum, linea) => sum + _calcularTotalLinea(linea));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.presupuesto['numero']?.toString().isNotEmpty == true
              ? widget.presupuesto['numero']
              : 'Presupuesto #${widget.presupuesto['id']}',
        ),
        backgroundColor: const Color(0xFF162846),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      EditarPresupuestoScreen(presupuesto: widget.presupuesto),
                ),
              );
              if (resultado == true) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Presupuesto actualizado. Cierra y vuelve a abrir para ver los cambios.',
                    ),
                    backgroundColor: Color(0xFF032458),
                  ),
                );
                // Volver a la lista de presupuestos
                Navigator.pop(context, true);
              }
            },
            tooltip: 'Editar presupuesto',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // ... resto del código sin cambios
              padding: const EdgeInsets.all(16.0),
              children: [
                // Información del presupuesto
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información del Presupuesto',
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
                          _formatearFecha(widget.presupuesto['fecha']),
                        ),
                        _buildInfoRow(
                          'Estado',
                          _getNombreEstado(widget.presupuesto['estado']),
                        ),
                        if (widget.presupuesto['observaciones'] != null &&
                            widget.presupuesto['observaciones']
                                .toString()
                                .isNotEmpty)
                          _buildInfoRow(
                            'Observaciones',
                            widget.presupuesto['observaciones'],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Líneas del presupuesto
                const Text(
                  'Líneas del Presupuesto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 8),

                if (_lineas.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text(
                          'No hay líneas en este presupuesto',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  ..._lineas.map((linea) {
                    final subtotal = _calcularSubtotalLinea(linea);
                    final descuento =
                        (linea['por_descuento'] as num?)?.toDouble() ?? 0.0;
                    final totalLinea = _calcularTotalLinea(linea);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              linea['articulo_nombre'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Código: ${linea['articulo_codigo']}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Cantidad: ${linea['cantidad']}'),
                                Text(
                                  'Precio: ${linea['precio'].toStringAsFixed(2)}€',
                                ),
                              ],
                            ),
                            if (descuento > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Descuento: ${descuento.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Total: ${totalLinea.toStringAsFixed(2)}€',
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

                // Card con el total del presupuesto
                Card(
                  color: const Color(0xFF032458).withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL PRESUPUESTO:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_calcularTotalPresupuesto().toStringAsFixed(2)}€',
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
