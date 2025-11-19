import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'crear_editar_lead_screen.dart';
import '../services/api_service.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  List<Map<String, dynamic>> _leads = [];
  List<Map<String, dynamic>> _leadsFiltrados = [];
  final Map<int, String> _clientesNombres = {};
  final Map<int, String> _campanasNombres = {};
  bool _isLoading = true;
  int? _comercialId;
  String _comercialNombre = 'Sin comercial';
  final TextEditingController _searchController = TextEditingController();
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _searchController.addListener(_filtrarLeads);
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
      final comercialNombre =
          prefs.getString('comercial_nombre') ?? 'Sin comercial';

      final db = DatabaseHelper.instance;

      // Cargar leads del comercial
      final leads = await db.obtenerLeads(comercialId);

      // Cargar clientes para mostrar nombres
      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var cliente in clientes) {
        _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
      }

      // Cargar campañas para mostrar nombres
      final campanas = await db.obtenerCampanas();
      _campanasNombres.clear();
      for (var campana in campanas) {
        _campanasNombres[campana['id'] as int] = campana['nombre'] as String;
      }

      setState(() {
        _comercialId = comercialId;
        _comercialNombre = comercialNombre;
        _leads = leads;
        _leadsFiltrados = leads;
        _isLoading = false;
      });
    } catch (e) {
      print('Error al cargar leads: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filtrarLeads() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _leadsFiltrados = _leads;
      } else {
        _leadsFiltrados = _leads.where((lead) {
          final asunto = (lead['asunto'] ?? '').toString().toLowerCase();
          final estado = (lead['estado'] ?? '').toString().toLowerCase();
          final clienteNombre = _obtenerNombreCliente(
            lead['cliente_id'],
          ).toLowerCase();

          return asunto.contains(query) ||
              estado.contains(query) ||
              clienteNombre.contains(query);
        }).toList();
      }
    });
  }

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null || clienteId == 0) return 'Sin cliente';
    return _clientesNombres[clienteId] ?? 'Cliente desconocido';
  }

  String _obtenerNombreCampana(int? campanaId) {
    if (campanaId == null || campanaId == 0) return 'Sin campaña';
    return _campanasNombres[campanaId] ?? 'Campaña desconocida';
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return 'Sin fecha';
    try {
      final fecha = DateTime.parse(fechaStr);
      return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    } catch (e) {
      return fechaStr;
    }
  }

  Color _getColorEstado(String? estado) {
    final estadoInt = int.tryParse(estado?.toString() ?? '1') ?? 1;
    switch (estadoInt) {
      case 1: // Sin Asignar
        return Colors.blue;
      case 2: // Asignado
        return Colors.orange;
      case 3: // Finalizado
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getIconoEstado(String? estado) {
    final estadoInt = int.tryParse(estado?.toString() ?? '1') ?? 1;
    switch (estadoInt) {
      case 1: // Sin Asignar
        return Icons.fiber_new;
      case 2: // Asignado
        return Icons.assignment_ind;
      case 3: // Finalizado
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  String _getNombreEstado(String? estado) {
    final estadoInt = int.tryParse(estado?.toString() ?? '1') ?? 1;
    switch (estadoInt) {
      case 1:
        return 'Sin Asignar';
      case 2:
        return 'Asignado';
      case 3:
        return 'Finalizado';
      default:
        return 'Desconocido';
    }
  }

  void _mostrarDetalleLead(Map<String, dynamic> lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        _getIconoEstado(lead['estado']),
                        color: _getColorEstado(lead['estado']),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lead['asunto'] ?? 'Sin asunto',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Estado: ${_getNombreEstado(lead['estado'])}',
                              style: TextStyle(
                                color: _getColorEstado(lead['estado']),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _buildInfoRow(
                    Icons.business,
                    'Cliente',
                    _obtenerNombreCliente(lead['cliente_id']),
                  ),
                  _buildInfoRow(
                    Icons.campaign,
                    'Campaña',
                    _obtenerNombreCampana(lead['campana_id']),
                  ),
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Fecha',
                    _formatearFecha(lead['fecha']),
                  ),
                  _buildInfoRow(
                    Icons.event_available,
                    'Fecha Alta',
                    _formatearFecha(lead['fecha_alta']),
                  ),
                  _buildInfoRow(
                    Icons.event_note,
                    'Agendado',
                    lead['agendado'] == 1
                        ? 'Sí (ID: ${lead['agenda_id']})'
                        : 'No',
                  ),
                  _buildInfoRow(
                    Icons.send,
                    'Enviado',
                    lead['enviado'] == 1 ? 'Sí' : 'No',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Descripción',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      lead['descripcion'] ?? 'Sin descripción',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        final resultado = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CrearEditarLeadScreen(lead: lead),
                          ),
                        );
                        if (resultado == true) {
                          _cargarDatos();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar Lead'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF032458),
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF032458)),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
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
                      hintText: 'Buscar leads...',
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
                    onPressed: _sincronizando ? null : _sincronizarLeads,
                    tooltip: 'Sincronizar leads',
                  ),
                ),
              ],
            ),
          ),
          // Lista de leads
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _leadsFiltrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchController.text.isEmpty
                              ? Icons.people_outline
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No hay leads'
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
                    itemCount: _leadsFiltrados.length,
                    itemBuilder: (context, index) {
                      final lead = _leadsFiltrados[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _mostrarDetalleLead(lead),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: _getColorEstado(
                                      lead['estado'],
                                    ).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getIconoEstado(lead['estado']),
                                    color: _getColorEstado(lead['estado']),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lead['asunto'] ?? 'Sin asunto',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _obtenerNombreCliente(
                                          lead['cliente_id'],
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
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getColorEstado(
                                                lead['estado'],
                                              ).withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _getNombreEstado(lead['estado']),
                                              style: TextStyle(
                                                color: _getColorEstado(
                                                  lead['estado'],
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CrearEditarLeadScreen(),
            ),
          );
          if (resultado == true) {
            _cargarDatos();
          }
        },
        backgroundColor: const Color(0xFF032458),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Lead'),
      ),
    );
  }

  Future<void> _sincronizarLeads() async {
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

      // Descargar TODOS los leads (sin filtro de comercial)
      final leadsLista = await apiService.obtenerLeads();
      await db.limpiarLeads();
      await db.insertarLeadsLote(leadsLista.cast<Map<String, dynamic>>());

      setState(() => _sincronizando = false);
      await _cargarDatos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${leadsLista.length} leads sincronizados'),
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
