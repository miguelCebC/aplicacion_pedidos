import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_presupuesto_screen.dart';
import 'crear_presupuesto_screen.dart';

class PresupuestosScreen extends StatefulWidget {
  const PresupuestosScreen({super.key});

  @override
  State<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends State<PresupuestosScreen> {
  List<Map<String, dynamic>> _presupuestos = [];
  List<Map<String, dynamic>> _presupuestosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  final Map<int, String> _clientesNombres = {}; // 👈 ESTA LÍNEA

  bool _isLoading = true;
  bool _sincronizando = false;

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

      final db = DatabaseHelper.instance;
      List<Map<String, dynamic>> presupuestos = await db.obtenerPresupuestos();

      // Filtrar por comercial si está configurado
      if (comercialId != null) {
        presupuestos = presupuestos
            .where((p) => p['comercial_id'] == comercialId)
            .toList();
      }

      // Cargar nombres de clientes
      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var cliente in clientes) {
        _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
      }

      // Ordenar por fecha descendente
      presupuestos.sort((a, b) {
        try {
          final fechaA = DateTime.parse(a['fecha'] ?? '');
          final fechaB = DateTime.parse(b['fecha'] ?? '');
          return fechaB.compareTo(fechaA);
        } catch (e) {
          return 0;
        }
      });

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
      _presupuestosFiltrados = _presupuestos.where((presupuesto) {
        final numero = presupuesto['numero']?.toString().toLowerCase() ?? '';
        final estado = _getNombreEstado(presupuesto['estado']).toLowerCase();
        final observaciones =
            presupuesto['observaciones']?.toString().toLowerCase() ?? '';
        return numero.contains(query) ||
            estado.contains(query) ||
            observaciones.contains(query);
      }).toList();
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
                      hintText: 'Buscar presupuestos...',
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

                const SizedBox(width: 12),
                // Botón de sincronización (el que ya tienes)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF032458),
                    borderRadius: BorderRadius.circular(12),
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
                    onPressed: _sincronizando ? null : _sincronizarPresupuestos,
                    tooltip: 'Sincronizar presupuestos',
                  ),
                ),
              ],
            ),
          ),
          // Lista de presupuestos
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _presupuestosFiltrados.isEmpty
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
                      final numeroPre = presupuesto['numero']?.toString() ?? '';
                      final textoNumero = numeroPre.isNotEmpty
                          ? numeroPre
                          : 'Presupuesto #${presupuesto['id']}';

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
                                builder: (context) => DetallePresupuestoScreen(
                                  presupuesto: presupuesto,
                                ),
                              ),
                            );
                            _cargarDatos();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Ícono de estado con badge debajo
                                Column(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: _getColorEstado(
                                          presupuesto['estado'],
                                        ).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getIconoEstado(presupuesto['estado']),
                                        color: _getColorEstado(
                                          presupuesto['estado'],
                                        ),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getColorEstado(
                                          presupuesto['estado'],
                                        ).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _getNombreEstado(presupuesto['estado']),
                                        style: TextStyle(
                                          color: _getColorEstado(
                                            presupuesto['estado'],
                                          ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Información del presupuesto
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
                                          presupuesto['cliente_id'],
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
                                            _formatearFecha(
                                              presupuesto['fecha'],
                                            ),
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
                                // Flecha de navegación
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
            MaterialPageRoute(
              builder: (context) => const CrearPresupuestoScreen(),
            ),
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

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null) return 'Sin cliente';
    return _clientesNombres[clienteId] ?? 'Cliente desconocido';
  }

  Future<void> _sincronizarPresupuestos() async {
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

      // Descargar TODOS los presupuestos (sin filtro de comercial)
      final presupuestosLista = await apiService.obtenerPresupuestos();

      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        presupuestosLista.cast<Map<String, dynamic>>(),
      );

      // Descargar TODAS las líneas de presupuesto
      final lineasPresupuesto = await apiService
          .obtenerTodasLineasPresupuesto();
      await db.insertarLineasPresupuestoLote(
        lineasPresupuesto.cast<Map<String, dynamic>>(),
      );

      setState(() => _sincronizando = false);

      // IMPORTANTE: Recargar los datos después de sincronizar
      await _cargarDatos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${presupuestosLista.length} presupuestos sincronizados',
          ),
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
