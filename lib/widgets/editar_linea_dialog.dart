import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/iva_config.dart';

class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;
  final double descuento; // Descuento General
  final double dto1;
  final double dto2;
  final double dto3;
  final String tipoIva;

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0,
    this.dto1 = 0.0,
    this.dto2 = 0.0,
    this.dto3 = 0.0,
    this.tipoIva = 'G',
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;
  late TextEditingController _descuentoController;
  late TextEditingController _dto1Controller;
  late TextEditingController _dto2Controller;
  late TextEditingController _dto3Controller;
  late String _tipoIvaSeleccionado;

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString(),
    );
    _precioController = TextEditingController(text: widget.precio.toString());

    // 🟢 Inicializamos los 4 controladores
    _descuentoController = TextEditingController(
      text: widget.descuento.toString(),
    );
    _dto1Controller = TextEditingController(text: widget.dto1.toString());
    _dto2Controller = TextEditingController(text: widget.dto2.toString());
    _dto3Controller = TextEditingController(text: widget.dto3.toString());

    _tipoIvaSeleccionado = widget.tipoIva;
    _cargarConfiguracionIva();
  }

  Future<void> _cargarConfiguracionIva() async {
    await IvaConfig.cargarConfiguracion();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _descuentoController.dispose();
    _dto1Controller.dispose();
    _dto2Controller.dispose();
    _dto3Controller.dispose();
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

            // Fila Cantidad y Precio
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cantidadController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _precioController,
                    decoration: const InputDecoration(
                      labelText: 'Precio (€)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 🟢 Descuento General
            TextField(
              controller: _descuentoController,
              decoration: const InputDecoration(
                labelText: 'Descuento General (%)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),

            // 🟢 Fila de Descuentos Adicionales
            const Text(
              'Descuentos Adicionales (%)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dto1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 1',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _dto2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 2',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _dto3Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 3',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
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
            final d1 = double.tryParse(_dto1Controller.text) ?? 0;
            final d2 = double.tryParse(_dto2Controller.text) ?? 0;
            final d3 = double.tryParse(_dto3Controller.text) ?? 0;

            Navigator.pop(
              context,
              LineaPedidoData(
                articulo: widget.articulo,
                cantidad: cantidad,
                precio: precio,
                descuento: descuento, // Guardamos el descuento general
                dto1: d1,
                dto2: d2,
                dto3: d3,
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
