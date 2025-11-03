import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

int? _comercialSeleccionadoId;
String _comercialSeleccionadoNombre = 'Sin asignar';
List<Map<String, dynamic>> _comerciales = [];

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isSyncing = false;
  String _syncStatus = '';
  double _syncProgress = 0.0;
  String _syncDetalle = '';
  final List<String> _logMessages = [];

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().substring(11, 19)} - $message',
      );
      if (_logMessages.length > 20) {
        _logMessages.removeAt(0);
      }
    });
    print(message);
  }

  Future<void> _cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;
    final comerciales = await db.obtenerComerciales();

    setState(() {
      _urlController.text =
          prefs.getString('velneo_url') ??
          'tecerp.nunsys.com:4311/TORRAL/TecERPv7_dat_dat/v1';
      _apiKeyController.text = prefs.getString('velneo_api_key') ?? '123456';
      _comercialSeleccionadoId = prefs.getInt('comercial_id');
      _comercialSeleccionadoNombre =
          prefs.getString('comercial_nombre') ?? 'Sin asignar';
      _comerciales = comerciales;
    });
  }

  Future<void> _guardarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('velneo_url', _urlController.text);
    await prefs.setString('velneo_api_key', _apiKeyController.text);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada'),
        backgroundColor: Color(0xFF032458),
      ),
    );
  }

  Future<void> _seleccionarComercial() async {
    if (_comerciales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero sincroniza los datos para ver comerciales'),
        ),
      );
      return;
    }

    final seleccionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Seleccionar Comercial'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _comerciales.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: const Text('Sin asignar'),
                  leading: const Icon(Icons.clear),
                  onTap: () => Navigator.pop(dialogContext, {
                    'id': null,
                    'nombre': 'Sin asignar',
                  }),
                );
              }
              final comercial = _comerciales[index - 1];
              return ListTile(
                title: Text(comercial['nombre']),
                subtitle: Text('ID: ${comercial['id']}'),
                onTap: () => Navigator.pop(dialogContext, comercial),
              );
            },
          ),
        ),
      ),
    );

    if (seleccionado != null) {
      final prefs = await SharedPreferences.getInstance();
      if (seleccionado['id'] == null) {
        await prefs.remove('comercial_id');
        await prefs.remove('comercial_nombre');
      } else {
        await prefs.setInt('comercial_id', seleccionado['id']);
        await prefs.setString('comercial_nombre', seleccionado['nombre']);
      }

      setState(() {
        _comercialSeleccionadoId = seleccionado['id'];
        _comercialSeleccionadoNombre = seleccionado['nombre'];
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Comercial asignado: ${seleccionado['nombre']}'),
          backgroundColor: const Color(0xFF032458),
        ),
      );
    }
  }

  Future<void> _sincronizarDatos() async {
    if (_urlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos primero')),
      );
      return;
    }

    await _guardarConfiguracion();

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Iniciando...';
      _syncProgress = 0.0;
      _syncDetalle = '';
      _logMessages.clear();
    });

    _addLog('ðŸš€ Iniciando sincronización');

    try {
      String url = _urlController.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(
        url,
        _apiKeyController.text,
        onLog: _addLog,
      );
      final db = DatabaseHelper.instance;

      setState(() {
        _syncStatus = 'Verificando conexión...';
        _syncProgress = 0.05;
      });

      _addLog('ðŸ” Verificando conexión con API');
      final conexionOk = await apiService.probarConexion();
      if (!conexionOk) {
        throw Exception('No se puede conectar a la API');
      }
      _addLog('âœ… Conexión exitosa');

      setState(() {
        _syncStatus = 'Descargando datos...';
        _syncProgress = 0.1;
        _syncDetalle = 'Iniciando descarga';
      });

      _addLog('ðŸ“¥ Descargando artÃ­culos');
      final articulosLista = await apiService.obtenerArticulos();
      _addLog('âœ… ${articulosLista.length} artÃ­culos descargados');
      _addLog('📥 Descargando clientes y comerciales');
      final resultadoClientes = await apiService.obtenerClientes();
      final clientesLista = resultadoClientes['clientes'] as List;
      final comercialesLista = resultadoClientes['comerciales'] as List;
      _addLog('✅ ${clientesLista.length} clientes descargados');
      _addLog('✅ ${comercialesLista.length} comerciales descargados');

      setState(() {
        _syncProgress = 0.5;
        _syncStatus = 'Descarga completa';
        _syncDetalle =
            '${articulosLista.length} artículos, ${clientesLista.length} clientes, ${comercialesLista.length} comerciales';
      });

      // GUARDAR ARTÃCULOS
      setState(() {
        _syncStatus = 'Guardando artÃ­culos...';
        _syncProgress = 0.55;
        _syncDetalle = 'Preparando...';
      });

      _addLog('ðŸ’¾ Limpiando artÃ­culos antiguos');
      await db.limpiarArticulos();

      const batchSize = 500;
      _addLog(
        'ðŸ’¾ Guardando ${articulosLista.length} artÃ­culos en lotes de $batchSize',
      );

      for (var i = 0; i < articulosLista.length; i += batchSize) {
        final end = (i + batchSize < articulosLista.length)
            ? i + batchSize
            : articulosLista.length;
        final batch = articulosLista
            .sublist(i, end)
            .cast<Map<String, dynamic>>();

        await db.insertarArticulosLote(batch);

        final progreso = 0.55 + (0.2 * (end / articulosLista.length));
        final porcentaje = ((end / articulosLista.length) * 100).toInt();

        setState(() {
          _syncProgress = progreso;
          _syncDetalle = '$end / ${articulosLista.length} ($porcentaje%)';
        });
      }

      _addLog('âœ… ${articulosLista.length} artÃ­culos guardados');

      // GUARDAR CLIENTES
      setState(() {
        _syncStatus = 'Guardando clientes...';
        _syncProgress = 0.75;
        _syncDetalle = 'Preparando...';
      });

      _addLog('💾 Limpiando clientes antiguos');
      await db.limpiarClientes();
      await db.limpiarComerciales();

      _addLog(
        '💾 Guardando ${clientesLista.length} clientes en lotes de $batchSize',
      );

      for (var i = 0; i < clientesLista.length; i += batchSize) {
        final end = (i + batchSize < clientesLista.length)
            ? i + batchSize
            : clientesLista.length;
        final batch = clientesLista
            .sublist(i, end)
            .cast<Map<String, dynamic>>();

        await db.insertarClientesLote(batch);

        final progreso = 0.75 + (0.15 * (end / clientesLista.length));
        final porcentaje = ((end / clientesLista.length) * 100).toInt();

        setState(() {
          _syncProgress = progreso;
          _syncDetalle = '$end / ${clientesLista.length} ($porcentaje%)';
        });
      }

      _addLog('✅ ${clientesLista.length} clientes guardados');

      // GUARDAR COMERCIALES
      setState(() {
        _syncStatus = 'Guardando comerciales...';
        _syncProgress = 0.90;
        _syncDetalle = 'Preparando...';
      });

      _addLog('💾 Guardando ${comercialesLista.length} comerciales');

      if (comercialesLista.isNotEmpty) {
        await db.insertarComercialesLote(
          comercialesLista.cast<Map<String, dynamic>>(),
        );
      }

      _addLog('✅ ${comercialesLista.length} comerciales guardados');

      // Recargar lista de comerciales
      final comerciales = await db.obtenerComerciales();
      setState(() {
        _comerciales = comerciales;
      });
      // === SINCRONIZAR DATOS CRM ===
      setState(() {
        _syncStatus = 'Descargando datos CRM...';
        _syncProgress = 0.92;
        _syncDetalle = 'Tipos de visita y provincias';
      });

      _addLog('📥 Descargando tipos de visita...');
      final tiposVisitaLista = await apiService.obtenerTiposVisita();
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        tiposVisitaLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${tiposVisitaLista.length} tipos de visita guardados');

      _addLog('📥 Descargando provincias...');
      final provinciasLista = await apiService.obtenerProvincias();
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(
        provinciasLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${provinciasLista.length} provincias guardadas');

      _addLog('📥 Descargando zonas técnicas...');
      final zonasLista = await apiService.obtenerZonasTecnicas();
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(
        zonasLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${zonasLista.length} zonas técnicas guardadas');

      _addLog('📥 Descargando poblaciones...');
      final poblacionesLista = await apiService.obtenerPoblaciones();
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        poblacionesLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${poblacionesLista.length} poblaciones guardadas');

      setState(() {
        _syncProgress = 0.94;
        _syncDetalle = 'Campañas y leads';
      });

      _addLog('📥 Descargando campañas comerciales...');
      final campanasLista = await apiService.obtenerCampanas();
      await db.limpiarCampanas();
      await db.insertarCampanasLote(campanasLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${campanasLista.length} campañas guardadas');

      _addLog('📥 Descargando leads...');
      final leadsLista = await apiService.obtenerLeads();
      await db.limpiarLeads();
      await db.insertarLeadsLote(leadsLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${leadsLista.length} leads guardados');

      setState(() {
        _syncProgress = 0.96;
        _syncDetalle = 'Agenda';
      });
      _addLog('📥 Descargando agenda...');
      final prefsAgenda =
          await SharedPreferences.getInstance(); // ← AÑADIR ESTA LÍNEA
      final comercialId = prefsAgenda.getInt(
        'comercial_id',
      ); // ← USAR prefsAgenda
      final agendasLista = await apiService.obtenerAgenda(comercialId);
      await db.limpiarAgenda();
      await db.insertarAgendasLote(agendasLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${agendasLista.length} eventos de agenda guardados');

      _addLog('🎉 Sincronización completada exitosamente');
      setState(() {
        _isSyncing = false;
        _syncStatus = 'Completado';
        _syncProgress = 1.0;
      });

      // Guardar timestamp de sincronización
      final prefsSync = await SharedPreferences.getInstance();
      await prefsSync.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Sincronización completa\n'
            '${articulosLista.length} artículos\n'
            '${clientesLista.length} clientes\n'
            '${comercialesLista.length} comerciales\n'
            '${tiposVisitaLista.length} tipos de visita\n'
            '${provinciasLista.length} provincias\n'
            '${zonasLista.length} zonas técnicas\n'
            '${poblacionesLista.length} poblaciones\n'
            '${campanasLista.length} campañas\n'
            '${leadsLista.length} leads\n'
            '${agendasLista.length} eventos agenda',
          ),
          backgroundColor: const Color(0xFF032458),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      _addLog('❌ ERROR: $e');

      setState(() {
        _isSyncing = false;
        _syncStatus = 'Error';
        _syncProgress = 0.0;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error de Sincronización'),
          content: SingleChildScrollView(
            child: SelectableText(e.toString().replaceAll('Exception: ', '')),
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

  Future<void> _limpiarDatos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('Â¿Eliminar todos los datos locales?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF44336),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await DatabaseHelper.instance.limpiarBaseDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos eliminados'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
    }
  }

  Future<void> _cargarDatosPrueba() async {
    await DatabaseHelper.instance.limpiarBaseDatos();
    await DatabaseHelper.instance.cargarDatosPrueba();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Datos de prueba cargados'),
        backgroundColor: Color(0xFF032458),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Conexión API Velneo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL del Servidor',
              hintText: 'servidor:puerto/ruta/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _guardarConfiguracion,
            icon: const Icon(Icons.save),
            label: const Text('Guardar Configuración'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF162846),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Comercial Asignado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: Text(_comercialSeleccionadoNombre),
              subtitle: _comercialSeleccionadoId != null
                  ? Text('ID: $_comercialSeleccionadoId')
                  : const Text('No hay comercial asignado'),
              trailing: const Icon(Icons.person),
              onTap: _seleccionarComercial,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este comercial se asignará automáticamente a todos los pedidos nuevos',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          if (_isSyncing) ...[
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _syncStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _syncProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF032458),
                      ),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_syncProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    if (_syncDetalle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _syncDetalle,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Container(
                height: 300,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Log de sincronización',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        itemCount: _logMessages.length,
                        itemBuilder: (context, index) {
                          final msg =
                              _logMessages[_logMessages.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              msg,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: msg.contains('âŒ')
                                    ? Colors.red
                                    : msg.contains('âœ…')
                                    ? Colors.green
                                    : Colors.black87,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _sincronizarDatos,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar Datos desde Velneo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Base de Datos Local',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _cargarDatosPrueba,
            icon: const Icon(Icons.data_object),
            label: const Text('Cargar Datos de Prueba'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF032458),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _limpiarDatos,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Limpiar Base de Datos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFFF44336),
            ),
          ),
        ],
      ),
    );
  }
}
