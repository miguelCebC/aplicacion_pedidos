import 'dart:async';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _buscarClientes(); // carga inicial
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Reinicia el timer si el usuario sigue escribiendo
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Espera 300 ms antes de buscar
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _buscarClientes(_searchController.text);
    });
  }

  Future<void> _buscarClientes([String? busqueda]) async {
    final db = DatabaseHelper.instance;
    final clientes = await db.obtenerClientes(busqueda);
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
                ? const Center(child: Text(''))
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
