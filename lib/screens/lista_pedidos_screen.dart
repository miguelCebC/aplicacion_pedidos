import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_pedido_screen.dart';

class ListaPedidosScreen extends StatefulWidget {
  const ListaPedidosScreen({super.key});

  @override
  State<ListaPedidosScreen> createState() => _ListaPedidosScreenState();
}

class _ListaPedidosScreenState extends State<ListaPedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    final db = DatabaseHelper.instance;
    final pedidos = await db.obtenerPedidos();
    setState(() => _pedidos = pedidos);
  }

  String _formatearFecha(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return fecha;
    }
  }

  Future<void> _sincronizarPedidosPendientes() async {
    // Obtener pedidos no sincronizados
    final pedidosPendientes = _pedidos
        .where((p) => p['sincronizado'] == 0)
        .toList();

    if (pedidosPendientes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay pedidos pendientes de sincronizar'),
          backgroundColor: Color(0xFF032458),
        ),
      );
      return;
    }

    // Confirmar sincronización
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sincronizar Pedidos'),
        content: Text(
          'Â¿Deseas sincronizar ${pedidosPendientes.length} pedido(s) pendiente(s) con Velneo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _sincronizando = true);

    // Forzar actualización de UI antes de operación pesada
    await Future.delayed(const Duration(milliseconds: 100));

    int exitosos = 0;
    int fallidos = 0;
    final errores = <String>[];

    try {
      // Obtener configuración desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String url =
          prefs.getString('velneo_url') ??
          'tecerp.nunsys.com:4311/TORRAL/TecERPv7_dat_dat/v1';
      final String apiKey = prefs.getString('velneo_api_key') ?? '1234';

      // Asegurar que la URL tenga el protocolo
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      for (var pedido in pedidosPendientes) {
        try {
          print('Sincronizando pedido #${pedido['id']}...');

          // Obtener lÃ­neas del pedido
          final lineas = await db.obtenerLineasPedido(pedido['id']);

          if (lineas.isEmpty) {
            throw Exception('El pedido no tiene lÃ­neas');
          }

          // Preparar datos del pedido para Velneo
          final pedidoData = {
            'cliente_id': pedido['cliente_id'],
            'fecha': pedido['fecha'],
            'observaciones': pedido['observaciones'] ?? '',
            'total': pedido['total'],
            'lineas': lineas
                .map(
                  (linea) => {
                    'articulo_id': linea['articulo_id'],
                    'cantidad': linea['cantidad'],
                    'precio': linea['precio'],
                  },
                )
                .toList(),
          };

          // Enviar a Velneo con timeout
          final resultado = await apiService
              .crearPedido(pedidoData)
              .timeout(const Duration(seconds: 45));

          print('âœ“ Pedido #${pedido['id']} sincronizado: $resultado');

          // Marcar como sincronizado
          await db.actualizarPedidoSincronizado(pedido['id'], 1);

          exitosos++;

          // PequeÃ±a pausa entre pedidos
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('âœ— Error al sincronizar pedido ${pedido['id']}: $e');
          fallidos++;
          final errorMsg = e.toString().replaceAll('Exception: ', '');
          errores.add('Pedido #${pedido['id']}: $errorMsg');
        }
      }

      setState(() => _sincronizando = false);
      await _cargarPedidos();

      if (!mounted) return;

      // Mostrar resultado
      if (fallidos == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'âœ“ $exitosos pedido(s) sincronizado(s) correctamente',
            ),
            backgroundColor: const Color(0xFF032458),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Resultado de Sincronización'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('âœ“ Exitosos: $exitosos'),
                  Text('âœ— Fallidos: $fallidos'),
                  if (errores.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Errores:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...errores.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(e, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
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
    } catch (e) {
      setState(() => _sincronizando = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFF44336),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidosPendientes = _pedidos
        .where((p) => p['sincronizado'] == 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lista de Pedidos'),
            if (pedidosPendientes > 0)
              Text(
                '$pedidosPendientes pendiente(s)',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          if (pedidosPendientes > 0)
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
                  : const Icon(Icons.cloud_upload),
              onPressed: _sincronizando ? null : _sincronizarPedidosPendientes,
              tooltip: 'Sincronizar pedidos pendientes',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarPedidos,
            tooltip: 'Recargar lista',
          ),
        ],
      ),
      body: _pedidos.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay pedidos',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _pedidos.length,
              itemBuilder: (context, index) {
                final pedido = _pedidos[index];
                final esSincronizado = pedido['sincronizado'] == 1;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: esSincronizado
                          ? const Color(0xFF032458)
                          : const Color(0xFFF44336),
                      child: Icon(
                        esSincronizado ? Icons.cloud_done : Icons.cloud_off,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      'Pedido #${pedido['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cliente ID: ${pedido['cliente_id']}'),
                        Text(_formatearFecha(pedido['fecha'])),
                        if (pedido['total'] != null)
                          Text(
                            'Total: ${pedido['total'].toStringAsFixed(2)}€',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF032458),
                            ),
                          ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        esSincronizado ? 'Sincronizado' : 'Pendiente',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: esSincronizado
                          ? const Color(0xFFCAD3E2)
                          : const Color(0xFFFFC107),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DetallePedidoScreen(pedido: pedido),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
