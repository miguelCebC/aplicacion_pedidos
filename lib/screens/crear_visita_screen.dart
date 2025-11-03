import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../widgets/buscar_cliente_dialog.dart';
import 'debug_logs_screen.dart';

class CrearVisitaScreen extends StatefulWidget {
  final DateTime? fechaSeleccionada;

  const CrearVisitaScreen({Key? key, this.fechaSeleccionada}) : super(key: key);

  @override
  State<CrearVisitaScreen> createState() => _CrearVisitaScreenState();
}

class _CrearVisitaScreenState extends State<CrearVisitaScreen> {
  final _asuntoController = TextEditingController();
  final _descripcionController = TextEditingController();

  Map<String, dynamic>? _clienteSeleccionado;
  int? _comercialId;
  int? _tipoVisita;
  int? _campanaSeleccionada;
  DateTime? _fechaInicio;
  TimeOfDay _horaInicio = TimeOfDay.now();
  DateTime? _fechaFin;
  TimeOfDay? _horaFin;
  bool _todoDia = false;
  bool _isLoading = false;

  List<Map<String, dynamic>> _tiposVisita = [];
  List<Map<String, dynamic>> _campanas = [];

  @override
  void initState() {
    super.initState();
    _fechaInicio = widget.fechaSeleccionada ?? DateTime.now();
    _fechaFin = _fechaInicio;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;

    final tiposVisita = await db.obtenerTiposVisita();
    final campanas = await db.obtenerCampanas();

    setState(() {
      _comercialId = prefs.getInt('comercial_id');
      _tiposVisita = tiposVisita;
      _campanas = campanas;

      // Seleccionar primer tipo por defecto
      if (_tiposVisita.isNotEmpty) {
        _tipoVisita = _tiposVisita.first['id'];
      }
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
      initialTime: esInicio ? _horaInicio : (_horaFin ?? TimeOfDay.now()),
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

  Future<void> _guardarVisita() async {
    DebugLogger.log('🚀 Iniciando creación de visita');

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

    if (_comercialId == null) {
      DebugLogger.log('❌ Comercial no configurado');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay comercial asignado. Ve a Configuración'),
        ),
      );
      return;
    }

    if (_tipoVisita == null) {
      DebugLogger.log('❌ Tipo de visita no seleccionado');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un tipo de visita')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      TimeOfDay horaInicioFinal = _horaInicio;

      DebugLogger.log('📅 Fecha inicio: ${_fechaInicio!.toString()}');
      DebugLogger.log(
        '⏰ Hora inicio: ${horaInicioFinal.hour}:${horaInicioFinal.minute}',
      );

      final fechaHoraInicio = DateTime(
        _fechaInicio!.year,
        _fechaInicio!.month,
        _fechaInicio!.day,
        horaInicioFinal.hour,
        horaInicioFinal.minute,
      );

      DebugLogger.log(
        '📅 Fecha-hora construida: ${fechaHoraInicio.toIso8601String()}',
      );

      DateTime? fechaHoraFin;
      if (_fechaFin != null && _horaFin != null) {
        fechaHoraFin = DateTime(
          _fechaFin!.year,
          _fechaFin!.month,
          _fechaFin!.day,
          _horaFin!.hour,
          _horaFin!.minute,
        );
        DebugLogger.log('📅 Fecha-hora fin: ${fechaHoraFin.toIso8601String()}');
      }

      final visitaData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'tipo_visita': _tipoVisita,
        'asunto': _asuntoController.text,
        'comercial_id': _comercialId,
        'campana_id': _campanaSeleccionada ?? 0,
        'fecha_inicio': fechaHoraInicio.toIso8601String(),
        'hora_inicio': fechaHoraInicio.toIso8601String(),
        'fecha_fin': fechaHoraFin?.toIso8601String(),
        'hora_fin': fechaHoraFin?.toIso8601String(),
        'descripcion': _descripcionController.text,
        'todo_dia': _todoDia ? 1 : 0,
        'lead_id': 0,
        'presupuesto_id': 0,
        'generado': 1,
      };

      DebugLogger.log(
        '📦 Datos preparados: Cliente=${visitaData['cliente_id']}, Tipo=${visitaData['tipo_visita']}',
      );

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

      DebugLogger.log('📤 Enviando visita a Velneo...');

      final resultado = await apiService
          .crearVisitaAgenda(visitaData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              DebugLogger.log('❌ TIMEOUT después de 45 segundos');
              throw Exception('Timeout: El servidor tardó más de 45 segundos');
            },
          );

      final idVelneo = resultado['id'];
      DebugLogger.log('✅ Visita creada con ID: $idVelneo');

      if (idVelneo == null) {
        throw Exception('No se recibió ID de Velneo');
      }
      DebugLogger.log('🔄 Sincronizando agenda del comercial $_comercialId...');
      final db = DatabaseHelper.instance;

      try {
        await db.limpiarAgenda();
        DebugLogger.log('🗑️ Agenda local limpiada');

        // IMPORTANTE: Asegurarse de descargar TODAS las páginas
        final visitasComercial = await apiService.obtenerAgenda(_comercialId);
        DebugLogger.log(
          '📥 Descargadas ${visitasComercial.length} visitas de la API',
        );

        if (visitasComercial.isEmpty) {
          DebugLogger.log(
            '⚠️ WARNING: No se descargaron visitas. Reintentando sin filtro...',
          );
          final todasVisitas = await apiService.obtenerAgenda(null);
          DebugLogger.log(
            '📥 Total visitas sin filtro: ${todasVisitas.length}',
          );

          // Filtrar manualmente
          final visitasFiltradas = todasVisitas
              .where((v) => v['comercial_id'] == _comercialId)
              .toList();
          DebugLogger.log(
            '📥 Filtradas para comercial $_comercialId: ${visitasFiltradas.length}',
          );

          if (visitasFiltradas.isNotEmpty) {
            await db.insertarAgendasLote(
              visitasFiltradas.cast<Map<String, dynamic>>(),
            );
          }
        } else {
          await db.insertarAgendasLote(
            visitasComercial.cast<Map<String, dynamic>>(),
          );
        }

        DebugLogger.log('💾 Visitas guardadas en BD local');

        // Verificar que se guardó
        final visitasEnBD = await db.obtenerAgenda(_comercialId);
        DebugLogger.log(
          '✅ Verificado: ${visitasEnBD.length} visitas en BD local',
        );

        // Buscar específicamente la visita recién creada
        final visitaNueva = visitasEnBD
            .where((v) => v['id'] == idVelneo)
            .toList();
        if (visitaNueva.isNotEmpty) {
          DebugLogger.log('✅ Visita #$idVelneo encontrada en BD local');
        } else {
          DebugLogger.log('⚠️ Visita #$idVelneo NO encontrada en BD local');
        }
      } catch (e) {
        DebugLogger.log('❌ Error al sincronizar: $e');
      }
      setState(() => _isLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Visita #$idVelneo creada'),
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

      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      setState(() => _isLoading = false);

      DebugLogger.log('❌ ERROR CRÍTICO: $e');
      DebugLogger.log('Stack: ${stackTrace.toString().substring(0, 200)}');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al crear visita'),
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
      appBar: AppBar(
        title: const Text('Nueva Visita'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugLogsScreen(),
                ),
              );
            },
            tooltip: 'Ver logs de depuración',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Creando visita...'),
                  const SizedBox(height: 8),
                  Text(
                    'Intentando sincronizar con Velneo',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                    isExpanded: true, // ← AÑADIR ESTA LÍNEA
                    items: _tiposVisita.map((tipo) {
                      return DropdownMenuItem<int>(
                        value: tipo['id'],
                        child: Text(
                          tipo['nombre'],
                          overflow:
                              TextOverflow.ellipsis, // ← AÑADIR ESTA LÍNEA
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _tipoVisita = value);
                    },
                  )
                else
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No hay tipos de visita. Sincroniza los datos en Configuración.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
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
                  isExpanded: true, // ← AÑADIR ESTA LÍNEA
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
                          maxLines: 2, // ← AÑADIR ESTA LÍNEA
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
                  onPressed: _guardarVisita,
                  icon: const Icon(Icons.save),
                  label: const Text('CREAR VISITA'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'La visita se intentará sincronizar automáticamente con Velneo',
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
