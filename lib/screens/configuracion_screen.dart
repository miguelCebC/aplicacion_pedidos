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
  final _diasVisitaController = TextEditingController();

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
          'tecerp.nunsys.com:4331/TORRAL/TecERPv7_dat_dat/v1';
      _apiKeyController.text = prefs.getString('velneo_api_key') ?? '123456';
      _diasVisitaController.text = (prefs.getInt('proxima_visita_dias') ?? 60)
          .toString();

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
    final int dias = int.tryParse(_diasVisitaController.text) ?? 60;
    await prefs.setInt('proxima_visita_dias', dias);

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

        // 🟢 ESTE CÓDIGO (CON SIZEDBOX) ES LA CORRECCIÓN DEL PASO ANTERIOR
        content: SizedBox(
          width: double.maxFinite,
          height: 300, // <-- Altura fija para el área de scroll
          child: ListView.builder(
            // shrinkWrap: true, // <-- Esta línea NO debe estar
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

  // [DENTRO DE lib/screens/configuracion_screen.dart]

  // [DENTRO DE lib/screens/configuracion_screen.dart]

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

    _addLog('🚀 Iniciando sincronización');

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

      // --- 1. Conexión ---
      setState(() {
        _syncStatus = 'Verificando conexión...';
        _syncProgress = 0.05;
      });

      final conexionOk = await apiService.probarConexion();
      if (!conexionOk) throw Exception('No se puede conectar a la API');
      _addLog('✅ Conexión exitosa');

      // --- 2. Artículos ---
      setState(() {
        _syncStatus = 'Artículos...';
        _syncProgress = 0.10;
      });
      _addLog('📦 Descargando artículos');
      final articulosLista = await apiService.obtenerArticulos();

      await db.limpiarArticulos();
      const batchSize = 500;
      for (var i = 0; i < articulosLista.length; i += batchSize) {
        final end = (i + batchSize < articulosLista.length)
            ? i + batchSize
            : articulosLista.length;
        await db.insertarArticulosLote(
          articulosLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }
      _addLog('✅ ${articulosLista.length} artículos guardados');

      // --- 3. Clientes y Comerciales ---
      setState(() {
        _syncStatus = 'Clientes...';
        _syncProgress = 0.30;
      });
      _addLog('📥 Descargando clientes y comerciales...');
      final resultadoClientes = await apiService.obtenerClientes();
      final clientesLista = resultadoClientes['clientes'] as List;
      final comercialesLista = resultadoClientes['comerciales'] as List;

      await db.limpiarClientes();
      for (var i = 0; i < clientesLista.length; i += batchSize) {
        final end = (i + batchSize < clientesLista.length)
            ? i + batchSize
            : clientesLista.length;
        await db.insertarClientesLote(
          clientesLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesLista.cast<Map<String, dynamic>>(),
      );

      // Actualizar lista en memoria
      final comercialesDb = await db.obtenerComerciales();
      setState(() => _comerciales = comercialesDb);

      _addLog(
        '✅ ${clientesLista.length} clientes y ${comercialesLista.length} comerciales',
      );

      // --- 4. Datos Maestros CRM ---
      setState(() {
        _syncStatus = 'Datos CRM...';
        _syncProgress = 0.50;
      });

      _addLog('📥 Tipos visita, provincias, zonas...');

      final tiposVisita = await apiService.obtenerTiposVisita();
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        tiposVisita.cast<Map<String, dynamic>>(),
      );

      final provincias = await apiService.obtenerProvincias();
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(provincias.cast<Map<String, dynamic>>());

      final zonas = await apiService.obtenerZonasTecnicas();
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(zonas.cast<Map<String, dynamic>>());

      final poblaciones = await apiService.obtenerPoblaciones();
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        poblaciones.cast<Map<String, dynamic>>(),
      );

      final campanas = await apiService.obtenerCampanas();
      await db.limpiarCampanas();
      await db.insertarCampanasLote(campanas.cast<Map<String, dynamic>>());

      _addLog('✅ Maestros CRM actualizados');

      // --- 5. Datos Transaccionales (Leads, Agenda, Pedidos, Presupuestos) ---
      setState(() {
        _syncStatus = 'Datos Usuario...';
        _syncProgress = 0.70;
      });

      // Leads
      final leads = await apiService.obtenerLeads();
      await db.limpiarLeads();
      await db.insertarLeadsLote(leads.cast<Map<String, dynamic>>());

      // Agenda (filtrada por comercial actual si existe)
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');

      _addLog('📥 Descargando agenda...');
      final agenda = await apiService.obtenerAgenda(comercialId);
      await db.limpiarAgenda();
      await db.insertarAgendasLote(agenda.cast<Map<String, dynamic>>());

      // Pedidos
      _addLog('📥 Descargando pedidos...');
      final pedidos = await apiService.obtenerPedidos();
      await db.limpiarPedidos();
      await db.insertarPedidosLote(pedidos.cast<Map<String, dynamic>>());

      final lineasPedido = await apiService.obtenerTodasLineasPedido();
      await db.insertarLineasPedidoLote(
        lineasPedido.cast<Map<String, dynamic>>(),
      );

      // Presupuestos
      _addLog('📥 Descargando presupuestos...');
      final presupuestos = await apiService.obtenerPresupuestos();
      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        presupuestos.cast<Map<String, dynamic>>(),
      );

      final lineasPresu = await apiService.obtenerTodasLineasPresupuesto();
      await db.insertarLineasPresupuestoLote(
        lineasPresu.cast<Map<String, dynamic>>(),
      );

      // Tarifas
      _addLog('📥 Descargando tarifas...');
      final tarifasCli = await apiService.obtenerTarifasCliente();
      await db.limpiarTarifasCliente();
      await db.insertarTarifasClienteLote(
        tarifasCli.cast<Map<String, dynamic>>(),
      );

      final tarifasArt = await apiService.obtenerTarifasArticulo();
      await db.limpiarTarifasArticulo();
      await db.insertarTarifasArticuloLote(
        tarifasArt.cast<Map<String, dynamic>>(),
      );

      // --- 6. NUEVO: Configuración de IVA ---
      setState(() {
        _syncStatus = 'Configurando IVA...';
        _syncProgress = 0.95;
      });

      _addLog('📥 Descargando IVA desde API...');
      final configIva = await apiService.obtenerConfiguracionIVA();

      if (configIva.isNotEmpty) {
        await prefs.setDouble('iva_general', configIva['iva_general']!);
        await prefs.setDouble('iva_reducido', configIva['iva_reducido']!);
        await prefs.setDouble(
          'iva_superreducido',
          configIva['iva_superreducido']!,
        );
        await prefs.setDouble('iva_exento', configIva['iva_exento']!);

        // Recargar clase estática para uso inmediato
        // Nota: Asegúrate de importar '../models/iva_config.dart'
        // await IvaConfig.cargarConfiguracion();
        // (Si no puedes acceder a IvaConfig aquí, se cargará al reiniciar la app o entrar en pantallas)
        _addLog('✅ IVA actualizado: G=${configIva['iva_general']}%');
      } else {
        _addLog('⚠️ No se pudo descargar IVA, usando valores por defecto');
      }

      // Finalizar
      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      setState(() {
        _syncProgress = 1.0;
        _syncStatus = 'Completado';
        _syncDetalle = 'Sincronización exitosa';
      });

      _addLog('🎉 Sincronización finalizada con éxito');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronización completada con éxito'),
          backgroundColor: Color(0xFF032458),
        ),
      );
    } catch (e) {
      _addLog('❌ ERROR CRÍTICO: $e');
      setState(() {
        _isSyncing = false;
        _syncStatus = 'Error';
        _syncProgress = 0.0;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error de Sincronización'),
          content: SingleChildScrollView(child: Text(e.toString())),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }
  // Añadir después del método _sincronizarDatos() en lib/screens/configuracion_screen.dart

  Future<void> _sincronizacionIncremental() async {
    if (_urlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configura la URL y API Key primero')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Actualización rápida...';
      _syncProgress = 0.0;
      _syncDetalle = '';
      _logMessages.clear();
    });

    _addLog('🔄 Iniciando actualización incremental');

    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimaSincMs = prefs.getInt('ultima_sincronizacion') ?? 0;

      DateTime? fechaDesde;
      if (ultimaSincMs > 0) {
        // Restar 1 hora de margen para no perder datos
        fechaDesde = DateTime.fromMillisecondsSinceEpoch(
          ultimaSincMs,
        ).subtract(const Duration(hours: 1));
        _addLog('📅 Buscando cambios desde: ${fechaDesde.toIso8601String()}');
      } else {
        _addLog('📅 Primera sincronización - usar sincronización completa');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Primera vez: usa Sincronización Completa'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isSyncing = false);
        return;
      }

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
      final comercialId = prefs.getInt('comercial_id');

      setState(() {
        _syncStatus = 'Verificando conexión...';
        _syncProgress = 0.1;
      });

      final conexionOk = await apiService.probarConexion();
      if (!conexionOk) {
        throw Exception('No se puede conectar a la API');
      }

      setState(() {
        _syncStatus = 'Actualizando artículos...';
        _syncProgress = 0.15;
      });

      _addLog('📥 Buscando artículos modificados...');
      final articulosNuevos = await apiService.obtenerArticulosIncrementales(
        fechaDesde,
      );

      if (articulosNuevos.isNotEmpty) {
        await db.insertarArticulosLote(
          articulosNuevos.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${articulosNuevos.length} artículos actualizados');
      } else {
        _addLog('✓ No hay artículos nuevos');
      }

      // Actualizar clientes y comerciales
      setState(() {
        _syncStatus = 'Actualizando clientes...';
        _syncProgress = 0.2;
      });

      _addLog('📥 Buscando clientes/comerciales modificados...');
      final resultadoClientes = await apiService.obtenerClientesIncrementales(
        fechaDesde,
      );
      final clientesNuevos = resultadoClientes['clientes'] as List;
      final comercialesNuevos = resultadoClientes['comerciales'] as List;

      if (clientesNuevos.isNotEmpty) {
        await db.insertarClientesLote(
          clientesNuevos.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${clientesNuevos.length} clientes actualizados');
      } else {
        _addLog('✓ No hay clientes nuevos');
      }

      if (comercialesNuevos.isNotEmpty) {
        await db.insertarComercialesLote(
          comercialesNuevos.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${comercialesNuevos.length} comerciales actualizados');
      } else {
        _addLog('✓ No hay comerciales nuevos');
      }

      // Actualizar pedidos (cambiar el progress a 0.35)
      setState(() {
        _syncStatus = 'Actualizando pedidos...';
        _syncProgress = 0.35;
      });

      _addLog('📥 Buscando pedidos modificados...');
      final pedidosNuevos = await apiService.obtenerPedidosIncrementales(
        fechaDesde,
      );
      if (pedidosNuevos.isNotEmpty) {
        await db.insertarPedidosLote(
          pedidosNuevos.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${pedidosNuevos.length} pedidos actualizados');

        _addLog('📥 Actualizando líneas de pedido...');
        await db.limpiarLineasPedido(); // 🔥 AGREGAR ESTA LÍNEA
        final lineasPedido = await apiService.obtenerTodasLineasPedido();
        await db.insertarLineasPedidoLote(
          lineasPedido.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${lineasPedido.length} líneas de pedido actualizadas');
      } else {
        _addLog('✓ No hay pedidos nuevos');
      }
      // Actualizar presupuestos
      setState(() {
        _syncStatus = 'Actualizando presupuestos...';
        _syncProgress = 0.4;
      });

      _addLog('📥 Buscando presupuestos modificados...');
      final presupuestosNuevos = await apiService
          .obtenerPresupuestosIncrementales(fechaDesde);

      if (presupuestosNuevos.isNotEmpty) {
        await db.insertarPresupuestosLote(
          presupuestosNuevos.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${presupuestosNuevos.length} presupuestos actualizados');

        _addLog('📥 Actualizando líneas de presupuesto...');
        await db.limpiarLineasPresupuesto(); // 🔥 AGREGAR ESTA LÍNEA
        final lineasPresupuesto = await apiService
            .obtenerTodasLineasPresupuesto();
        await db.insertarLineasPresupuestoLote(
          lineasPresupuesto.cast<Map<String, dynamic>>(),
        );
        _addLog(
          '✅ ${lineasPresupuesto.length} líneas de presupuesto actualizadas',
        );
      } else {
        _addLog('✓ No hay presupuestos nuevos');
      }
      // Actualizar leads
      setState(() {
        _syncStatus = 'Actualizando leads...';
        _syncProgress = 0.6;
      });

      _addLog('📥 Buscando leads modificados...');
      final leadsNuevos = await apiService.obtenerLeadsIncrementales(
        fechaDesde,
      );

      if (leadsNuevos.isNotEmpty) {
        await db.insertarLeadsLote(leadsNuevos.cast<Map<String, dynamic>>());
        _addLog('✅ ${leadsNuevos.length} leads actualizados');
      } else {
        _addLog('✓ No hay leads nuevos');
      }

      // Actualizar agenda
      setState(() {
        _syncStatus = 'Actualizando agenda...';
        _syncProgress = 0.8;
      });

      _addLog('📥 Buscando eventos modificados...');
      final agendasNuevas = await apiService.obtenerAgendaIncremental(
        fechaDesde,
        comercialId,
      );

      if (agendasNuevas.isNotEmpty) {
        await db.insertarAgendasLote(
          agendasNuevas.cast<Map<String, dynamic>>(),
        );
        _addLog('✅ ${agendasNuevas.length} eventos actualizados');
      } else {
        _addLog('✓ No hay eventos nuevos');
      }

      // Guardar timestamp
      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      setState(() {
        _syncProgress = 1.0;
        _syncStatus = 'Actualización completada';
        _isSyncing = false;
      });

      _addLog('🎉 Actualización incremental completada');

      final totalActualizados =
          pedidosNuevos.length +
          presupuestosNuevos.length +
          leadsNuevos.length +
          agendasNuevas.length;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            totalActualizados > 0
                ? '✅ $totalActualizados registro(s) actualizados'
                : '✓ Todos los datos están al día',
          ),
          backgroundColor: const Color(0xFF032458),
          duration: const Duration(seconds: 3),
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
          title: const Text('Error'),
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
  // ... (El resto del fichero configuracion_screen.dart no cambia) ...

  Future<void> _limpiarDatos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar todos los datos locales?'),
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

  // 🟢 1. NUEVA FUNCIÓN DE DIAGNÓSTICO
  Future<void> _verificarComercialesDB() async {
    final db = DatabaseHelper.instance;
    final comerciales = await db.obtenerComerciales();

    print('--- VERIFICACIÓN DB COMERCIALES ---');
    print('Total encontrados: ${comerciales.length}');

    final nombres = comerciales.map((c) => c['nombre']).toList();
    print(nombres.join('\n'));
    print('------------------------------------');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('DB Contenido: Comerciales (${comerciales.length})'),
        content: SizedBox(
          height: 400, // <-- Más altura para ver más
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: comerciales.length,
            itemBuilder: (context, index) {
              final comercial = comerciales[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  '${index + 1}. ${comercial['nombre']} (ID: ${comercial['id']})',
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
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
          TextField(
            controller: _diasVisitaController,
            decoration: const InputDecoration(
              labelText: 'Días por defecto próxima visita',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            keyboardType: TextInputType.number,
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
                                color: msg.contains('❌')
                                    ? Colors.red
                                    : msg.contains('✅')
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

          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _sincronizacionIncremental,
            icon: const Icon(Icons.update),
            label: const Text('Actualización Rápida (Solo Cambios)'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
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

          // 🟢 2. AÑADIR EL NUEVO BOTÓN
          ElevatedButton.icon(
            onPressed: _verificarComercialesDB,
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Verificar Comerciales en DB'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.orange[800],
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
