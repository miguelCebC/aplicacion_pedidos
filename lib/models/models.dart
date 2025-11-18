import 'iva_config.dart';

class LineaPedidoData {
  final Map<String, dynamic> articulo;
  double cantidad;
  double precio;
  final double descuento;
  final String tipoIva; // G/R/S/X

  LineaPedidoData({
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0,
    this.tipoIva = 'G', // Por defecto General
  });

  // Método helper para obtener el porcentaje de IVA
  double get porcentajeIva => IvaConfig.obtenerPorcentaje(tipoIva);
}

// Clase auxiliar para líneas de detalle
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
