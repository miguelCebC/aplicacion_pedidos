import 'package:flutter/material.dart';
import '../database_helper.dart';
import 'editar_visita_screen.dart';
import 'debug_logs_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class DetalleVisitaScreen extends StatefulWidget {
  final Map<String, dynamic> visita;

  const DetalleVisitaScreen({super.key, required this.visita});

  @override
  State<DetalleVisitaScreen> createState() => _DetalleVisitaScreenState();
}

class _DetalleVisitaScreenState extends State<DetalleVisitaScreen> {
  Map<String, dynamic>? _cliente;
  Map<String, dynamic>? _comercial;
  Map<String, dynamic>? _campana;
  Map<String, dynamic>? _lead;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    final db = DatabaseHelper.instance;

    // Cargar cliente
    if (widget.visita['cliente_id'] != null &&
        widget.visita['cliente_id'] != 0) {
      final clientes = await db.obtenerClientes();
      _cliente = clientes.firstWhere(
        (c) => c['id'] == widget.visita['cliente_id'],
        orElse: () => {
          'id': widget.visita['cliente_id'],
          'nombre': 'Cliente no encontrado',
        },
      );
    }

    // Cargar comercial
    if (widget.visita['comercial_id'] != null &&
        widget.visita['comercial_id'] != 0) {
      final comerciales = await db.obtenerComerciales();
      _comercial = comerciales.firstWhere(
        (c) => c['id'] == widget.visita['comercial_id'],
        orElse: () => {
          'id': widget.visita['comercial_id'],
          'nombre': 'Comercial no encontrado',
        },
      );
    }

    // Cargar campaña
    if (widget.visita['campana_id'] != null &&
        widget.visita['campana_id'] != 0) {
      final campanas = await db.obtenerCampanas();
      _campana = campanas.firstWhere(
        (c) => c['id'] == widget.visita['campana_id'],
        orElse: () => {
          'id': widget.visita['campana_id'],
          'nombre': 'Campaña no encontrada',
        },
      );
    }

    // Cargar lead
    if (widget.visita['lead_id'] != null && widget.visita['lead_id'] != 0) {
      final leads = await db.obtenerLeads();
      _lead = leads.firstWhere(
        (l) => l['id'] == widget.visita['lead_id'],
        orElse: () => {
          'id': widget.visita['lead_id'],
          'asunto': 'Lead no encontrado',
        },
      );
    }

