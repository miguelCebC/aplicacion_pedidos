import 'package:flutter/material.dart';
import '../models/models.dart';

class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString(),
    );
    _precioController = TextEditingController(text: widget.precio.toString());
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Línea'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.articulo['nombre'],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            widget.articulo['codigo'],
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _cantidadController,
            decoration: const InputDecoration(
              labelText: 'Cantidad',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _precioController,
            decoration: const InputDecoration(
              labelText: 'Precio Unitario (€)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final cantidad = double.tryParse(_cantidadController.text) ?? 1;
            final precio = double.tryParse(_precioController.text) ?? 0;

            Navigator.pop(
              context,
              LineaPedidoData(
                articulo: widget.articulo,
                cantidad: cantidad,
                precio: precio,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
