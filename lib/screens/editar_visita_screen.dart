import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../widgets/buscar_cliente_dialog.dart';
import 'debug_logs_screen.dart';

class EditarVisitaScreen extends StatefulWidget {
  final Map<String, dynamic> visita;

  const EditarVisitaScreen({Key? key, required this.visita}) : super(key: key);

  @override
  State<EditarVisitaScreen> createState() => _EditarVisitaScreenState();
}

class _EditarVisitaScreenState extends State<EditarVisitaScreen> {
  late TextEditingController _asuntoController;
  late TextEditingController _descripcionController;

  Map<String, dynamic>? _clienteSeleccionado;
  int? _comercialId;
  int? _tipoVisita;
  int? _campanaSeleccionada;
  DateTime? _fechaInicio;
  TimeOfDay? _horaInicio;
  DateTime? _fechaFin;
  TimeOfDay? _horaFin;
  bool _todoDia = false;
  bool _isLoading = false;
  bool _datosListos = false; // ← AÑADIR ESTA LÍNEA
  bool _guardando = false;
  List<Map<String, dynamic>> _tiposVisita = [];
  List<Map<String, dynamic>> _campanas = [];

  @override
  void initState() {
    super.initState();
    _asuntoController = TextEditingController(
      text: widget.visita['asunto'] ?? '',
    );
    _descripcionController = TextEditingController(
      text: widget.visita['descripcion'] ?? '',
    );

    _tipoVisita = widget.visita['tipo_visita'];
    _campanaSeleccionada = widget.visita['campana_id'] == 0
        ? null
        : widget.visita['campana_id'];
    _todoDia = widget.visita['todo_dia'] == 1;
    // Parsear fechas
    if (widget.visita['fecha_inicio'] != null) {
      try {
        final fechaInicio = DateTime.parse(widget.visita['fecha_inicio']);
        _fechaInicio = fechaInicio;
        _horaInicio = TimeOfDay(
          hour: fechaInicio.hour,
          minute: fechaInicio.minute,
        );
      } catch (e) {
        _fechaInicio = DateTime.now();
        _horaInicio = TimeOfDay.now();
      }
    }

    if (widget.visita['fecha_fin'] != null) {
      try {
        final fechaFin = DateTime.parse(widget.visita['fecha_fin']);
        _fechaFin = fechaFin;
        _horaFin = TimeOfDay(hour: fechaFin.hour, minute: fechaFin.minute);
      } catch (e) {
        _fechaFin = null;
        _horaFin = null;
      }
    }

    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;

    final tiposVisita = await db.obtenerTiposVisita();
    final campanas = await db.obtenerCampanas();

    // Cargar cliente
    if (widget.visita['cliente_id'] != null &&
        widget.visita['cliente_id'] != 0) {
      final clientes = await db.obtenerClientes();
      final cliente = clientes.firstWhere(
        (c) => c['id'] == widget.visita['cliente_id'],
        orElse: () => {
          'id': widget.visita['cliente_id'],
          'nombre': 'Cliente no encontrado',
        },
      );
      _clienteSeleccionado = cliente;
    }

    setState(() {
      _comercialId = prefs.getInt('comercial_id');
      _tiposVisita = tiposVisita;
      _campanas = campanas;

      // Validar que el tipo de visita existe
      if (_tipoVisita != null) {
        final tipoExiste = tiposVisita.any((tipo) => tipo['id'] == _tipoVisita);
        if (!tipoExiste) {
          print('⚠️ Tipo de visita $_tipoVisita no encontrado');
          _tipoVisita = tiposVisita.isNotEmpty ? tiposVisita.first['id'] : null;
        }
      }

      // Validar que la campaña existe
      if (_campanaSeleccionada != null) {
        final campanaExiste = campanas.any(
          (camp) => camp['id'] == _campanaSeleccionada,
        );
        if (!campanaExiste) {
          print('⚠️ Campaña $_campanaSeleccionada no encontrada');
          _campanaSeleccionada = null;
        }
      }

      _datosListos = true; // ← MARCAR COMO LISTO
    });
  }

