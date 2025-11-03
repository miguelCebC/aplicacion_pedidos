import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../widgets/buscar_cliente_dialog.dart';

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
    if (_asuntoController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El asunto es obligatorio')));
      return;
    }

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    if (_comercialId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay comercial asignado. Ve a Configuración'),
        ),
      );
      return;
    }

    if (_tipoVisita == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un tipo de visita')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Validar hora de inicio
      if (_horaInicio == null) {
        _horaInicio = TimeOfDay.now();
      }

      // Construir fecha-hora inicio
      final fechaHoraInicio = DateTime(
        _fechaInicio!.year,
        _fechaInicio!.month,
        _fechaInicio!.day,
        _horaInicio!.hour,
        _horaInicio!.minute,
      );

      // Construir fecha-hora fin si existe
      DateTime? fechaHoraFin;
      if (_fechaFin != null && _horaFin != null) {
        fechaHoraFin = DateTime(
          _fechaFin!.year,
          _fechaFin!.month,
          _fechaFin!.day,
          _horaFin!.hour,
          _horaFin!.minute,
        );
      }

      // Preparar datos de la visita
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

      print('🚀 Subiendo visita a Velneo...');

      // 1. SUBIR A VELNEO PRIMERO
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
      final resultado = await apiService
          .crearVisitaAgenda(visitaData)
          .timeout(const Duration(seconds: 45));

      final idVelneo = resultado['id'];
      print('✅ Visita creada en Velneo con ID: $idVelneo');

      // 2. SINCRONIZAR SOLO LAS VISITAS DEL COMERCIAL
      print('🔄 Sincronizando agenda del comercial $_comercialId...');
      final db = DatabaseHelper.instance;

      // Limpiar y recargar agenda del comercial
      await db.limpiarAgenda();
      final visitasComercial = await apiService.obtenerAgenda(_comercialId);
      await db.insertarAgendasLote(
        visitasComercial.cast<Map<String, dynamic>>(),
      );

      print(
        '✅ Agenda sincronizada: ${visitasComercial.length} visitas del comercial',
      );

      setState(() => _isLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Visita #$idVelneo creada y sincronizada correctamente',
          ),
          backgroundColor: const Color(0xFF032458),
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isLoading = false);

      print('❌ Error al crear visita: $e');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al crear visita'),
          content: SingleChildScrollView(
            child: Text(e.toString().replaceAll('Exception: ', '')),
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
      appBar: AppBar(title: const Text('Nueva Visita')),
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
