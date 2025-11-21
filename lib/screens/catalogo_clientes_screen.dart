import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'detalle_cliente_screen.dart'; //
import 'crear_cliente_screen.dart';

class CatalogoClientesScreen extends StatefulWidget {
  const CatalogoClientesScreen({super.key});

  @override
  State<CatalogoClientesScreen> createState() => _CatalogoClientesScreenState();
}

class _CatalogoClientesScreenState extends State<CatalogoClientesScreen> {
  final List<Map<String, dynamic>> _clientes = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  int? _comercialId; // Para filtrar solo mis clientes

  @override
  void initState() {
    super.initState();
    _cargarComercialYClientes();

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

  Future<void> _cargarComercialYClientes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _comercialId = prefs.getInt('comercial_id');
    });
    _cargarClientes(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _cargarClientes(reset: true);
    });
  }

  // En lib/screens/catalogo_clientes_screen.dart

  Future<void> _cargarClientes({bool reset = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (reset) {
        _clientes.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });

    try {
      // 🟢 CHIVATO 1: Ver qué ID estamos usando
      print(
        '🕵️ [DEBUG] Buscando clientes para el Comercial ID: $_comercialId',
      );

      final db = DatabaseHelper.instance;
      final nuevosClientes = await db.obtenerClientesPaginados(
        busqueda: _searchController.text,
        comercialId: _comercialId,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      // 🟢 CHIVATO 2: Ver cuántos ha encontrado
      print('🕵️ [DEBUG] Encontrados: ${nuevosClientes.length} clientes');
      if (nuevosClientes.isNotEmpty) {
        print(
          '   -> Ejemplo Cliente 1: ${nuevosClientes[0]['nombre']} (CMR: ${nuevosClientes[0]['cmr']})',
        );
      }

      if (mounted) {
        setState(() {
          if (nuevosClientes.length < _pageSize) {
            _hasMore = false;
          }
          _clientes.addAll(nuevosClientes);
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Error cargando clientes: $e');
    }
  }

  // Icono de perfil para el cliente (ya que no tienen foto)
  Widget _buildAvatarCliente() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF032458).withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Icon(Icons.person, size: 30, color: Color(0xFF032458)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Clientes'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar nombre, NIF, teléfono...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Mostrando ${_clientes.length} clientes',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _clientes.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No se encontraron clientes',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _clientes.length + (_hasMore ? 1 : 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      if (index == _clientes.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final cliente = _clientes[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            // 🟢 Navegar al detalle del cliente
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    DetalleClienteScreen(cliente: cliente),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                _buildAvatarCliente(),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cliente['nombre'] ?? 'Sin nombre',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF032458),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      if (cliente['nom_com'] != null &&
                                          cliente['nom_com'] != '')
                                        Text(
                                          cliente['nom_com'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone,
                                            size: 14,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            cliente['telefono'] ?? '---',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        cliente['direccion'] ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Navegar a la pantalla de creación
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CrearClienteScreen()),
          );
          // Si se creó un cliente (return true), recargamos la lista
          if (resultado == true) {
            _cargarClientes(reset: true);
          }
        },
        backgroundColor: const Color(0xFF032458),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
