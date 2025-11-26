import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'editar_pedido_screen.dart';

class DetallePedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const DetallePedidoScreen({super.key, required this.pedido});

  @override
  State<DetallePedidoScreen> createState() => _DetallePedidoScreenState();
}

class _DetallePedidoScreenState extends State<DetallePedidoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<LineaDetalle> _lineas = [];
  Map<String, dynamic>? _cliente;

  String _nombreComercial = 'Cargando...';
  String _nombreSerie = 'Cargando...';
  String _nombreFormaPago = 'Cargando...';
  String _direccionEntrega = 'Cargando...';

  // 🟢 VARIABLES DE ESTADO Y BLOQUEO
  bool _isConfirmedKyro = false; // Bloqueo local basado en con_kyr
  bool _isConfirming = false; // Spinner mientras confirma
  bool _isLoading = true; // Carga inicial de datos

  // Variables Foto
  String? _fotoBase64;
  bool _cargandoFoto = false;
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // 🟢 Leer estado inicial de bloqueo (0=Falso, 1=Verdadero)
    final conKyrVal = widget.pedido['con_kyr'];
    // Verificación robusta por si viene como int, bool o string
    if (conKyrVal == 1 || conKyrVal == true || conKyrVal.toString() == 'true') {
      _isConfirmedKyro = true;
    } else {
      _isConfirmedKyro = false;
    }

    _cargarDetalle();
    _cargarFotoRemota();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 🟢 MÉTODO PARA CONFIRMAR PEDIDO
  Future<void> _confirmarPedido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Pedido'),
        content: const Text(
          '¿Deseas confirmar este pedido? Una vez confirmado, no podrás editarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF032458),
            ),
            child: const Text(
              'CONFIRMAR',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isConfirming = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      String apiKey = prefs.getString('velneo_api_key') ?? '';
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      // 1. Actualizar en API (con_kyr: true)
      await apiService.actualizarPedido(widget.pedido['id'], {
        'cliente_id': widget.pedido['cliente_id'],
        'con_kyr': true, // Enviamos boolean true
      });

      // 2. Actualizar en BD Local (con_kyr: 1)
      await db.actualizarPedido(widget.pedido['id'], {
        'con_kyr': 1,
        'sincronizado': 1,
      });

      if (!mounted) return;

      setState(() {
        _isConfirmedKyro = true; // 🟢 Bloqueamos visualmente
        _isConfirming = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pedido Confirmado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isConfirming = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cargarFotoRemota() async {
    setState(() => _cargandoFoto = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);
      final foto = await apiService.obtenerFotoPedido(widget.pedido['id']);

      if (mounted) {
        setState(() {
          _fotoBase64 = foto;
          _cargandoFoto = false;
        });
      }
    } catch (e) {
      print('Error cargando foto remota: $e');
      if (mounted) setState(() => _cargandoFoto = false);
    }
  }

  Future<void> _cargarDetalle() async {
    final db = DatabaseHelper.instance;

    // 1. Cargar Líneas
    final lineasRaw = await db.obtenerLineasPedido(widget.pedido['id']);
    final articulos = await db.obtenerArticulos();

    final lineasConArticulo = <LineaDetalle>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {
          'id': linea['articulo_id'],
          'nombre': 'Artículo no encontrado',
          'codigo': 'N/A',
        },
      );

      lineasConArticulo.add(
        LineaDetalle(
          articuloNombre: articulo['nombre'],
          articuloCodigo: articulo['codigo'],
          cantidad: (linea['cantidad'] as num).toDouble(),
          precio: (linea['precio'] as num).toDouble(),
          porDescuento: (linea['por_descuento'] as num?)?.toDouble() ?? 0.0,
          porIva: (linea['por_iva'] as num?)?.toDouble() ?? 0.0,
          tipoIva: linea['tipo_iva']?.toString() ?? 'G',
          dto1: (linea['dto1'] as num?)?.toDouble() ?? 0.0,
          dto2: (linea['dto2'] as num?)?.toDouble() ?? 0.0,
          dto3: (linea['dto3'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    // 2. Cargar Cliente
    final clientes = await db.obtenerClientes();
    final cliente = clientes.firstWhere(
      (c) => c['id'] == widget.pedido['cliente_id'],
      orElse: () => {
        'id': widget.pedido['cliente_id'],
        'nombre': 'Desconocido',
      },
    );

    String dirNombre = 'Principal del cliente';
    if (widget.pedido['direccion_entrega_id'] != null &&
        widget.pedido['direccion_entrega_id'] != 0) {
      dirNombre = await db.obtenerDireccionPorId(
        widget.pedido['direccion_entrega_id'],
      );
    } else {
      if (cliente != null) dirNombre = cliente['direccion'] ?? 'Principal';
    }

    String nomCmr = 'Sin asignar';
    if (widget.pedido['cmr'] != null && widget.pedido['cmr'] != 0) {
      final cmr = await db.obtenerComercialPorId(widget.pedido['cmr']);
      if (cmr != null) nomCmr = cmr['nombre'];
    }

    String nomSerie = 'General';
    if (widget.pedido['serie_id'] != null && widget.pedido['serie_id'] != 0) {
      nomSerie = await db.obtenerNombreSerie(widget.pedido['serie_id']);
    }

    String nomFpg = 'No especificada';
    if (widget.pedido['forma_pago'] != null &&
        widget.pedido['forma_pago'] != 0) {
      nomFpg = await db.obtenerNombreFormaPago(widget.pedido['forma_pago']);
    }

    if (mounted) {
      setState(() {
        _lineas = lineasConArticulo;
        _cliente = cliente;
        _nombreComercial = nomCmr;
        _nombreSerie = nomSerie;
        _nombreFormaPago = nomFpg;
        _direccionEntrega = dirNombre;
        _isLoading = false;
      });
    }
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(fechaStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (e) {
      return fechaStr;
    }
  }

  // --- MÉTODOS PARA GESTIONAR LA FOTO ---

  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _subiendoFoto = true);

      final bytes = await File(image.path).readAsBytes();
      final String base64String = base64Encode(bytes);

      await _subirFotoAPI(base64String);
    } catch (e) {
      print('Error cámara: $e');
      setState(() => _subiendoFoto = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarFoto() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Foto'),
        content: const Text('¿Seguro que quieres borrar la foto del servidor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _subiendoFoto = true);
      await _subirFotoAPI(null);
    }
  }

  Future<void> _subirFotoAPI(String? base64String) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      String apiKey = prefs.getString('velneo_api_key') ?? '';
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);

      final success = await apiService.actualizarFotoPedido(
        widget.pedido['id'],
        base64String,
      );

      if (success) {
        setState(() {
          _fotoBase64 = base64String;
          _subiendoFoto = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              base64String == null
                  ? 'Foto eliminada'
                  : 'Foto subida correctamente',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _subiendoFoto = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error conexión: $e')));
    }
  }

  // --- WIDGETS DE PESTAÑAS ---

  Widget _buildTabCabecera() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 🟢 AVISO VISUAL SI ESTÁ CONFIRMADO
          if (_isConfirmedKyro)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Pedido Confirmado',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Datos Generales',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF032458),
                    ),
                  ),
                  const Divider(),
                  _buildInfoRow('Nº Pedido', widget.pedido['numero'] ?? '-'),
                  _buildInfoRow(
                    'Fecha',
                    _formatearFecha(widget.pedido['fecha']),
                  ),
                  const Divider(),
                  _buildInfoRow('Cliente', _cliente?['nombre'] ?? '...'),
                  _buildInfoRow('Dirección', _direccionEntrega),
                  _buildInfoRow('Comercial', _nombreComercial),
                  _buildInfoRow('Forma Pago', _nombreFormaPago),
                  _buildInfoRow('Serie', _nombreSerie),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF032458).withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.pedido['total']?.toStringAsFixed(2) ?? '0.00'} €',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF032458),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabLineas() {
    if (_lineas.isEmpty) return const Center(child: Text('No hay líneas'));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _lineas.length,
      itemBuilder: (context, index) {
        final l = _lineas[index];
        // Cálculo visual
        double pNeto = l.precio;
        if (l.dto1 > 0) pNeto *= (1 - l.dto1 / 100);
        if (l.dto2 > 0) pNeto *= (1 - l.dto2 / 100);
        if (l.dto3 > 0) pNeto *= (1 - l.dto3 / 100);
        final subtotal = l.cantidad * pNeto;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              l.articuloNombre,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${l.cantidad} x ${l.precio.toStringAsFixed(2)}€'),
            trailing: Text(
              '${subtotal.toStringAsFixed(2)}€',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabObservaciones() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.pedido['observaciones'] ?? 'Sin observaciones.',
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildTabFoto() {
    if (_cargandoFoto) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_subiendoFoto) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sincronizando...'),
          ],
        ),
      );
    }

    bool tieneFoto = _fotoBase64 != null && _fotoBase64!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: tieneFoto
                  ? Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          base64Decode(_fotoBase64!),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                Text('Error imagen'),
                              ],
                            );
                          },
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sin foto asignada',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          ),
          // Solo mostrar botones si no está confirmado
          if (!_isConfirmedKyro) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _tomarFoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF032458),
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _tomarFoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF032458),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (tieneFoto) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _eliminarFoto,
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  'Eliminar Foto',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 VARIABLE DE BLOQUEO DEFINIDA AQUÍ
    final bool isBloqueado = _isConfirmedKyro;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido ${widget.pedido['numero'] ?? ''}'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'DATOS'),
            Tab(text: 'DETALLE'),
            Tab(text: 'OBSERV.'),
            Tab(text: 'FOTO'),
          ],
        ),
        actions: [
          // 2. Botón Confirmar (Visible si NO está bloqueado)
          if (!isBloqueado)
            IconButton(
              icon: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.check_circle_outline,
                      color: Colors.greenAccent,
                    ),
              tooltip: 'Confirmar y Bloquear Pedido',
              onPressed: _isConfirming ? null : _confirmarPedido,
            ),

          // 3. Botón Editar (Visible si NO está bloqueado, Candado si lo está)
          if (!isBloqueado)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar Pedido',
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarPedidoScreen(pedido: widget.pedido),
                  ),
                );
                if (resultado == true) {
                  setState(() => _isLoading = true);
                  await _cargarDetalle();
                  // Recargar estado desde DB por seguridad
                  final db = DatabaseHelper.instance;
                  final ped = (await db.obtenerPedidos()).firstWhere(
                    (p) => p['id'] == widget.pedido['id'],
                  );
                  final val = ped['con_kyr'];
                  setState(() {
                    _isConfirmedKyro =
                        (val == 1 || val == true || val.toString() == 'true');
                  });
                }
              },
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 12.0),
              child: Icon(Icons.lock, color: Colors.grey),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabCabecera(),
                _buildTabLineas(),
                _buildTabObservaciones(),
                _buildTabFoto(),
              ],
            ),
    );
  }
}
