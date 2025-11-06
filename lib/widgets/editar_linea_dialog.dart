import 'package:flutter/material.dart';
import '../models/models.dart';

class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;
  final double descuento; // 🟢 AÑADIR
  final double iva; // 🟢 AÑADIR

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0, // 🟢 AÑADIR
    this.iva = 21.0, // 🟢 AÑADIR
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;
  late TextEditingController _descuentoController; // 🟢 AÑADIR
  late TextEditingController _ivaController; // 🟢 AÑADIR

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString(),
    );
    _precioController = TextEditingController(text: widget.precio.toString());
    _descuentoController = TextEditingController(
      text: widget.descuento.toString(), // 🟢 AÑADIR
    );
    _ivaController = TextEditingController(
      text: widget.iva.toString(), // 🟢 AÑADIR
    );
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _descuentoController.dispose(); // 🟢 AÑADIR
    _ivaController.dispose(); // 🟢 AÑADIR
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Línea'),
      content: SingleChildScrollView(
        // 🟢 Envuelto para evitar overflow
        child: Column(
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _precioController,
              decoration: const InputDecoration(
                labelText: 'Precio Unitario (€)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16), // 🟢 INICIO CAMPOS NUEVOS
            TextField(
              controller: _descuentoController,
              decoration: const InputDecoration(
                labelText: 'Descuento (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ivaController,
              decoration: const InputDecoration(
                labelText: 'IVA (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ), // 🟢 FIN CAMPOS NUEVOS
          ],
        ),
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
            final descuento =
                double.tryParse(_descuentoController.text) ?? 0; // 🟢 AÑADIR
            final iva = double.tryParse(_ivaController.text) ?? 21; // 🟢 AÑADIR

            Navigator.pop(
              context,
              LineaPedidoData(
                // 🟢 Asegúrate de que el modelo acepte esto
                articulo: widget.articulo,
                cantidad: cantidad,
                precio: precio,
                descuento: descuento,
                iva: iva,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
