import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'detalle_visita_screen.dart';
import 'crear_visita_screen.dart';
import '../services/api_service.dart';

class CRMCalendarioScreen extends StatefulWidget {
  const CRMCalendarioScreen({Key? key}) : super(key: key);

  @override
  State<CRMCalendarioScreen> createState() => _CRMCalendarioScreenState();
}

// 🟢 1. Se añade 'with AutomaticKeepAliveClientMixin' para mantener viva la pestaña
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

  // 🟢 2. Se añade la propiedad 'wantKeepAlive'
  @override
  bool get wantKeepAlive => true; // Esto mantiene el estado de la pestaña

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
      // 🟢 3. MODIFICADO:
      // Ya no llamamos a _sincronizarVisitas() aquí.
      // Solo cargamos los eventos de la base de datos local.
      // La sincronización de red ya la hace 'main.dart' en segundo plano.
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
    setState(() {
      _eventosDelDia = _eventos[diaKey] ?? [];
    });
  }

  List<Map<String, dynamic>> _getEventosParaDia(DateTime dia) {
    final diaKey = DateTime(dia.year, dia.month, dia.day);
    return _eventos[diaKey] ?? [];
  }

  String _formatearHora(String? horaStr) {
    if (horaStr == null || horaStr.isEmpty) return '';
    try {
      // Controlar el formato de hora que viene de Velneo (ej. "9:0:0")
      if (horaStr.contains(':')) {
        final parts = horaStr.split(':');
        final hora = int.parse(parts[0]).toString().padLeft(2, '0');
        final minuto = int.parse(parts[1]).toString().padLeft(2, '0');
        return '$hora:$minuto';
      }
      // Si es una fecha completa (ej. guardado local)
      final dt = DateTime.parse(horaStr);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      // Fallback por si el formato es inesperado
      if (horaStr.length > 5) return horaStr.substring(0, 5);
      return horaStr;
    }
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
      // Recargar eventos después de crear (desde la BD local)
      await _cargarEventos();
    }
  }

  // Esta función se mantiene para el botón de refresco manual
  Future<void> _sincronizarVisitas() async {
    if (_comercialId == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Evitar sincronizaciones múltiples si ya hay una en curso
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
        '🔄 Sincronizando agenda del comercial $_comercialId desde Velneo...',
      );

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      // Limpiar y recargar agenda del comercial
      await db.limpiarAgenda();
      final visitasComercial = await apiService.obtenerAgenda(_comercialId);
      await db.insertarAgendasLote(
        visitasComercial.cast<Map<String, dynamic>>(),
      );

      print('✅ Agenda sincronizada: ${visitasComercial.length} visitas');

      setState(() => _sincronizando = false);
      await _cargarEventos(); // Carga los datos recién descargados

      if (!mounted) return;

      // Solo mostrar mensaje si es sincronización manual (no al abrir)
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
    // 🟢 4. Se añade 'super.build(context)'
    super.build(context); // Requerido por AutomaticKeepAliveClientMixin

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agenda CRM'),
            Text(_comercialNombre, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _sincronizando ? null : _sincronizarVisitas,
            tooltip: 'Sincronizar con Velneo',
          ),
        ],
      ),
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
                      DefaultTabController.of(context)?.animateTo(3);
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
                    markersMaxCount: 1,
                    markerDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Color(0xFF162846),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: true,
                    titleCentered: true,
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
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Eventos del día (${_eventosDelDia.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _crearNuevaVisita,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF032458),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _eventosDelDia.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.event_busy,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text(
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
                                  // Si se borra o edita la visita, recargar
                                  if (resultado == true) {
                                    _cargarEventos();
                                  }
                                },
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF032458),
                                    child: Text(
                                      _formatearHora(evento['hora_inicio']),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  title: Text(
                                    evento['asunto'] ?? 'Sin asunto',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (evento['descripcion'] != null &&
                                          evento['descripcion']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                          evento['descripcion'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Cliente ID: ${evento['cliente_id']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: evento['todo_dia'] == 1
                                      ? const Chip(
                                          label: Text(
                                            'Todo el día',
                                            style: TextStyle(fontSize: 10),
                                          ),
                                          backgroundColor: Color(0xFFCAD3E2),
                                        )
                                      : const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
