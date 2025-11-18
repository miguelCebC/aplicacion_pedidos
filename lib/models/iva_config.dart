import 'package:shared_preferences/shared_preferences.dart';

class IvaConfig {
  static const String GENERAL = 'G';
  static const String REDUCIDO = 'R';
  static const String SUPERREDUCIDO = 'S';
  static const String EXENTO = 'X';

  // Valores por defecto
  static double porcentajeGeneral = 21.0;
  static double porcentajeReducido = 10.0;
  static double porcentajeSuperreducido = 4.0;
  static double porcentajeExento = 0.0;

  static double obtenerPorcentaje(String tipo) {
    switch (tipo) {
      case GENERAL:
        return porcentajeGeneral;
      case REDUCIDO:
        return porcentajeReducido;
      case SUPERREDUCIDO:
        return porcentajeSuperreducido;
      case EXENTO:
        return porcentajeExento;
      default:
        return porcentajeGeneral;
    }
  }

  static String obtenerNombre(String tipo) {
    switch (tipo) {
      case GENERAL:
        return 'General ($porcentajeGeneral%)';
      case REDUCIDO:
        return 'Reducido ($porcentajeReducido%)';
      case SUPERREDUCIDO:
        return 'Superreducido ($porcentajeSuperreducido%)';
      case EXENTO:
        return 'Exento ($porcentajeExento%)';
      default:
        return 'General ($porcentajeGeneral%)';
    }
  }

  static List<String> obtenerTipos() {
    return [GENERAL, REDUCIDO, SUPERREDUCIDO, EXENTO];
  }

  static Future<void> cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    porcentajeGeneral = prefs.getDouble('iva_general') ?? 21.0;
    porcentajeReducido = prefs.getDouble('iva_reducido') ?? 10.0;
    porcentajeSuperreducido = prefs.getDouble('iva_superreducido') ?? 4.0;
    porcentajeExento = prefs.getDouble('iva_exento') ?? 0.0;
  }

  static Future<void> guardarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('iva_general', porcentajeGeneral);
    await prefs.setDouble('iva_reducido', porcentajeReducido);
    await prefs.setDouble('iva_superreducido', porcentajeSuperreducido);
    await prefs.setDouble('iva_exento', porcentajeExento);
  }
}
