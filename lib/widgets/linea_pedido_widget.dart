import 'package:flutter/material.dart';
import '../models/models.dart';

class LineaPedidoWidget extends StatelessWidget {
  final LineaPedidoData linea;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onUpdate;

  const LineaPedidoWidget({
    super.key,
    required this.linea,
    required this.onDelete,
    this.onEdit,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          linea.articulo['nombre'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${linea.articulo['codigo']} - ${linea.precio}€ x ${linea.cantidad}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF032458)),
                      onPressed: onEdit,
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFF44336)),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Subtotal: ${(linea.cantidad * linea.precio).toStringAsFixed(2)}€',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF032458),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
