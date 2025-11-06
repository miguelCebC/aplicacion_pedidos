import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'crear_presupuesto_screen.dart';
import 'detalle_presupuesto_screen.dart';

class PresupuestosScreen extends StatefulWidget {
  const PresupuestosScreen({super.key});

  @override
  State<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends State<PresupuestosScreen> {
  List<Map<String, dynamic>> _presupuestos = [];
  List<Map<String, dynamic>> _presupuestosFiltrados = [];
  final Map<int, String> _clientesNombres = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _searchController.addListener(_filtrarPresupuestos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isNotEmpty && apiKey.isNotEmpty) {
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
        }

        // Sincronizar desde Velneo
        final apiService = VelneoAPIService(url, apiKey);
        final presupuestosVelneo = await apiService.obtenerPresupuestos();

        // Guardar en BD local
        final db = DatabaseHelper.instance;
        await db.insertarPresupuestosLote(
          presupuestosVelneo.cast<Map<String, dynamic>>(),
        );
      }

      // Cargar desde BD local
      final db = DatabaseHelper.instance;
      List<Map<String, dynamic>> presupuestos = await db.obtenerPresupuestos();

      // Filtrar por comercial si está seleccionado
      if (comercialId != null) {
        presupuestos = presupuestos
            .where((p) => p['comercial_id'] == comercialId)
            .toList();
      }

      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var cliente in clientes) {
        _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
      }

      setState(() {
        _presupuestos = presupuestos;
        _presupuestosFiltrados = presupuestos;
        _isLoading = false;
      });
    } catch (e) {
      print('Error al cargar presupuestos: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filtrarPresupuestos() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _presupuestosFiltrados = _presupuestos;
      } else {
        _presupuestosFiltrados = _presupuestos.where((presupuesto) {
          final clienteNombre = _obtenerNombreCliente(
            presupuesto['cliente_id'],
          ).toLowerCase();
          final numero = (presupuesto['numero'] ?? '').toString().toLowerCase();
          final observaciones = (presupuesto['observaciones'] ?? '')
              .toString()
              .toLowerCase();

          return clienteNombre.contains(query) ||
              numero.contains(query) ||
              observaciones.contains(query);
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

  Color _getColorEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'A':
        return Colors.green;
      case 'P':
        return Colors.orange;
      case 'R':
        return Colors.red;
      default:
        return Colors.grey;
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

  IconData _getIconoEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'A':
        return Icons.check_circle;
      case 'P':
        return Icons.pending;
      case 'R':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
        backgroundColor: const Color(0xFF162846),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
            tooltip: 'Recargar lista',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar presupuestos por cliente, número...',
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
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.request_quote, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_presupuestosFiltrados.length} presupuesto(s) encontrado(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _presupuestosFiltrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchController.text.isEmpty
                                    ? Icons.request_quote_outlined
                                    : Icons.search_off,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'No hay presupuestos'
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
                          itemCount: _presupuestosFiltrados.length,
                          itemBuilder: (context, index) {
                            final presupuesto = _presupuestosFiltrados[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          DetallePresupuestoScreen(
                                            presupuesto: presupuesto,
                                          ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            _getIconoEstado(
                                              presupuesto['estado'],
                                            ),
                                            color: _getColorEstado(
                                              presupuesto['estado'],
                                            ),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            presupuesto['numero'] ??
                                                'Presupuesto #${presupuesto['id']}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getColorEstado(
                                                presupuesto['estado'],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _getNombreEstado(
                                                presupuesto['estado'],
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.business,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              _obtenerNombreCliente(
                                                presupuesto['cliente_id'],
                                              ),
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatearFecha(
                                              presupuesto['fecha'],
                                            ),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (presupuesto['observaciones'] !=
                                              null &&
                                          presupuesto['observaciones']
                                              .toString()
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          presupuesto['observaciones'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const Divider(),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Total:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                '${(presupuesto['total'] ?? 0).toStringAsFixed(2)} €',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF032458),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.chevron_right,
                                                color: Colors.grey,
                                              ),
                                            ],
                                          ),
                                        ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CrearPresupuestoScreen(),
            ),
          );
          if (resultado == true) {
            _cargarDatos();
          }
        },
        backgroundColor: const Color(0xFF032458),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Presupuesto'),
      ),
    );
  }
}
