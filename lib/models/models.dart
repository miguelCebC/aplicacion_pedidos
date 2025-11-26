import 'iva_config.dart';

class LineaPedidoData {
  final Map<String, dynamic> articulo;
  double cantidad;
  double precio;
  double descuento; // Descuento general
  double dto1; // Descuento 1
  double dto2; // Descuento 2
  double dto3; // Descuento 3
  final String tipoIva;

  LineaPedidoData({
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0,
    this.dto1 = 0.0,
    this.dto2 = 0.0,
    this.dto3 = 0.0,
    this.tipoIva = 'G',
  });

  double get porcentajeIva => IvaConfig.obtenerPorcentaje(tipoIva);

  // Cálculo asumiendo siempre Porcentaje (%)
  double get precioNeto {
    double neto = precio;
    if (descuento != 0) neto = neto * (1 - (descuento / 100));
    if (dto1 != 0) neto = neto * (1 - (dto1 / 100));
    if (dto2 != 0) neto = neto * (1 - (dto2 / 100));
    if (dto3 != 0) neto = neto * (1 - (dto3 / 100));
    return neto;
  }
}

class LineaDetalle {
  final String articuloNombre;
  final String articuloCodigo;
  final double cantidad;
  final double precio;
  final double porDescuento;
  final double dto1;
  final double dto2;
  final double dto3;
  final double porIva;
  final String tipoIva;

  LineaDetalle({
    required this.articuloNombre,
    required this.articuloCodigo,
    required this.cantidad,
    required this.precio,
    this.porDescuento = 0.0,
    this.dto1 = 0.0,
    this.dto2 = 0.0,
    this.dto3 = 0.0,
    this.porIva = 0.0,
    this.tipoIva = 'G',
  });
}
