import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/models.dart';

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

    final articulos = await db.obtenerArticulos();

    final lineasConArticulo = <LineaDetalle>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {
          'id': linea['articulo_id'],
          'nombre': 'ArtÃ­culo no encontrado',
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
      appBar: AppBar(title: Text('Pedido ${widget.pedido['numero']}')),
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