  void _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarClienteDialog(),
    );
    if (cliente != null) {
      setState(() => _clienteSeleccionado = cliente);
    }
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio
          ? (_fechaInicio ?? DateTime.now())
          : (_fechaFin ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
    );

    if (fecha != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = fecha;
        } else {
          _fechaFin = fecha;
        }
      });
    }
  }

  Future<void> _seleccionarHora(bool esInicio) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: esInicio
          ? (_horaInicio ?? TimeOfDay.now())
          : (_horaFin ?? TimeOfDay.now()),
    );

    if (hora != null) {
      setState(() {
        if (esInicio) {
          _horaInicio = hora;
        } else {
          _horaFin = hora;
        }
      });
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No seleccionada';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearHora(TimeOfDay? hora) {
    if (hora == null) return 'No seleccionada';
    return '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _guardarCambios() async {
    // Protección contra doble clic
    if (_guardando) {
      DebugLogger.log('⚠️ BLOQUEADO: Ya se está guardando una visita');
      return;
    }

    // Generar ID único para esta ejecución
    final ejecutionId = DateTime.now().millisecondsSinceEpoch;
    DebugLogger.log(
      '🚀 ========== INICIO _guardarCambios (ID: $ejecutionId) ==========',
    );

    if (_asuntoController.text.isEmpty) {
      DebugLogger.log('❌ Asunto vacío');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El asunto es obligatorio')));
      return;
    }

    if (_clienteSeleccionado == null) {
      DebugLogger.log('❌ Cliente no seleccionado');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    // Comprobar el año
    final int anoActual = DateTime.now().year;
    if (_fechaInicio == null || _fechaInicio!.year < anoActual) {
      DebugLogger.log(
        '❌ Año inválido: ${_fechaInicio?.year} (Actual: $anoActual)',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El año de la visita (${_fechaInicio?.year}) no puede ser anterior al año actual ($anoActual)',
          ),
          backgroundColor: Colors.orange[800],
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    final db = DatabaseHelper.instance;

    try {
      // Construir fecha-hora inicio
      final fechaHoraInicio = DateTime(
        _fechaInicio!.year,
        _fechaInicio!.month,
        _fechaInicio!.day,
        _horaInicio?.hour ?? 0,
        _horaInicio?.minute ?? 0,
      );

      // ==================================================
      // == 🟢 INICIO DE LA CORRECCIÓN (FORMATO Y WORKAROUND) ==
      // ==================================================

      // Formatear la HORA INICIO como "HH:MM:SS"
      final String horaInicioStr =
          '${(_horaInicio?.hour ?? 0).toString().padLeft(2, '0')}:${(_horaInicio?.minute ?? 0).toString().padLeft(2, '0')}:00';

      DateTime fechaHoraFin;
      String horaFinStr;

      if (_fechaFin != null && _horaFin != null) {
        // 1. El usuario SÍ especificó una hora de fin
        fechaHoraFin = DateTime(
          _fechaFin!.year,
          _fechaFin!.month,
          _fechaFin!.day,
          _horaFin!.hour,
          _horaFin!.minute,
        );
        horaFinStr =
            '${_horaFin!.hour.toString().padLeft(2, '0')}:${_horaFin!.minute.toString().padLeft(2, '0')}:00';
      } else {
        // 2. El usuario NO especificó una hora de fin
        // WORKAROUND: Usamos la hora de inicio para evitar el bug de Velneo
        fechaHoraFin = fechaHoraInicio; // Usar el DateTime de INICIO
        horaFinStr = horaInicioStr; // Usar el String de HORA de INICIO
      }

      // ==================================================
      // == 🟢 FIN DE LA CORRECCIÓN (FORMATO Y WORKAROUND) ==
      // ==================================================

      // Preparar datos actualizados
      final visitaActualizada = {
        'id': widget.visita['id'],
        'nombre': widget.visita['nombre'] ?? '',
        'cliente_id': _clienteSeleccionado!['id'],
        'tipo_visita': _tipoVisita,
        'asunto': _asuntoController.text,
        'comercial_id': _comercialId,
        'campana_id': _campanaSeleccionada ?? 0,
        'fecha_inicio': fechaHoraInicio.toIso8601String(),
        'hora_inicio': horaInicioStr,
        'fecha_fin': fechaHoraFin.toIso8601String(),
        'hora_fin': horaFinStr,
        'descripcion': _descripcionController.text,
        'todo_dia': _todoDia ? 1 : 0,
        'lead_id': widget.visita['lead_id'] ?? 0,
        'presupuesto_id': widget.visita['presupuesto_id'] ?? 0,
        'generado': widget.visita['generado'] ?? 1,
        'sincronizado': 1, // Marcar como sincronizado
      };

      // ==================================================
      // == 🟢 INICIO DE LA CORRECCIÓN (LLAMADA API) ==
      // ==================================================

      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      DebugLogger.log('🌐 Conectando a: $url');

      final apiService = VelneoAPIService(url, apiKey);
      final String visitaIdVelneo = widget.visita['id'].toString();

      DebugLogger.log('📤 ===== LLAMANDO A actualizarVisitaAgenda =====');

      final resultado = await apiService
          .actualizarVisitaAgenda(visitaIdVelneo, visitaActualizada)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              DebugLogger.log('❌ TIMEOUT (ID: $ejecutionId)');
              throw Exception('Timeout: El servidor tardó más de 45 segundos');
            },
          );

      DebugLogger.log('📥 ===== RESPUESTA actualizarVisitaAgenda =====');
      DebugLogger.log('✅ Visita #${resultado['id']} actualizada en Velneo');

      // ==================================================
      // == 🟢 FIN DE LA CORRECCIÓN (LLAMADA API) ==
      // ==================================================

      // Actualizar en base de datos local
      final database = await db.database;
      await database.update(
        'agenda',
        visitaActualizada,
        where: 'id = ?',
        whereArgs: [widget.visita['id']],
      );

      DebugLogger.log('💾 Visita actualizada en BD local');

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      DebugLogger.log('✅ ========== FIN _guardarCambios ==========');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Visita #${widget.visita['id']} actualizada'),
          backgroundColor: const Color(0xFF032458),
          action: SnackBarAction(
            label: 'Ver Logs',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugLogsScreen(),
                ),
              );
            },
          ),
        ),
      );

      Navigator.pop(context, true); // Devolver true para recargar
    } catch (e) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      DebugLogger.log('❌ ERROR CRÍTICO: $e');
      DebugLogger.log(
        '❌ ========== FIN _guardarCambios (CON ERROR) ==========',
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al modificar visita'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogsScreen(),
                    ),
                  );
                },
                child: const Text('Ver Logs Completos'),
              ),
            ],
          ),
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
      appBar: AppBar(title: const Text('Editar Visita')),
      body:
          !_datosListos // ← CAMBIAR ESTA CONDICIÓN
          ? const Center(child: CircularProgressIndicator())
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Banner de sincronización
                if (widget.visita['sincronizado'] == 1)
                  Card(
                    color: const Color(0xFFE3F2FD),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF032458),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Esta visita está sincronizada con Velneo. Al editarla se marcará como pendiente de sincronización.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Asunto
                TextField(
                  controller: _asuntoController,
                  decoration: const InputDecoration(
                    labelText: 'Asunto *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),

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
                        : const Text('Toca para buscar'),
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),

                // Tipo de visita
                if (_tiposVisita.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _tipoVisita,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Visita *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    isExpanded: true,
                    items: _tiposVisita.map((tipo) {
                      return DropdownMenuItem<int>(
                        value: tipo['id'],
                        child: Text(
                          tipo['nombre'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _tipoVisita = value);
                    },
                  ),
                const SizedBox(height: 16),

                // Campaña comercial
                DropdownButtonFormField<int?>(
                  value: _campanaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Campaña Comercial (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.campaign),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin campaña'),
                    ),
                    ..._campanas.map((campana) {
                      return DropdownMenuItem<int?>(
                        value: campana['id'],
                        child: Text(
                          campana['nombre'],
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      );
                    }).toList(),
                  ],
                  onChanged: (value) {
                    setState(() => _campanaSeleccionada = value);
                  },
                ),
                const SizedBox(height: 16),

                // Todo el día
                SwitchListTile(
                  title: const Text('Todo el día'),
                  value: _todoDia,
                  onChanged: (value) {
                    setState(() => _todoDia = value);
                  },
                  activeColor: const Color(0xFF032458),
                ),
                const SizedBox(height: 16),

                // Fecha y hora inicio
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Fecha Inicio'),
                        subtitle: Text(_formatearFecha(_fechaInicio)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _seleccionarFecha(true),
                      ),
                      if (!_todoDia)
                        ListTile(
                          title: const Text('Hora Inicio'),
                          subtitle: Text(_formatearHora(_horaInicio)),
                          trailing: const Icon(Icons.access_time),
                          onTap: () => _seleccionarHora(true),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Fecha y hora fin
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Fecha Fin (opcional)'),
                        subtitle: Text(_formatearFecha(_fechaFin)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _seleccionarFecha(false),
                      ),
                      if (!_todoDia)
                        ListTile(
                          title: const Text('Hora Fin (opcional)'),
                          subtitle: Text(_formatearHora(_horaFin)),
                          trailing: const Icon(Icons.access_time),
                          onTap: () => _seleccionarHora(false),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Descripción
                TextField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Notas',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 24),

                // Botón guardar
                ElevatedButton.icon(
                  onPressed: _guardarCambios,
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR CAMBIOS'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Los cambios se sincronizarán con Velneo al pulsar el botón de sincronizar',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }
}
