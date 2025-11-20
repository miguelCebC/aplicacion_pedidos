import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

class DetalleArticuloScreen extends StatefulWidget {
  final Map<String, dynamic> articulo;

  const DetalleArticuloScreen({super.key, required this.articulo});

  @override
  State<DetalleArticuloScreen> createState() => _DetalleArticuloScreenState();
}

class _DetalleArticuloScreenState extends State<DetalleArticuloScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _nombreProveedor = 'Cargando...';
  String _nombreFamilia = 'Cargando...';

  // 🟢 VARIABLES PARA LA IMAGEN
  String? _imagenBase64;
  bool _cargandoImagen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 1. Cargar imagen inicial (vendrá vacía de la lista optimizada)
    _imagenBase64 = widget.articulo['img'];

    _cargarDatosExtendidos();

    // 2. 🟢 SI NO HAY IMAGEN, LA PEDIMOS A LA API
    if (_imagenBase64 == null || _imagenBase64!.isEmpty) {
      _descargarImagenFull();
    }
  }

  // 🟢 MÉTODO NUEVO: Llama a la API para traer la foto
  Future<void> _descargarImagenFull() async {
    if (!mounted) return;
    setState(() => _cargandoImagen = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isNotEmpty && apiKey.isNotEmpty) {
        if (!url.startsWith('http')) url = 'https://$url';

        final apiService = VelneoAPIService(url, apiKey);

        // Llamada al método corregido del paso 1
        final detalle = await apiService.obtenerDetalleArticulo(
          widget.articulo['id'],
        );

        if (mounted &&
            detalle != null &&
            detalle['img'] != null &&
            detalle['img'].isNotEmpty) {
          setState(() {
            _imagenBase64 = detalle['img'];
          });
        }
      }
    } catch (e) {
      print('Error cargando imagen remota: $e');
    } finally {
      if (mounted) setState(() => _cargandoImagen = false);
    }
  }

  // ... dentro de _DetalleArticuloScreenState ...

  Widget _buildImagen() {
    // A. Cargando
    if (_cargandoImagen) {
      return Container(
        height: 200,
        color: Colors.grey[100],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text(
                'Cargando foto...',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // B. Si está vacía o es nula -> 🟢 AQUÍ PONEMOS EL ICONO DE CAJA (inventory_2)
    if (_imagenBase64 == null || _imagenBase64!.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.inventory_2, size: 80, color: Colors.grey),
        ), // 🟢 CAMBIADO
      );
    }

    // C. Mostrar imagen
    try {
      final bytes = base64Decode(_imagenBase64!);
      return Image.memory(
        bytes,
        height: 200,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 200,
            color: Colors.grey[200],
            child: const Center(
              child: Icon(Icons.inventory_2, size: 80, color: Colors.grey),
            ), // 🟢 CAMBIADO
          );
        },
      );
    } catch (e) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: const Icon(
          Icons.inventory_2,
          size: 80,
          color: Colors.grey,
        ), // 🟢 CAMBIADO
      );
    }
  }

  Future<void> _cargarDatosExtendidos() async {
    final db = DatabaseHelper.instance;

    // Proveedor
    if (widget.articulo['proveedor_id'] != null &&
        widget.articulo['proveedor_id'] != 0) {
      final nombre = await db.obtenerNombreCliente(
        widget.articulo['proveedor_id'],
      );
      if (mounted) setState(() => _nombreProveedor = nombre);
    } else {
      if (mounted) setState(() => _nombreProveedor = 'No asignado');
    }

    // 🟢 FAMILIA: Nos aseguramos de convertirlo a String de forma segura
    final familiaId = widget.articulo['familia'];
    if (familiaId != null &&
        familiaId.toString().isNotEmpty &&
        familiaId.toString() != '0') {
      // Pasamos el ID tal cual, el helper decidirá cómo buscarlo
      final nombreFam = await db.obtenerNombreFamilia(familiaId.toString());
      if (mounted) setState(() => _nombreFamilia = nombreFam);
    } else {
      if (mounted) setState(() => _nombreFamilia = 'Sin familia');
    }
  }

  Widget _buildFilaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF032458),
              ),
            ),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha Artículo'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Datos'),
            Tab(icon: Icon(Icons.price_change_outlined), text: 'Tarifas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Pestaña 1: DATOS
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _buildImagen()), // 🟢 Usamos el nuevo widget
                const SizedBox(height: 24),
                const Text(
                  'Información General',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _buildFilaDato('Nombre:', widget.articulo['nombre'] ?? ''),
                _buildFilaDato(
                  'Ref / Código:',
                  widget.articulo['codigo'] ?? '',
                ),
                _buildFilaDato('Familia:', _nombreFamilia),
                _buildFilaDato('Proveedor:', _nombreProveedor),
                _buildFilaDato(
                  'Cod. Barras:',
                  widget.articulo['codigo_barras'] ?? 'N/A',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF032458).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PRECIO BASE:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${widget.articulo['precio']}€',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Color(0xFF032458),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pestaña 2: TARIFAS
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.obtenerTarifasPorArticulo(
              widget.articulo['id'],
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tarifas = snapshot.data ?? [];
              if (tarifas.isEmpty) {
                return const Center(child: Text('No hay tarifas especiales'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tarifas.length,
                separatorBuilder: (ctx, i) => const Divider(),
                itemBuilder: (context, index) {
                  final tarifa = tarifas[index];
                  return ListTile(
                    leading: const Icon(Icons.tag, color: Color(0xFF032458)),
                    title: Text(tarifa['nombre_tarifa'] ?? 'Tarifa General'),
                    subtitle: Text('Descuento: ${tarifa['por_descuento']}%'),
                    trailing: Text(
                      '${tarifa['precio']}€',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
