import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'home_screen.dart';
import '../services/api_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _comercialIdController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _nuevaContrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();

  bool _isLoading = true;
  bool _esPrimeraVez = false;
  String _mensajeError = '';

  @override
  void initState() {
    super.initState();
    _verificarPrimeraVez();
  }

  @override
  void dispose() {
    _comercialIdController.dispose();
    _contrasenaController.dispose();
    _nuevaContrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  Future<void> _verificarPrimeraVez() async {
    final db = DatabaseHelper.instance;
    final existeContrasena = await db.existeContrasenaLocal();

    setState(() {
      _esPrimeraVez = !existeContrasena;
      _isLoading = false;
    });
  }

  Future<void> _establecerContrasena() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final nuevaContrasena = _nuevaContrasenaController.text.trim();
    final confirmarContrasena = _confirmarContrasenaController.text.trim();

    if (comercialId == null) {
      setState(() => _mensajeError = 'El ID debe ser un número válido');
      return;
    }

    if (nuevaContrasena.isEmpty || nuevaContrasena.length < 4) {
      setState(
        () => _mensajeError = 'La contraseña debe tener al menos 4 caracteres',
      );
      return;
    }

    if (nuevaContrasena != confirmarContrasena) {
      setState(() => _mensajeError = 'Las contraseñas no coinciden');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verificar que el comercial existe en la sesión guardada
      final prefs = await SharedPreferences.getInstance();
      final comercialGuardado = prefs.getInt('comercial_id');

      if (comercialGuardado == null || comercialGuardado != comercialId) {
        setState(() {
          _mensajeError =
              'El ID de comercial no coincide con la sesión guardada';
          _isLoading = false;
        });
        return;
      }

      // Guardar contraseña
      final db = DatabaseHelper.instance;
      await db.guardarContrasenaLocal(nuevaContrasena);

      if (!mounted) return;

      // Ir a home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _mensajeError = 'Error: $e';
        _isLoading = false;
      });
    }
  }
  // Reemplazar el método _validarContrasena() en lib/screens/auth_screen.dart (líneas ~87-121)

  // Reemplazar el método _validarContrasena() en lib/screens/auth_screen.dart

  Future<void> _validarContrasena() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final contrasena = _contrasenaController.text.trim();

    if (comercialId == null) {
      setState(() => _mensajeError = 'El ID debe ser un número válido');
      return;
    }

    if (contrasena.isEmpty) {
      setState(() => _mensajeError = 'La contraseña es obligatoria');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verificar comercial
      final prefs = await SharedPreferences.getInstance();
      final comercialGuardado = prefs.getInt('comercial_id');

      if (comercialGuardado == null || comercialGuardado != comercialId) {
        setState(() {
          _mensajeError = 'ID de comercial incorrecto';
          _isLoading = false;
        });
        return;
      }

      // Verificar contraseña
      final db = DatabaseHelper.instance;
      final contrasenaGuardada = await db.obtenerContrasenaLocal();

      if (contrasenaGuardada != contrasena) {
        setState(() {
          _mensajeError = 'Contraseña incorrecta';
          _isLoading = false;
        });
        return;
      }

      // Mostrar loading mínimo 3 segundos
      await Future.delayed(const Duration(seconds: 3));

      // Lanzar sincronización en segundo plano (sin await)
      _sincronizacionRapidaEnSegundoPlano();

      if (!mounted) return;

      // Ir a home inmediatamente
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _mensajeError = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  // Actualizar el método _sincronizacionRapidaEnSegundoPlano() para que sea verdadero segundo plano

  Future<void> _sincronizacionRapidaEnSegundoPlano() async {
    // Ejecutar en segundo plano sin bloquear navegación
    Future.delayed(Duration.zero, () async {
      try {
        print('🔄 [BACKGROUND] Iniciando sincronización rápida...');

        final prefs = await SharedPreferences.getInstance();
        String? url = prefs.getString('velneo_url');
        String? apiKey = prefs.getString('velneo_api_key');
        final comercialId = prefs.getInt('comercial_id');
        final ultimaSincMs = prefs.getInt('ultima_sincronizacion') ?? 0;

        if (url == null || apiKey == null || url.isEmpty || apiKey.isEmpty) {
          print('⚠️ [BACKGROUND] No hay configuración de API');
          return;
        }

        if (ultimaSincMs == 0) {
          print(
            '⚠️ [BACKGROUND] Primera vez - omitiendo sincronización automática',
          );
          return;
        }

        final fechaDesde = DateTime.fromMillisecondsSinceEpoch(
          ultimaSincMs,
        ).subtract(const Duration(hours: 1));

        print(
          '📅 [BACKGROUND] Buscando cambios desde: ${fechaDesde.toIso8601String()}',
        );

        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
        }

        final apiService = VelneoAPIService(url, apiKey);
        final db = DatabaseHelper.instance;

        // Artículos
        print('📥 [BACKGROUND] Actualizando artículos...');
        final articulosNuevos = await apiService.obtenerArticulosIncrementales(
          fechaDesde,
        );
        if (articulosNuevos.isNotEmpty) {
          await db.insertarArticulosLote(
            articulosNuevos.cast<Map<String, dynamic>>(),
          );
          print(
            '✅ [BACKGROUND] ${articulosNuevos.length} artículos actualizados',
          );
        }

        // Clientes y comerciales
        print('📥 [BACKGROUND] Actualizando clientes y comerciales...');
        final resultadoClientes = await apiService.obtenerClientesIncrementales(
          fechaDesde,
        );
        final clientesNuevos = resultadoClientes['clientes'] as List;
        final comercialesNuevos = resultadoClientes['comerciales'] as List;

        if (clientesNuevos.isNotEmpty) {
          await db.insertarClientesLote(
            clientesNuevos.cast<Map<String, dynamic>>(),
          );
          print(
            '✅ [BACKGROUND] ${clientesNuevos.length} clientes actualizados',
          );
        }

        if (comercialesNuevos.isNotEmpty) {
          await db.insertarComercialesLote(
            comercialesNuevos.cast<Map<String, dynamic>>(),
          );
          print(
            '✅ [BACKGROUND] ${comercialesNuevos.length} comerciales actualizados',
          );
        }

        // Pedidos
        print('📥 [BACKGROUND] Actualizando pedidos...');
        final pedidosNuevos = await apiService.obtenerPedidosIncrementales(
          fechaDesde,
        );
        if (pedidosNuevos.isNotEmpty) {
          await db.insertarPedidosLote(
            pedidosNuevos.cast<Map<String, dynamic>>(),
          );
          print('✅ [BACKGROUND] ${pedidosNuevos.length} pedidos actualizados');

          final lineasPedido = await apiService.obtenerTodasLineasPedido();
          await db.insertarLineasPedidoLote(
            lineasPedido.cast<Map<String, dynamic>>(),
          );
          print('✅ [BACKGROUND] Líneas de pedido actualizadas');
        }

        // Presupuestos
        print('📥 [BACKGROUND] Actualizando presupuestos...');
        final presupuestosNuevos = await apiService
            .obtenerPresupuestosIncrementales(fechaDesde);
        if (presupuestosNuevos.isNotEmpty) {
          await db.insertarPresupuestosLote(
            presupuestosNuevos.cast<Map<String, dynamic>>(),
          );
          print(
            '✅ [BACKGROUND] ${presupuestosNuevos.length} presupuestos actualizados',
          );

          final lineasPresupuesto = await apiService
              .obtenerTodasLineasPresupuesto();
          await db.insertarLineasPresupuestoLote(
            lineasPresupuesto.cast<Map<String, dynamic>>(),
          );
          print('✅ [BACKGROUND] Líneas de presupuesto actualizadas');
        }

        // Leads
        print('📥 [BACKGROUND] Actualizando leads...');
        final leadsNuevos = await apiService.obtenerLeadsIncrementales(
          fechaDesde,
        );
        if (leadsNuevos.isNotEmpty) {
          await db.insertarLeadsLote(leadsNuevos.cast<Map<String, dynamic>>());
          print('✅ [BACKGROUND] ${leadsNuevos.length} leads actualizados');
        }

        // Agenda
        print('📥 [BACKGROUND] Actualizando agenda...');
        final agendasNuevas = await apiService.obtenerAgendaIncremental(
          fechaDesde,
          comercialId,
        );
        if (agendasNuevas.isNotEmpty) {
          await db.insertarAgendasLote(
            agendasNuevas.cast<Map<String, dynamic>>(),
          );
          print('✅ [BACKGROUND] ${agendasNuevas.length} eventos actualizados');
        }

        // Guardar timestamp
        await prefs.setInt(
          'ultima_sincronizacion',
          DateTime.now().millisecondsSinceEpoch,
        );

        final totalActualizados =
            articulosNuevos.length +
            clientesNuevos.length +
            comercialesNuevos.length +
            pedidosNuevos.length +
            presupuestosNuevos.length +
            leadsNuevos.length +
            agendasNuevas.length;

        print(
          '🎉 [BACKGROUND] Sincronización completada: $totalActualizados cambios',
        );
      } catch (e) {
        print('⚠️ [BACKGROUND] Error en sincronización (no crítico): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: Color(0xFF032458),
              ),
              const SizedBox(height: 24),
              Text(
                _esPrimeraVez ? 'Crear Contraseña' : 'Verificación',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF032458),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _esPrimeraVez
                    ? 'Establece una contraseña de seguridad'
                    : 'Ingresa tu ID y contraseña',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 48),

              // ID Comercial
              TextField(
                controller: _comercialIdController,
                decoration: const InputDecoration(
                  labelText: 'ID del Comercial *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              if (_esPrimeraVez) ...[
                // Nueva contraseña
                TextField(
                  controller: _nuevaContrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Nueva Contraseña *',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    helperText: 'Mínimo 4 caracteres',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),

                // Confirmar contraseña
                TextField(
                  controller: _confirmarContrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar Contraseña *',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ] else ...[
                // Contraseña existente
                TextField(
                  controller: _contrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña *',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _validarContrasena(),
                ),
              ],

              if (_mensajeError.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _mensajeError,
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botón
              ElevatedButton(
                onPressed: _esPrimeraVez
                    ? _establecerContrasena
                    : _validarContrasena,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF032458),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _esPrimeraVez ? 'ESTABLECER CONTRASEÑA' : 'INGRESAR',
                  style: const TextStyle(
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
