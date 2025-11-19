import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/iva_config.dart';

class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;
  final double descuento;
  final String tipoIva;

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0,
    this.tipoIva = 'G',
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;
  late TextEditingController _descuentoController;
  late String _tipoIvaSeleccionado;

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString(),
    );
    _precioController = TextEditingController(text: widget.precio.toString());
    _descuentoController = TextEditingController(
      text: widget.descuento.toString(),
    );
    _tipoIvaSeleccionado = widget.tipoIva;
    _cargarConfiguracionIva();
  }

  Future<void> _cargarConfiguracionIva() async {
    await IvaConfig.cargarConfiguracion();
    if (mounted) {
      setState(() {}); // Refrescar para mostrar porcentajes actualizados
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _descuentoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Línea'),
      content: SingleChildScrollView(
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
            const SizedBox(height: 16),
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
            DropdownButtonFormField<String>(
              initialValue: _tipoIvaSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Tipo de IVA',
                border: OutlineInputBorder(),
              ),
              items: IvaConfig.obtenerTipos().map((tipo) {
                return DropdownMenuItem(
                  value: tipo,
                  child: Text(IvaConfig.obtenerNombre(tipo)),
                );
              }).toList(),
              onChanged: (valor) {
                setState(() {
                  _tipoIvaSeleccionado = valor!;
                });
              },
            ),
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
            final descuento = double.tryParse(_descuentoController.text) ?? 0;

            Navigator.pop(
              context,
              LineaPedidoData(
                articulo: widget.articulo,
                cantidad: cantidad,
                precio: precio,
                descuento: descuento,
                tipoIva: _tipoIvaSeleccionado,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
