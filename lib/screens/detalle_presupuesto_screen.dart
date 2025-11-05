import 'package:flutter/material.dart';
import '../database_helper.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.presupuesto['numero'] ??
              'Presupuesto #${widget.presupuesto['id']}',
        ),
        backgroundColor: const Color(0xFF162846),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información del Presupuesto',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          'Cliente',
                          _cliente?['nombre'] ?? 'Desconocido',
                        ),
                        _buildInfoRow(
                          'Fecha',
                          _formatearFecha(widget.presupuesto['fecha']),
                        ),
                        if (widget.presupuesto['fecha_validez'] != null)
                          _buildInfoRow(
                            'Validez',
                            _formatearFecha(
                              widget.presupuesto['fecha_validez'],
                            ),
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
                const Text(
                  'Líneas del Presupuesto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._lineas.map((linea) {
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
                        linea['articulo_nombre'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Código: ${linea['articulo_codigo']}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${linea['cantidad']} x ${linea['precio'].toStringAsFixed(2)}€',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${(linea['cantidad'] * linea['precio']).toStringAsFixed(2)}€',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF032458),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF032458),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${(widget.presupuesto['total'] ?? 0).toStringAsFixed(2)} €',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}
