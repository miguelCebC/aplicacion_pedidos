class LineaPedidoData {
  final Map<String, dynamic> articulo;
  double cantidad;
  double precio;
  final double descuento; // 🟢 AÑADIR
  final double iva; // 🟢 AÑADIR

  LineaPedidoData({
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0, // 🟢 AÑADIR
    this.iva = 21.0,
  });
}

// Clase auxiliar para lÃ­neas de detalle
class LineaDetalle {
  final String articuloNombre;
  final String articuloCodigo;
  final double cantidad;
  final double precio;

  LineaDetalle({
    required this.articuloNombre,
    required this.articuloCodigo,
    required this.cantidad,
    required this.precio,
  });
}
