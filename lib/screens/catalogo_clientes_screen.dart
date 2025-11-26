import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_cliente_screen.dart';

class CatalogoClientesScreen extends StatefulWidget {
  const CatalogoClientesScreen({super.key});

  @override
  State<CatalogoClientesScreen> createState() => CatalogoClientesScreenState();
}

class CatalogoClientesScreenState extends State<CatalogoClientesScreen> {
  final List<Map<String, dynamic>> _clientes = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  int? _comercialId;

  @override
  void initState() {
    super.initState();
    _cargarComercialYClientes();
    // Sync fondo
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarFondo());

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _cargarClientes();
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _sincronizarFondo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final key = prefs.getString('velneo_api_key');
      if (url == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        key!,
      );
      final res = await api.obtenerClientes();
      final lista = res['clientes'] as List;

      if (lista.isNotEmpty) {
        await DatabaseHelper.instance.insertarClientesLote(lista.cast());
        if (mounted) _cargarClientes(reset: true);
      }
    } catch (e) {
      print("Error sync clientes: $e");
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void recargarClientes() => _cargarClientes(reset: true);

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _cargarClientes(reset: true),
    );
  }

  Future<void> _cargarComercialYClientes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _comercialId = prefs.getInt('comercial_id'));
    _cargarClientes(reset: true);
  }

  Future<void> _cargarClientes({bool reset = false}) async {
    if (_isLoading && !reset) return;
    setState(() {
      _isLoading = true;
      if (reset) {
        _clientes.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });

    try {
      final nuevos = await DatabaseHelper.instance.obtenerClientesPaginados(
        busqueda: _searchController.text,
        comercialId: _comercialId,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      if (mounted) {
        setState(() {
          if (nuevos.length < _pageSize) _hasMore = false;
          _clientes.addAll(nuevos);
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _clientes.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _clientes.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final c = _clientes[index];
              final direccion = c['direccion'] ?? '';

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    c['nombre'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // 🟢 AÑADIDA DIRECCIÓN AQUÍ TAMBIÉN
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['telefono'] ?? c['email'] ?? 'Sin contacto'),
                      if (direccion.isNotEmpty)
                        Text(
                          direccion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetalleClienteScreen(cliente: c),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
