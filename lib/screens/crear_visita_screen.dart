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
  DateTime? _fechaProximaVisita;
  TimeOfDay? _horaProximaVisita;
  bool _todoDia = false;
  bool _isLoading = false;
  bool _guardando = false;

  // ==================================================
  // == 🟢 1. "VISITA CERRADA" AÑADIDO ==
  // Por defecto 'false' para que el usuario decida
  // ==================================================
  bool _visitaCerrada = false;

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

  Future<void> _seleccionarFecha(
    bool esInicio, {
    bool esProxima = false,
  }) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio
          ? (_fechaInicio ?? DateTime.now())
          : (esProxima
                ? (_fechaProximaVisita ??
                      DateTime.now().add(const Duration(days: 60)))
                : (_fechaFin ?? DateTime.now())),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
    );

    if (fecha != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = fecha;
        } else if (esProxima) {
          _fechaProximaVisita = fecha;
        } else {
          _fechaFin = fecha;
        }
      });
    }
  }

  Future<void> _seleccionarHora(bool esInicio, {bool esProxima = false}) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: esInicio
          ? _horaInicio
          : (esProxima
                ? (_horaProximaVisita ?? const TimeOfDay(hour: 9, minute: 0))
                : (_horaFin ?? TimeOfDay.now())),
    );

    if (hora != null) {
      setState(() {
        if (esInicio) {
          _horaInicio = hora;
        } else if (esProxima) {
          _horaProximaVisita = hora;
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
    if (_guardando) {
      DebugLogger.log('⚠️ BLOQUEADO: Ya se está guardando una visita');
      return;
    }

    final ejecutionId = DateTime.now().millisecondsSinceEpoch;

    DebugLogger.log(
      '🚀 ========== INICIO _guardarVisita (ID: $ejecutionId) ==========',
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

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final fechaHoraInicio = DateTime(
        _fechaInicio!.year,
        _fechaInicio!.month,
        _fechaInicio!.day,
        _horaInicio.hour,
        _horaInicio.minute,
      );

      final String horaInicioStr =
          '${_horaInicio.hour.toString().padLeft(2, '0')}:${_horaInicio.minute.toString().padLeft(2, '0')}:00';
      DateTime fechaHoraFin;
      String horaFinStr;

      if (_fechaFin != null && _horaFin != null) {
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
        fechaHoraFin = fechaHoraInicio;
        horaFinStr = horaInicioStr;
      }

      // ==================================================
      // == 🟢 2. LÓGICA DE GUARDADO (BASADA EN EL TRIGGER) ==
      // ==================================================

      String? fechaProximaStr;
      String? horaProximaStr;
      bool noGenProVis;
      bool noGenTri;

      if (_visitaCerrada) {
        // --- CASO 1: VISITA CERRADA ---
        // El usuario ha marcado "Visita Cerrada"
        DebugLogger.log('📦 Lógica: Visita Cerrada');

        noGenProVis = true; // Como pide el trigger para cerrar
        noGenTri = true; // MODO SEGURO: Evita el bug 1925

        fechaProximaStr = null;
        horaProximaStr = null;
      } else {
        // --- CASO 2: VISITA ABIERTA ---
        DebugLogger.log('📦 Lógica: Visita Abierta');
        noGenProVis = false; // Como pide el trigger para generar
        noGenTri = false; // Para que entre en el trigger

        // Si el usuario PUSO fecha/hora, las usamos
        if (_fechaProximaVisita != null && _horaProximaVisita != null) {
          DebugLogger.log('📦 ...usando fecha/hora manual');
          // --- CORRECCIÓN DE FORMATO ---
          fechaProximaStr = _fechaProximaVisita!.toIso8601String().split(
            'T',
          )[0]; // "YYYY-MM-DD"
          horaProximaStr =
              '${_horaProximaVisita!.hour.toString().padLeft(2, '0')}:${_horaProximaVisita!.minute.toString().padLeft(2, '0')}:00'; // "HH:MM:SS"
        } else {
          // Si el usuario NO PUSO fecha/hora, las calculamos NOSOTROS
          // para evitar el bug de addDays() en Velneo.
          DebugLogger.log('📦 ...calculando fecha/hora por defecto (hoy + 60)');
          final fechaDefecto = DateTime.now().add(const Duration(days: 60));

          fechaProximaStr = fechaDefecto.toIso8601String().split(
            'T',
          )[0]; // "YYYY-MM-DD"
          horaProximaStr = "09:00:00"; // Hora por defecto
        }
      }

      // ==================================================

      DebugLogger.log(
        '📅 Fecha-hora construida: ${fechaHoraInicio.toIso8601String()}',
      );

      // ==================================================
      // == 🟢 3. MAPA VISITADATA (CON CAMPOS CORREGIDOS) ==
      // ==================================================
      final visitaData = {
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
        'lead_id': 0,
        'presupuesto_id': 0,
        'generado': 1, // <-- CORREGIDO A 1 (estaba en 0)
        // --- Campos de Próxima Visita (AÑADIDOS Y CORREGIDOS) ---
        'fecha_proxima_visita': fechaProximaStr, // <-- SÓLO FECHA "YYYY-MM-DD"
        'hora_proxima_visita': horaProximaStr, // <-- SÓLO HORA "HH:MM:SS"
        'no_gen_pro_vis': noGenProVis, // <-- Condicional
        'no_gen_tri': noGenTri, // <-- Condicional
      };

      // ==================================================

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

      DebugLogger.log('📤 ===== LLAMANDO A crearVisitaAgenda =====');

      final resultado = await apiService
          .crearVisitaAgenda(visitaData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              DebugLogger.log('❌ TIMEOUT (ID: $ejecutionId)');
              throw Exception('Timeout: El servidor tardó más de 45 segundos');
            },
          );

      DebugLogger.log(
        '📥 ===== RESPUESTA crearVisitaAgenda (ID: $ejecutionId) =====',
      );

      final idVelneo = resultado['id'];
      DebugLogger.log('✅ Visita creada con ID: $idVelneo');

      if (idVelneo == null) {
        throw Exception('No se recibió ID de Velneo');
      }

      DebugLogger.log('💾 Guardando visita #$idVelneo en BD local...');
      final db = DatabaseHelper.instance;

      final visitaLocal = Map<String, dynamic>.from(visitaData);
      visitaLocal['id'] = idVelneo;
      visitaLocal['sincronizado'] = 1;

      try {
        await db.insertarAgendasLote([visitaLocal]);
        DebugLogger.log('✅ Visita #$idVelneo guardada en BD local');
      } catch (e) {
        DebugLogger.log('❌ Error al guardar visita local: $e');
      }
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      DebugLogger.log('✅ ========== FIN _guardarVisita ==========');

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
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      DebugLogger.log('❌ ERROR CRÍTICO: $e');
      DebugLogger.log('❌ ========== FIN _guardarVisita (CON ERROR) ==========');

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
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                SwitchListTile(
                  title: const Text('Todo el día'),
                  value: _todoDia,
                  onChanged: (value) {
                    setState(() => _todoDia = value);
                  },
                  activeColor: const Color(0xFF032458),
                ),
                const SizedBox(height: 16),
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

                // ==================================================
                // == 🟢 4. INTERRUPTOR "VISITA CERRADA" AÑADIDO ==
                // ==================================================
                SwitchListTile(
                  title: const Text('Visita Cerrada'),
                  subtitle: Text(
                    _visitaCerrada
                        ? 'No se generará una próxima visita.'
                        : 'Se generará una próxima visita (automática o manual).',
                  ),
                  value: _visitaCerrada,
                  onChanged: (value) {
                    setState(() => _visitaCerrada = value);
                  },
                  activeColor: const Color(0xFF032458),
                ),
                const SizedBox(height: 16),

                // ==================================================
                // == 🟢 5. PRÓXIMA VISITA (AHORA CONDICIONAL) ==
                // ==================================================
                if (!_visitaCerrada)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Fecha Próxima Visita (opcional)'),
                          subtitle: Text(_formatearFecha(_fechaProximaVisita)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () =>
                              _seleccionarFecha(false, esProxima: true),
                        ),
                        if (!_todoDia)
                          ListTile(
                            title: const Text('Hora Próxima Visita (opcional)'),
                            subtitle: Text(_formatearHora(_horaProximaVisita)),
                            trailing: const Icon(Icons.access_time),
                            onTap: () =>
                                _seleccionarHora(false, esProxima: true),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            'Si dejas estos campos vacíos, se programará una visita automática en 60 días.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ==================================================
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
                  onPressed: _isLoading || _guardando ? null : _guardarVisita,
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
