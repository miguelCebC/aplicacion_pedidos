import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🟢 Importar esto
import '../database_helper.dart';

class BuscarClienteDialog extends StatefulWidget {
  const BuscarClienteDialog({super.key});

  @override
  State<BuscarClienteDialog> createState() => _BuscarClienteDialogState();
}

class _BuscarClienteDialogState extends State<BuscarClienteDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _clientes = [];
  Timer? _debounce;
  int? _comercialId; // 🟢 Variable para el ID

  @override
  void initState() {
    super.initState();
    _cargarComercial(); // 🟢 Cargar ID antes de buscar
    _searchController.addListener(_onSearchChanged);
  }

  // 🟢 Nuevo método para obtener el comercial
  Future<void> _cargarComercial() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _comercialId = prefs.getInt('comercial_id');
    });
    _buscarClientes(); // Buscar después de tener el ID
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _buscarClientes(_searchController.text);
    });
  }

  Future<void> _buscarClientes([String? busqueda]) async {
    final db = DatabaseHelper.instance;
    // 🟢 Usamos los nuevos parámetros nombrados
    final clientes = await db.obtenerClientes(
      busqueda: busqueda,
      comercialId: _comercialId,
    );
    if (mounted) {
      setState(() => _clientes = clientes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _clientes.isEmpty
                ? const Center(
                    child: Text('No se encontraron clientes asignados'),
                  )
                : ListView.builder(
                    itemCount: _clientes.length,
                    itemBuilder: (listContext, index) {
                      final cliente = _clientes[index];
                      return ListTile(
                        title: Text(cliente['nombre']),
                        subtitle: Text(
                          'ID: ${cliente['id']} - ${cliente['telefono'] ?? ''}',
                        ),
                        onTap: () => Navigator.pop(context, cliente),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
