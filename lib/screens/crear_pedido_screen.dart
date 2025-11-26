import 'dart:convert'; // Para base64
import 'dart:io'; // Para File
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // 🟢 IMPORTAR IMAGE PICKER
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';

class CrearPedidoScreen extends StatefulWidget {
  const CrearPedidoScreen({super.key});

  @override
  State<CrearPedidoScreen> createState() => _CrearPedidoScreenState();
}

class _CrearPedidoScreenState extends State<CrearPedidoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];

  // Listas para desplegables
  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _formasPago = [];
  List<Map<String, dynamic>> _direccionesCliente = [];
  int? _direccionEntregaId;
  // Selecciones
  int? _serieSeleccionadaId;
  int? _formaPagoSeleccionadaId;
  DateTime? _fechaEntrega;

  // 🟢 VARIABLE PARA LA FOTO (Temporal en memoria)
  String? _fotoBase64;

  bool _isLoading = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarMaestros();
  }

  Future<void> _cargarMaestros() async {
    final db = DatabaseHelper.instance;
    final series = await db.obtenerSeries(tipo: 'V');
    final formasPago = await db.obtenerFormasPago();

    if (mounted) {
      setState(() {
        _series = series;
        _formasPago = formasPago;
        if (_series.isNotEmpty) _serieSeleccionadaId = _series[0]['id'];
      });
    }
  }

  Future<void> _seleccionarFechaEntrega() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() => _fechaEntrega = picked);
    }
  }

  // 🟢 1. MÉTODOS PARA TOMAR FOTO
  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800, // Reducir tamaño para optimizar subida
        maxHeight: 800,
        imageQuality: 70,
      );

      if (image == null) return;

      final bytes = await File(image.path).readAsBytes();
      final String base64String = base64Encode(bytes);

      setState(() {
        _fotoBase64 = base64String;
      });
    } catch (e) {
      print('Error cámara: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _borrarFoto() {
    setState(() {
      _fotoBase64 = null;
    });
  }

  Future<void> _guardarPedido() async {
    if (_guardando) return;

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }
    if (_lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un artículo')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';
      final comercialId = prefs.getInt('comercial_id');

      if (url.isEmpty || apiKey.isEmpty)
        throw Exception('Configura la API primero');
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);

      // 🟢 1. Estructura del pedido completa
      final pedidoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'cmr': comercialId,
        'serie_id': _serieSeleccionadaId,
        'fecha': DateTime.now().toIso8601String(),
        'fecha_entrega': _fechaEntrega?.toIso8601String(),
        'forma_pago': _formaPagoSeleccionadaId,
        'direccion_entrega_id': _direccionEntregaId,
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        // Mapeo de líneas con los nuevos campos
        'lineas': _lineas
            .map(
              (linea) => {
                'articulo_id': linea.articulo['id'],
                'cantidad': linea.cantidad,
                'precio': linea.precio,
                'tipo_iva': linea.tipoIva,

                // Campos nuevos que pedías:
                'dto1': linea.dto1,
                'dto2': linea.dto2,
                'dto3': linea.dto3,

                'por_dto': linea.descuento, // Descuento general
              },
            )
            .toList(),
      };

      // 🟢 2. Llamada a la API (Usará los métodos corregidos arriba)
      final resultado = await apiService.crearPedido(pedidoData);
      final pedidoId = resultado['id'];

      // 🟢 3. Subir Foto si existe
      if (_fotoBase64 != null) {
        await apiService.actualizarFotoPedido(pedidoId, _fotoBase64);
      }

      // 4. Guardar en BD Local
      final db = DatabaseHelper.instance;
      await db.insertarPedido({
        'id': pedidoId,
        'cliente_id': _clienteSeleccionado!['id'],
        'cmr': comercialId,
        'serie_id': _serieSeleccionadaId,
        'fecha': DateTime.now().toIso8601String(),
        'fecha_entrega': _fechaEntrega?.toIso8601String(),
        'forma_pago': _formaPagoSeleccionadaId,
        'direccion_entrega_id': _direccionEntregaId,
        'observaciones': _observacionesController.text,
        'total': _calcularTotal(),
        'estado': 'Sincronizado',
        'sincronizado': 1,
      });

      for (var linea in _lineas) {
        await db.insertarLineaPedido({
          'pedido_id': pedidoId,
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
          'tipo_iva': linea.tipoIva,
          'por_descuento': linea.descuento,
          'dto1': linea.dto1,
          'dto2': linea.dto2,
          'dto3': linea.dto3,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Pedido #$pedidoId creado correctamente'),
          backgroundColor: const Color(0xFF032458),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error al crear'),
          content: SingleChildScrollView(
            child: Text(e.toString().replaceAll('Exception: ', '')),
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

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const BuscarClienteDialog(),
    );

    if (cliente != null) {
      setState(() {
        _clienteSeleccionado = cliente;
        _direccionEntregaId = null; // Reseteamos dirección anterior
        _direccionesCliente = [];
      });

      // Cargar direcciones del cliente
      final db = DatabaseHelper.instance;
      final direcciones = await db.obtenerDirecciones(ent: cliente['id']);

      setState(() {
        _direccionesCliente = direcciones;
        // Asignar automáticamente la primera dirección encontrada como default
        if (_direccionesCliente.isNotEmpty) {
          _direccionEntregaId = _direccionesCliente.first['id'];
        }
      });
    }
  }

  Future<void> _agregarLinea() async {
    if (_clienteSeleccionado == null) return;
    final articulo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const BuscarArticuloDialog(),
    );
    if (articulo != null) {
      final db = DatabaseHelper.instance;
      final precioInfo = await db.obtenerPrecioYDescuento(
        _clienteSeleccionado!['id'],
        articulo['id'],
        articulo['precio'] ?? 0.0,
      );
      if (!mounted) return;
      final linea = await showDialog<LineaPedidoData>(
        context: context,
        builder: (_) => EditarLineaDialog(
          articulo: articulo,
          cantidad: 1,
          precio: precioInfo['precio']!,
          descuento: precioInfo['descuento']!,
        ),
      );
      if (linea != null) setState(() => _lineas.add(linea));
    }
  }

  double _calcularTotal() {
    return _lineas.fold(0, (sum, l) {
      final base = l.cantidad * l.precio * (1 - (l.descuento / 100));
      return sum + (base * (1 + (l.porcentajeIva / 100)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Pedido'),
        backgroundColor: const Color(0xFF162846),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // CLIENTE
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
                        : null,
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),
                if (_clienteSeleccionado != null &&
                    _direccionesCliente.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Dirección de Entrega',
                          border: InputBorder.none,
                          icon: Icon(Icons.location_on, color: Colors.grey),
                        ),
                        value: _direccionEntregaId,
                        items: _direccionesCliente.map((dir) {
                          return DropdownMenuItem<int>(
                            value: dir['id'],
                            child: Text(
                              dir['direccion'],
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setState(() => _direccionEntregaId = v),
                      ),
                    ),
                  ),

                if (_clienteSeleccionado != null && _direccionesCliente.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Este cliente no tiene direcciones.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                // FECHA Y SERIE
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _seleccionarFechaEntrega,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Entrega (Opcional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today, size: 20),
                          ),
                          child: Text(
                            _fechaEntrega != null
                                ? '${_fechaEntrega!.day}/${_fechaEntrega!.month}/${_fechaEntrega!.year}'
                                : 'Sin fecha',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Serie',
                          border: OutlineInputBorder(),
                        ),
                        value: _serieSeleccionadaId,
                        items: _series
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s['id'],
                                child: Text(
                                  s['nombre'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _serieSeleccionadaId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // FORMA DE PAGO
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pago',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  value: _formaPagoSeleccionadaId,
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin especificar'),
                    ),
                    ..._formasPago.map(
                      (f) => DropdownMenuItem<int>(
                        value: f['id'],
                        child: Text(
                          f['nombre'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _formaPagoSeleccionadaId = v),
                ),
                const SizedBox(height: 16),

                // OBSERVACIONES
                TextField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // 🟢 SECCIÓN FOTOGRAFÍA
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.camera_alt, color: Color(0xFF032458)),
                            SizedBox(width: 8),
                            Text(
                              'Adjuntar Fotografía',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_fotoBase64 != null)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(_fotoBase64!),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 30,
                                ),
                                onPressed: _borrarFoto,
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _tomarFoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Galería'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _tomarFoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Cámara'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // BOTÓN AGREGAR ARTÍCULO
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Artículos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _agregarLinea,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF032458),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // LISTA ARTÍCULOS
                if (_lineas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No hay artículos',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._lineas.asMap().entries.map((entry) {
                    final l = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(l.articulo['nombre']),
                        subtitle: Text(
                          '${l.cantidad} x ${l.precio}€ (${l.descuento}% dto)',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              setState(() => _lineas.removeAt(entry.key)),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // BOTÓN GUARDAR
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardarPedido,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF032458),
                      foregroundColor: Colors.white,
                    ),
                    child: _guardando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'GUARDAR PEDIDO',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
