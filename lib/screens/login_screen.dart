import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../database_helper.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _comercialIdController = TextEditingController();
  final _codigoAppController = TextEditingController();
  final _serverUrlController = TextEditingController(
    text: 'tecerp.nunsys.com:4311/TORRAL/TecERPv7_dat_dat',
  );
  final _apiVersionController = TextEditingController(text: 'v1');
  final _apiKeyController = TextEditingController(text: '123456');

  bool _isLoading = false;
  String _statusMessage = '';
  final List<String> _logMessages = [];

  @override
  void dispose() {
    _comercialIdController.dispose();
    _serverUrlController.dispose();
    _apiVersionController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().substring(11, 19)} - $message',
      );
      if (_logMessages.length > 50) {
        _logMessages.removeAt(0);
      }
    });
    print(message);
  }

  Future<void> _iniciarSesion() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final codigoApp = _codigoAppController.text.trim();

    if (comercialId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ El ID debe ser un número válido')),
      );
      return;
    }

    if (codigoApp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ El código de app es obligatorio')),
      );
      return;
    }
    if (_serverUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ La URL del servidor es obligatoria')),
      );
      return;
    }

    if (_apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ La API Key es obligatoria')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Validando comercial...';
      _logMessages.clear();
    });

    try {
      // Construir URL completa con versión
      String serverUrl = _serverUrlController.text.trim();
      final apiVersion = _apiVersionController.text.trim();

      // Asegurar que no termine con /
      if (serverUrl.endsWith('/')) {
        serverUrl = serverUrl.substring(0, serverUrl.length - 1);
      }

      // Remover versión si ya está en la URL
      if (serverUrl.endsWith('/v1') ||
          serverUrl.endsWith('/v2') ||
          serverUrl.endsWith('/v3')) {
        serverUrl = serverUrl.substring(0, serverUrl.lastIndexOf('/'));
      }

      // Añadir versión
      final fullUrl = '$serverUrl/$apiVersion';

      // Asegurar protocolo
      String finalUrl = fullUrl;
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }

      // LÍNEAS A CAMBIAR:

      _addLog('🌐 Conectando a: $finalUrl');
      final apiKey = _apiKeyController.text.trim();
      final apiService = VelneoAPIService(finalUrl, apiKey);

      // 1. Descargar comerciales primero
      setState(() => _statusMessage = 'Descargando comerciales...');
      _addLog('📥 Descargando lista de comerciales desde API');

      final resultado = await apiService.obtenerClientes();
      final comercialesLista = resultado['comerciales'] as List;

      _addLog('📊 Total comerciales descargados: ${comercialesLista.length}');

      final db = DatabaseHelper.instance;
      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesLista.cast<Map<String, dynamic>>(),
      );
      _addLog('💾 Comerciales guardados en base de datos local');

      // 2. Buscar el comercial en la BD local
      setState(() => _statusMessage = 'Validando comercial ID $comercialId...');
      _addLog('🔍 Buscando comercial ID $comercialId en base de datos local');

      final comercial = await db.obtenerComercialPorId(comercialId);

      if (comercial == null || comercial.isEmpty) {
        _addLog('❌ No se encontró comercial con ID $comercialId');
        throw Exception('No se encontró ningún comercial con ID $comercialId');
      }

      _addLog('✅ Comercial encontrado: ${comercial['nombre']}');

      // 3. Descargar usuarios de app
      setState(() => _statusMessage = 'Descargando usuarios de app...');
      _addLog('📥 Descargando usuarios desde API');

      final usuariosLista = await apiService.obtenerTodosUsuarios();
      _addLog('📊 Total usuarios descargados: ${usuariosLista.length}');

      // Guardar usuarios en BD local (necesitarás crear esta tabla)
      await db.insertarUsuariosLote(usuariosLista.cast<Map<String, dynamic>>());
      _addLog('💾 Usuarios guardados en base de datos local');

      // 4. Buscar usuario asociado al comercial en BD local
      setState(() => _statusMessage = 'Buscando usuario de app...');
      _addLog('🔍 Buscando usuario para comercial ID $comercialId en BD local');

      final usuario = await db.obtenerUsuarioPorComercial(comercialId);

      if (usuario == null || usuario.isEmpty) {
        _addLog('❌ No se encontró usuario para este comercial');
        throw Exception('No se encontró usuario de app para este comercial.');
      }

      final usuarioAppId = usuario['id'] as int;
      _addLog(
        '✅ Usuario de app encontrado: ${usuario['name']} (ID: $usuarioAppId)',
      );

      // 5. Descargar relaciones usr_apl
      setState(() => _statusMessage = 'Validando acceso a la aplicación...');
      _addLog('📥 Descargando permisos de aplicación');

      final usrAplLista = await apiService.obtenerTodosUsrApl();
      _addLog('📊 Total registros usr_apl descargados: ${usrAplLista.length}');

      // 6. Verificar acceso en la lista descargada
      _addLog(
        '🔐 Verificando acceso del usuario $usuarioAppId al código de app $codigoApp',
      );

      final tieneAcceso = usrAplLista.any(
        (reg) =>
            reg['usr_m'] == usuarioAppId &&
            reg['apl_tec'] == int.parse(codigoApp),
      );

      if (!tieneAcceso) {
        _addLog('❌ Usuario no tiene acceso a esta aplicación');
        _addLog(
          '💡 No existe registro usr_apl con usr_m=$usuarioAppId y apl_tec=$codigoApp',
        );
        throw Exception('Este usuario no tiene acceso a la aplicación.');
      }

      _addLog('✅ Acceso validado correctamente');
      _addLog('✅ Acceso validado correctamente');
      // Línea 150-156 - Guardar también el ID del usuario de app:
      // Guardar configuración
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('velneo_url', finalUrl);
      await prefs.setString('velneo_api_key', apiKey);
      await prefs.setString('api_version', apiVersion);
      await prefs.setInt('comercial_id', comercialId);
      await prefs.setString('comercial_nombre', comercial['nombre']);
      await prefs.setInt('usuario_app_id', usuarioAppId);
      await prefs.setString('usuario_app_nombre', usuario['name']);
      _addLog('💾 Configuración guardada');

      // Sincronizar todos los datos
      await _sincronizarDatos(apiService, comercialId);

      // Navegar a home
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      _addLog('❌ ERROR: $e');

      if (!mounted) return;

      // Mostrar diálogo con TODOS los logs
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error de Conexión'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error: ${e.toString().replaceAll('Exception: ', '')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Log completo:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._logMessages.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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

  Future<void> _sincronizarDatos(
    VelneoAPIService apiService,
    int comercialId,
  ) async {
    final db = DatabaseHelper.instance;

    try {
      // Artículos
      setState(() => _statusMessage = 'Descargando artículos...');
      _addLog('📥 Descargando artículos...');
      final articulosLista = await apiService.obtenerArticulos();
      await db.limpiarArticulos();
      await db.insertarArticulosLote(
        articulosLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${articulosLista.length} artículos guardados');

      // Clientes y Comerciales
      setState(() => _statusMessage = 'Descargando clientes...');
      _addLog('📥 Descargando clientes y comerciales...');
      final resultado = await apiService.obtenerClientes();
      final clientesLista = resultado['clientes'] as List;
      final comercialesLista = resultado['comerciales'] as List;

      await db.limpiarClientes();
      await db.insertarClientesLote(clientesLista.cast<Map<String, dynamic>>());
      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesLista.cast<Map<String, dynamic>>(),
      );
      _addLog(
        '✅ ${clientesLista.length} clientes y ${comercialesLista.length} comerciales guardados',
      );

      // Tarifas
      setState(() => _statusMessage = 'Descargando tarifas...');
      _addLog('📥 Descargando tarifas por cliente...');
      final tarifasClienteLista = await apiService.obtenerTarifasCliente();
      await db.limpiarTarifasCliente();
      await db.insertarTarifasClienteLote(
        tarifasClienteLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${tarifasClienteLista.length} tarifas por cliente guardadas');

      _addLog('📥 Descargando tarifas por artículo...');
      final tarifasArticuloLista = await apiService.obtenerTarifasArticulo();
      await db.limpiarTarifasArticulo();
      await db.insertarTarifasArticuloLote(
        tarifasArticuloLista.cast<Map<String, dynamic>>(),
      );
      _addLog(
        '✅ ${tarifasArticuloLista.length} tarifas por artículo guardadas',
      );

      // Tipos de visita
      setState(() => _statusMessage = 'Descargando tipos de visita...');
      _addLog('📥 Descargando tipos de visita...');
      final tiposVisitaLista = await apiService.obtenerTiposVisita();
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        tiposVisitaLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${tiposVisitaLista.length} tipos de visita guardados');

      // Campañas
      setState(() => _statusMessage = 'Descargando campañas...');
      _addLog('📥 Descargando campañas comerciales...');
      final campanasLista = await apiService.obtenerCampanas();
      await db.limpiarCampanas();
      await db.insertarCampanasLote(campanasLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${campanasLista.length} campañas guardadas');

      // Leads
      setState(() => _statusMessage = 'Descargando leads...');
      _addLog('📥 Descargando leads...');
      final leadsLista = await apiService.obtenerLeads();
      await db.limpiarLeads();
      await db.insertarLeadsLote(leadsLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${leadsLista.length} leads guardados');

      // Agenda
      setState(() => _statusMessage = 'Descargando agenda...');
      _addLog('📥 Descargando agenda del comercial $comercialId...');
      final agendasLista = await apiService.obtenerAgenda(comercialId);
      await db.limpiarAgenda();
      await db.insertarAgendasLote(agendasLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${agendasLista.length} eventos de agenda guardados');

      // Pedidos
      setState(() => _statusMessage = 'Descargando pedidos...');
      _addLog('📥 Descargando pedidos...');
      final pedidosLista = await apiService.obtenerPedidos();
      await db.limpiarPedidos();
      await db.insertarPedidosLote(pedidosLista.cast<Map<String, dynamic>>());
      _addLog('✅ ${pedidosLista.length} pedidos guardados');

      _addLog('📥 Descargando líneas de pedido...');
      final lineasPedido = await apiService.obtenerTodasLineasPedido();
      await db.insertarLineasPedidoLote(
        lineasPedido.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${lineasPedido.length} líneas de pedido guardadas');

      // Presupuestos
      setState(() => _statusMessage = 'Descargando presupuestos...');
      _addLog('📥 Descargando presupuestos...');
      final presupuestosLista = await apiService.obtenerPresupuestos();
      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        presupuestosLista.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${presupuestosLista.length} presupuestos guardados');

      _addLog('📥 Descargando líneas de presupuesto...');
      final lineasPresupuesto = await apiService
          .obtenerTodasLineasPresupuesto();
      await db.insertarLineasPresupuestoLote(
        lineasPresupuesto.cast<Map<String, dynamic>>(),
      );
      _addLog('✅ ${lineasPresupuesto.length} líneas de presupuesto guardadas');

      // Guardar timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      setState(() => _statusMessage = '✅ Sincronización completada');
      _addLog('🎉 ¡Sincronización completa exitosa!');
    } catch (e) {
      _addLog('❌ Error en sincronización: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF032458),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _statusMessage,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Log de Sincronización',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            reverse: true,
                            itemCount: _logMessages.length,
                            itemBuilder: (context, index) {
                              final reversedIndex =
                                  _logMessages.length - 1 - index;
                              return Text(
                                _logMessages[reversedIndex],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    // Logo o título
                    const Icon(
                      Icons.business_center,
                      size: 80,
                      color: Color(0xFF032458),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'CRM Velneo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configuración Inicial',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 48),
                    TextField(
                      controller: _codigoAppController,
                      decoration: const InputDecoration(
                        labelText: 'Código de App *',
                        hintText: 'Código único de aplicación',
                        prefixIcon: Icon(Icons.smartphone),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ID Comercial
                    TextField(
                      controller: _comercialIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID del Comercial *',
                        hintText: 'Ej: 123',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // URL Servidor
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'URL del Servidor *',
                        hintText: 'servidor:puerto/ruta',
                        helperText: 'Sin versión (v1, v2, etc.)',
                        prefixIcon: Icon(Icons.dns),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),

                    // Versión API
                    TextField(
                      controller: _apiVersionController,
                      decoration: const InputDecoration(
                        labelText: 'Versión de la API *',
                        hintText: 'v1, v2, v3...',
                        prefixIcon: Icon(Icons.api),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // API Key
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key *',
                        hintText: 'Ingrese su clave API',
                        prefixIcon: Icon(Icons.vpn_key),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 32),

                    // Botón de inicio
                    ElevatedButton(
                      onPressed: _iniciarSesion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF032458),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'INICIAR SESIÓN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