    setState(() => _isLoading = false);
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return 'No especificada';
    try {
      final fecha = DateTime.parse(fechaStr);
      return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    } catch (e) {
      return fechaStr;
    }
  }

  String _formatearHora(String? horaStr) {
    if (horaStr == null || horaStr.isEmpty) return 'No especificada';
    try {
      final hora = DateTime.parse(horaStr);
      return '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return horaStr;
    }
  }

  Future<String> _obtenerTipoVisita(int? tipoId) async {
    if (tipoId == null) return 'No especificado';

    final db = DatabaseHelper.instance;
    final tipos = await db.obtenerTiposVisita();

    final tipo = tipos.firstWhere(
      (t) => t['id'] == tipoId,
      orElse: () => {'nombre': 'Tipo $tipoId'},
    );

    return tipo['nombre'];
  }

  Future<void> _editarVisita() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarVisitaScreen(visita: widget.visita),
      ),
    );

    if (resultado == true) {
      // Recargar detalles después de editar
      await _cargarDetalles();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Visita actualizada. Recarga el calendario para ver los cambios.',
          ),
          backgroundColor: Color(0xFF032458),
        ),
      );
    }
  }

  Future<void> _eliminarVisita() async {
    // 1. Pedir confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar esta visita?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      DebugLogger.log('🚫 Eliminación cancelada por el usuario');
      return;
    }

    // Generar ID único para esta ejecución
    final ejecutionId = DateTime.now().millisecondsSinceEpoch;
    DebugLogger.log(
      '🚀 ========== INICIO _eliminarVisita (ID: $ejecutionId) ==========',
    );

    setState(() => _isLoading = true);

    try {
      // 2. Conectar a la API
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
      final String visitaIdVelneo = widget.visita['id'].toString();

      // 3. Llamar a la API para eliminar en Velneo
      await apiService
          .deleteVisitaAgenda(visitaIdVelneo)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              DebugLogger.log('❌ TIMEOUT (ID: $ejecutionId)');
              throw Exception('Timeout: El servidor tardó más de 45 segundos');
            },
          );
      DebugLogger.log('✅ Visita #$visitaIdVelneo eliminada de Velneo');

      // 4. Eliminar de la base de datos local
      final db = DatabaseHelper.instance;
      await db.eliminarVisita(widget.visita['id']);
      DebugLogger.log('✅ Visita #${widget.visita['id']} eliminada de BD local');

      setState(() => _isLoading = false);

      if (!mounted) return;

      DebugLogger.log('✅ ========== FIN _eliminarVisita ==========');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Visita eliminada'),
          backgroundColor: Color(0xFF032458),
        ),
      );

      // 5. Volver al calendario (devolviendo 'true' para refrescar)
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isLoading = false);
      DebugLogger.log('❌ ERROR CRÍTICO al eliminar: $e');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al eliminar visita'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
        title: const Text('Detalle de Visita'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              _editarVisita();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              _eliminarVisita();
            },
            tooltip: 'Eliminar visita',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<String>(
              future: _obtenerTipoVisita(widget.visita['tipo_visita']),
              builder: (context, snapshot) {
                final tipoVisita = snapshot.data ?? 'Cargando...';

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Información básica
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.event,
                                  color: Color(0xFF032458),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Información General',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            const SizedBox(height: 8),
                            _buildInfoRow('ID', '#${widget.visita['id']}'),
                            _buildInfoRow(
                              'Asunto',
                              widget.visita['asunto'] ?? 'Sin asunto',
                            ),
                            _buildInfoRow('Tipo', tipoVisita),
                            if (widget.visita['sincronizado'] == 1)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.cloud_done,
                                    color: Color(0xFF032458),
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Sincronizado con Velneo'),
                                ],
                              )
                            else
                              const Row(
                                children: [
                                  Icon(
                                    Icons.cloud_off,
                                    color: Color(0xFFFFC107),
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Pendiente de sincronizar'),
                                ],
                              ),
                            if (widget.visita['todo_dia'] == 1)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Chip(
                                  label: Text('Todo el día'),
                                  backgroundColor: Color(0xFFCAD3E2),
                                  avatar: Icon(Icons.wb_sunny, size: 16),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // ... resto del código igual ...
                    const SizedBox(height: 16),

                    // Fechas y horas
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Color(0xFF032458),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Fechas y Horarios',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Fecha Inicio',
                              _formatearFecha(widget.visita['fecha_inicio']),
                            ),
                            _buildInfoRow(
                              'Hora Inicio',
                              _formatearHora(widget.visita['hora_inicio']),
                            ),
                            if (widget.visita['fecha_fin'] != null)
                              _buildInfoRow(
                                'Fecha Fin',
                                _formatearFecha(widget.visita['fecha_fin']),
                              ),
                            if (widget.visita['hora_fin'] != null)
                              _buildInfoRow(
                                'Hora Fin',
                                _formatearHora(widget.visita['hora_fin']),
                              ),
                            if (widget.visita['fecha_proxima_visita'] != null &&
                                widget.visita['fecha_proxima_visita']
                                    .toString()
                                    .isNotEmpty)
                              _buildInfoRow(
                                'Próxima Visita',
                                _formatearFecha(
                                  widget.visita['fecha_proxima_visita'],
                                ),
                              ),
                            if (widget.visita['hora_proxima_visita'] != null &&
                                widget.visita['hora_proxima_visita']
                                    .toString()
                                    .isNotEmpty)
                              _buildInfoRow(
                                'Hora Próxima',
                                _formatearHora(
                                  widget.visita['hora_proxima_visita'],
                                ),
                              ),
                            if (widget.visita['fecha_proxima_visita'] != null)
                              _buildInfoRow(
                                'Próxima Visita',
                                _formatearFecha(
                                  widget.visita['fecha_proxima_visita'],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Descripción
                    if (widget.visita['descripcion'] != null &&
                        widget.visita['descripcion'].toString().isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.description,
                                    color: Color(0xFF032458),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Descripción',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF032458),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              const SizedBox(height: 8),
                              Text(
                                widget.visita['descripcion'],
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Relaciones
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.link,
                                  color: Color(0xFF032458),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Información Relacionada',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            const SizedBox(height: 8),
                            if (_cliente != null)
                              _buildInfoRow('Cliente', _cliente!['nombre']),
                            if (_comercial != null)
                              _buildInfoRow('Comercial', _comercial!['nombre']),
                            if (_campana != null)
                              _buildInfoRow('Campaña', _campana!['nombre']),
                            if (_lead != null)
                              _buildInfoRow(
                                'Lead',
                                _lead!['asunto'] ?? 'Sin asunto',
                              ),
                            if (widget.visita['presupuesto_id'] != null &&
                                widget.visita['presupuesto_id'] != 0)
                              _buildInfoRow(
                                'Presupuesto',
                                '#${widget.visita['presupuesto_id']}',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
