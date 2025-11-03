import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';

class BuscarArticuloDialog extends StatefulWidget {
  const BuscarArticuloDialog({super.key});

  @override
  State<BuscarArticuloDialog> createState() => _BuscarArticuloDialogState();
}

class _BuscarArticuloDialogState extends State<BuscarArticuloDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _articulos = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _buscarArticulos(); // carga inicial
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
    // Cancelar el timer previo si el usuario sigue escribiendo
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Esperar 300ms antes de buscar
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _buscarArticulos(_searchController.text);
    });
  }

  Future<void> _buscarArticulos([String? busqueda]) async {
    final db = DatabaseHelper.instance;
    final articulos = await db.obtenerArticulos(busqueda);
    if (mounted) {
      setState(() => _articulos = articulos);
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
                labelText: 'Buscar artículo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _articulos.isEmpty
                ? const Center(child: Text(''))
                : ListView.builder(
                    itemCount: _articulos.length,
                    itemBuilder: (listContext, index) {
                      final articulo = _articulos[index];
                      return ListTile(
                        title: Text(articulo['nombre']),
                        subtitle: Text(
                          '${articulo['codigo']} - ${articulo['precio']}€ (Stock: ${articulo['stock']})',
                        ),
                        onTap: () => Navigator.pop(context, articulo),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
