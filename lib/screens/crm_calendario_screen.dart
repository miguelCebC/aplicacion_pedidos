import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'detalle_visita_screen.dart';
import 'crear_visita_screen.dart';
import 'leads_screen.dart';
import 'presupuestos_screen.dart';
import '../services/api_service.dart';

class CRMCalendarioScreen extends StatefulWidget {
  const CRMCalendarioScreen({super.key});

  @override
  State<CRMCalendarioScreen> createState() => _CRMCalendarioScreenState();
}

class _CRMCalendarioScreenState extends State<CRMCalendarioScreen>
    with AutomaticKeepAliveClientMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int? _comercialId;
  String _comercialNombre = 'Sin comercial asignado';
  Map<DateTime, List<Map<String, dynamic>>> _eventos = {};
  List<Map<String, dynamic>> _eventosDelDia = [];
  bool _isLoading = true;
  bool _sincronizando = false;
  int _visitasPendientes = 0;

  // Mapa para cachear nombres de clientes
  final Map<int, String> _clientesNombres = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _cargarComercialYEventos();
  }

  Future<void> _cargarComercialYEventos() async {
    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');
    final comercialNombre =
        prefs.getString('comercial_nombre') ?? 'Sin comercial asignado';

    setState(() {
      _comercialId = comercialId;
      _comercialNombre = comercialNombre;
    });

    if (comercialId != null) {
      await _cargarEventos();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarEventos() async {
    if (_comercialId == null) return;

    setState(() => _isLoading = true);

    final db = DatabaseHelper.instance;
    final agendas = await db.obtenerAgenda(_comercialId);
    final pendientes = await db.contarAgendasPendientes(_comercialId);

    // Cargar todos los clientes para cachear sus nombres
    final clientes = await db.obtenerClientes();
    _clientesNombres.clear();
    for (var cliente in clientes) {
      _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
    }

    final Map<DateTime, List<Map<String, dynamic>>> eventosAgrupados = {};

    for (var agenda in agendas) {
      if (agenda['fecha_inicio'] != null &&
          agenda['fecha_inicio'].toString().isNotEmpty) {
        try {
          final fecha = DateTime.parse(agenda['fecha_inicio']);
          final fechaSoloDate = DateTime(fecha.year, fecha.month, fecha.day);

          if (eventosAgrupados[fechaSoloDate] == null) {
            eventosAgrupados[fechaSoloDate] = [];
          }
          eventosAgrupados[fechaSoloDate]!.add(agenda);
        } catch (e) {
          print('⚠️ Error parseando fecha: ${agenda['fecha_inicio']} - $e');
        }
      }
    }

    setState(() {
      _eventos = eventosAgrupados;
      _visitasPendientes = pendientes;
      _isLoading = false;
    });

    _cargarEventosDelDia(_selectedDay ?? _focusedDay);
  }

  void _cargarEventosDelDia(DateTime dia) {
    final diaKey = DateTime(dia.year, dia.month, dia.day);
    final eventos = _eventos[diaKey] ?? [];

    // Ordenar eventos por hora_inicio
    eventos.sort((a, b) {
      final horaA = a['hora_inicio']?.toString() ?? '';
      final horaB = b['hora_inicio']?.toString() ?? '';

      // Si alguna hora está vacía, poner al final
      if (horaA.isEmpty) return 1;
      if (horaB.isEmpty) return -1;

      return horaA.compareTo(horaB);
    });

    setState(() {
      _eventosDelDia = eventos;
    });
  }

  List<Map<String, dynamic>> _getEventosParaDia(DateTime dia) {
    final diaKey = DateTime(dia.year, dia.month, dia.day);
    return _eventos[diaKey] ?? [];
  }

  String _formatearHora(String? horaStr) {
    if (horaStr == null || horaStr.isEmpty) return '--:--';
    try {
      // Primero intentar parsear como fecha completa ISO
      if (horaStr.contains('T') || horaStr.contains('-')) {
        final dt = DateTime.parse(horaStr);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }

      // Si es formato "HH:MM:SS" o "HH:MM"
      if (horaStr.contains(':')) {
        final parts = horaStr.split(':');
        if (parts.length >= 2) {
          final hora = int.parse(parts[0]).toString().padLeft(2, '0');
          final minuto = int.parse(parts[1]).toString().padLeft(2, '0');
          return '$hora:$minuto';
        }
      }

      return '--:--';
    } catch (e) {
      print('⚠️ Error formateando hora: $horaStr - $e');
      return '--:--';
    }
  }

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null) return 'Sin cliente';
    return _clientesNombres[clienteId] ?? 'Cliente desconocido';
  }

  Future<void> _crearNuevaVisita() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CrearVisitaScreen(fechaSeleccionada: _selectedDay ?? _focusedDay),
      ),
    );

    if (resultado == true) {
      await _cargarEventos();
    }
  }

  Future<void> _sincronizarVisitas() async {
    if (_comercialId == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (_sincronizando) return;

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

      print(
        '📄 Sincronizando agenda del comercial $_comercialId desde Velneo...',
      );

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      await db.limpiarAgenda();
      final visitasComercial = await apiService.obtenerAgenda(_comercialId);
      await db.insertarAgendasLote(
        visitasComercial.cast<Map<String, dynamic>>(),
      );

      print('✅ Agenda sincronizada: ${visitasComercial.length} visitas');

      setState(() => _sincronizando = false);
      await _cargarEventos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${visitasComercial.length} visitas sincronizadas'),
          backgroundColor: const Color(0xFF032458),
        ),
      );
    } catch (e) {
      setState(() {
        _sincronizando = false;
        _isLoading = false;
      });

      print('❌ Error al sincronizar: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _comercialId == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay comercial asignado',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      // Navegar a configuración (índice 3)
                      // Necesitarás ajustar esto según tu implementación
                    },
                    child: const Text('Ir a Configuración'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: _getEventosParaDia,
                  locale: 'es_ES',
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarStyle: const CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Color(0xFF162846),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _cargarEventosDelDia(selectedDay);
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: _eventosDelDia.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.event_busy,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No hay eventos para este día',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _eventosDelDia.length,
                          itemBuilder: (context, index) {
                            final evento = _eventosDelDia[index];
                            final hora = _formatearHora(evento['hora_inicio']);
                            final clienteId = evento['cliente_id'] as int?;
                            final nombreCliente = _obtenerNombreCliente(
                              clienteId,
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () async {
                                  final resultado = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          DetalleVisitaScreen(visita: evento),
                                    ),
                                  );
                                  // 🟢 RECARGAR SI SE EDITÓ O ELIMINÓ
                                  if (resultado == true) {
                                    await _cargarEventos();
                                  }
                                },
                                child: ListTile(
                                  leading: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF032458),
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        hora,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF032458),
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    evento['asunto'] ?? 'Sin asunto',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(nombreCliente),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _comercialId != null
          ? FloatingActionButton(
              onPressed: _crearNuevaVisita,
              backgroundColor: const Color(0xFF032458),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _mostrarDebugInfo() {
    if (_eventosDelDia.isEmpty) return;

    final evento = _eventosDelDia[0];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DEBUG - Datos RAW'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ID: ${evento['id']}'),
              const Divider(),
              Text('Asunto: ${evento['asunto']}'),
              const Divider(),
              Text('fecha_inicio:\n${evento['fecha_inicio']}'),
              const Divider(),
              Text('hora_inicio:\n"${evento['hora_inicio']}"'),
              Text('Tipo: ${evento['hora_inicio'].runtimeType}'),
              Text('Length: ${evento['hora_inicio']?.toString().length ?? 0}'),
              const Divider(),
              Text('hora_fin:\n"${evento['hora_fin']}"'),
              const Divider(),
              Text(
                '_formatearHora() devuelve:\n${_formatearHora(evento['hora_inicio'])}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
