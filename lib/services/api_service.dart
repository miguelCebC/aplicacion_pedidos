import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../screens/debug_logs_screen.dart';

class VelneoAPIService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client = http.Client();
  final Function(String)? onLog; // ← AÑADIR ESTA LÍNEA

  VelneoAPIService(
    this.baseUrl,
    this.apiKey, {
    this.onLog,
  }); // ← MODIFICAR CONSTRUCTOR

  void _log(String message) {
    if (onLog != null) {
      onLog!(message);
    }
    print(message);
  }

  static http.Client createHttpClient() {
    return http.Client();
  }

  String _buildUrl(String endpoint) {
    return '$baseUrl$endpoint?api_key=$apiKey';
  }

  Future<http.Response> _getWithSSL(String url) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);

    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      return http.Response(
        stringData,
        response.statusCode,
        headers: {
          'content-type':
              response.headers.contentType?.toString() ?? 'application/json',
        },
      );
    } finally {
      httpClient.close();
    }
  }

  // MÃ©todo auxiliar para construir URL con parámetros
  String _buildUrlWithParams(String endpoint, Map<String, String>? params) {
    final uri = Uri.parse('$baseUrl$endpoint');
    final queryParams = {'api_key': apiKey};
    if (params != null) {
      queryParams.addAll(params);
    }
    return uri.replace(queryParameters: queryParams).toString();
  }

  Future<List<dynamic>> obtenerArticulos() async {
    try {
      final allArticulos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      print('🛑 Descargando artículos...');

      while (true) {
        final url = _buildUrlWithParams('/ART_M', {
          'page': page.toString(),
          'page_size': pageSize.toString(),
        });

        print('  🛑 Página $page');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
            }

            if (data['art_m'] != null && data['art_m'] is List) {
              final articulosList = data['art_m'] as List;

              if (articulosList.isEmpty) {
                print('  🛑 No hay más artículos, finalizando');
                break;
              }

              final articulos = articulosList.map((articulo) {
                return {
                  'id': articulo['id'],
                  'codigo': articulo['ref'] ?? '',
                  'nombre': articulo['name'] ?? 'Sin nombre',
                  'descripcion': articulo['name'] ?? 'Sin descripción',
                  'precio': _convertirADouble(articulo['pvp']),
                  'stock': articulo['exs'] ?? 0,
                };
              }).toList();

              allArticulos.addAll(articulos);
              print(
                '  ✓ Página $page: ${articulos.length} artículos (Acumulado: ${allArticulos.length}/$totalCount)',
              );

              // Si esta página tiene menos de pageSize, es la última
              if (articulos.length < pageSize) {
                print('  🛑 Última página (${articulos.length} < $pageSize)');
                break;
              }

              // Si ya tenemos todos los registros según total_count
              if (totalCount > 0 && allArticulos.length >= totalCount) {
                print(
                  '  ðŸ   Total alcanzado (${allArticulos.length} >= $totalCount)',
                );
                break;
              }

              // Continuar a la siguiente página
              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              print('  ðŸ   No hay campo art_m en respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('â Œ Error en página $page: $e');
          if (allArticulos.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      print('🛑 TOTAL artículos: ${allArticulos.length}');
      return allArticulos;
    } catch (e) {
      print('🛑 Error en obtenerArticulos: $e');
      rethrow;
    }
  }

  double _convertirADouble(dynamic valor) {
    if (valor == null) return 0.0;
    if (valor is double) return valor;
    if (valor is int) return valor.toDouble();
    if (valor is String) return double.tryParse(valor) ?? 0.0;
    return 0.0;
  }

  Future<Map<String, dynamic>> obtenerClientes() async {
    try {
      final allClientes = <dynamic>[];
      final allComerciales = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      print('📄 Descargando clientes...');

      while (true) {
        final url = _buildUrlWithParams('/ENT_M', {
          'page': page.toString(),
          'page_size': pageSize.toString(),
        });

        print('  📥 Página $page');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
            }

            if (data['ent_m'] != null && data['ent_m'] is List) {
              final entidadesList = data['ent_m'] as List;

              if (entidadesList.isEmpty) {
                print('  🏁 No hay más registros, finalizando');
                break;
              }

              for (var entidad in entidadesList) {
                final registro = {
                  'id': entidad['id'],
                  'nombre': entidad['nom_fis'] ?? 'Sin nombre',
                  'email': entidad['eml'] ?? '',
                  'telefono': entidad['tlf'] ?? '',
                  'direccion': entidad['dir'] ?? '',
                };

                // Separar según es_cmr
                if (entidad['es_cmr'] == true) {
                  allComerciales.add(registro);
                } else {
                  allClientes.add(registro);
                }
              }

              print(
                '  ✅ Página $page: ${entidadesList.length} registros (Clientes: ${allClientes.length}, Comerciales: ${allComerciales.length})',
              );

              if (entidadesList.length < pageSize) {
                print(
                  '  🏁 Última página (${entidadesList.length} < $pageSize)',
                );
                break;
              }

              if (totalCount > 0 &&
                  (allClientes.length + allComerciales.length) >= totalCount) {
                print(
                  '  🏁 Total alcanzado (${allClientes.length + allComerciales.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              print('  🏁 No hay campo ent_m en respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('❌ Error en página $page: $e');
          if (allClientes.isEmpty && allComerciales.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      print('✅ TOTAL clientes: ${allClientes.length}');
      print('✅ TOTAL comerciales: ${allComerciales.length}');

      return {'clientes': allClientes, 'comerciales': allComerciales};
    } catch (e) {
      print('❌ Error en obtenerClientes: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerCampanas() async {
    try {
      print('📄 Descargando campañas comerciales...');

      final url = _buildUrlWithParams('/CRM_CAM_COM', {
        'page': '1',
        'page_size': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['crm_cam_com'] != null && data['crm_cam_com'] is List) {
          final campanasList = (data['crm_cam_com'] as List).map((campana) {
            return {
              'id': campana['id'],
              'nombre': campana['name'] ?? 'Sin nombre',
              'fecha_inicio': campana['fch_ini'],
              'fecha_fin': campana['fch_fin'],
              'sector': campana['sec'] ?? 0,
              'provincia_id': campana['pro_m'] ?? 0,
              'poblacion_id': campana['pob'] ?? 0,
            };
          }).toList();

          print('✅ ${campanasList.length} campañas descargadas');
          return campanasList;
        }
      }

      throw Exception('Error al obtener campañas: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerCampanas: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerTiposVisita() async {
    try {
      print('📄 Descargando tipos de visita...');

      final url = _buildUrlWithParams('/TIP_VIS', {
        'page': '1',
        'page_size': '50',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['tip_vis'] != null && data['tip_vis'] is List) {
          final tiposList = (data['tip_vis'] as List).map((tipo) {
            return {'id': tipo['id'], 'nombre': tipo['name'] ?? 'Sin nombre'};
          }).toList();

          print('✅ ${tiposList.length} tipos de visita descargados');
          return tiposList;
        }
      }

      throw Exception(
        'Error al obtener tipos de visita: ${response.statusCode}',
      );
    } catch (e) {
      print('❌ Error en obtenerTiposVisita: $e');
      rethrow;
    }
  }
  // Añade estos métodos en api_service.dart

  Future<List<dynamic>> obtenerLineasPedido(int pedidoId) async {
    try {
      _log('📄 Descargando líneas del pedido $pedidoId...');

      final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
        'vta_ped': pedidoId.toString(),
        'page_size': '100',
      });

      _log('🌐 URL líneas pedido: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status code líneas pedido: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['vta_ped_lin_g'] != null && data['vta_ped_lin_g'] is List) {
          final lineasList = (data['vta_ped_lin_g'] as List).map((linea) {
            _log(
              '  → Línea: Art ${linea['art']} - Cant: ${linea['can_ped']} - Precio: ${linea['pre']}',
            );
            return {
              //     👇 USA EL ID DE LA 'linea'
              'pedido_id': linea['vta_ped'] ?? pedidoId, // <-- ✅ CORRECCIÓN
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can_ped']),
              'precio': _convertirADouble(linea['pre']),
            };
          }).toList();

          _log('✅ ${lineasList.length} líneas de pedido descargadas');
          return lineasList;
        } else {
          _log('⚠️ No se encontraron líneas para el pedido $pedidoId');
          return [];
        }
      }

      throw Exception(
        'Error al obtener líneas de pedido: ${response.statusCode}',
      );
    } catch (e) {
      _log('❌ Error en obtenerLineasPedido: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerLineasPresupuesto(int presupuestoId) async {
    try {
      _log('📄 Descargando líneas del presupuesto $presupuestoId...');

      final url = _buildUrlWithParams('/VTA_PRE_LIN_G', {
        'vta_pre': presupuestoId.toString(),
        'page_size': '100',
      });

      _log('🌐 URL líneas presupuesto: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status code líneas presupuesto: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['vta_pre_lin_g'] != null && data['vta_pre_lin_g'] is List) {
          final lineasList = (data['vta_pre_lin_g'] as List).map((linea) {
            _log(
              '  → Línea: Art ${linea['art']} - Cant: ${linea['can']} - Precio: ${linea['pre']}',
            );
            return {
              //     👇 USA EL ID DE LA 'linea'
              'presupuesto_id':
                  linea['vta_pre'] ?? presupuestoId, // <-- ✅ CORRECCIÓN
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can']),
              'precio': _convertirADouble(linea['pre']),
            };
          }).toList();

          _log('✅ ${lineasList.length} líneas de presupuesto descargadas');
          return lineasList;
        } else {
          _log(
            '⚠️ No se encontraron líneas para el presupuesto $presupuestoId',
          );
          return [];
        }
      }

      throw Exception(
        'Error al obtener líneas de presupuesto: ${response.statusCode}',
      );
    } catch (e) {
      _log('❌ Error en obtenerLineasPresupuesto: $e');
      return [];
    }
  }
  // [DENTRO DE services/api_service.dart, en la clase VelneoAPIService]

  Future<List<dynamic>> obtenerTodasLineasPedido() async {
    try {
      _log('📄 Descargando TODAS las líneas de pedido...');

      // Llamamos al endpoint sin el filtro 'vta_ped'
      final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
        'page_size': '2000', // O un límite suficientemente alto
      });

      _log('🌐 URL líneas pedido: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 45));

      _log('📥 Status code líneas pedido: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['vta_ped_lin_g'] != null && data['vta_ped_lin_g'] is List) {
          final lineasList = (data['vta_ped_lin_g'] as List).map((linea) {
            // Asumiendo que las líneas también tienen 'por_dto' y 'por_iva'
            // (Si los nombres de los campos son diferentes, ajústalos aquí)
            return {
              'pedido_id': linea['vta_ped'] ?? 0,
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can_ped']),
              'precio': _convertirADouble(linea['pre']),
              'por_descuento': _convertirADouble(
                linea['por_dto'],
              ), // 🟢 CAMPO AÑADIDO
              'por_iva': _convertirADouble(
                linea['por_iva_apl'],
              ), // 🟢 CAMPO AÑADIDO (suposición)
            };
          }).toList();

          _log('✅ ${lineasList.length} líneas de pedido descargadas');
          return lineasList;
        } else {
          _log('⚠️ No se encontraron líneas de pedido');
          return [];
        }
      }

      throw Exception(
        'Error al obtener líneas de pedido: ${response.statusCode}',
      );
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPedido: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerTodasLineasPresupuesto() async {
    try {
      _log('📄 Descargando TODAS las líneas de presupuesto...');

      // Llamamos al endpoint sin el filtro 'vta_pre'
      final url = _buildUrlWithParams('/VTA_PRE_LIN_G', {
        'page_size': '2000', // O un límite suficientemente alto
      });

      _log('🌐 URL líneas presupuesto: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 45));

      _log('📥 Status code líneas presupuesto: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['vta_pre_lin_g'] != null && data['vta_pre_lin_g'] is List) {
          final lineasList = (data['vta_pre_lin_g'] as List).map((linea) {
            // 🛑 ¡IMPORTANTE! Usamos el ID que viene en la línea
            return {
              'presupuesto_id':
                  linea['vta_pre'] ?? 0, // <-- ASIGNACIÓN CORRECTA
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can']),
              'precio': _convertirADouble(linea['pre']),
            };
          }).toList();

          _log('✅ ${lineasList.length} líneas de presupuesto descargadas');
          return lineasList;
        } else {
          _log('⚠️ No se encontraron líneas de presupuesto');
          return [];
        }
      }

      throw Exception(
        'Error al obtener líneas de presupuesto: ${response.statusCode}',
      );
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPresupuesto: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerLeads() async {
    try {
      print('📄 Descargando leads...');

      final url = _buildUrlWithParams('/CRM_LEA', {
        'page': '1',
        'page_size': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['crm_lea'] != null && data['crm_lea'] is List) {
          final leadsList = (data['crm_lea'] as List).map((lead) {
            return {
              'id': lead['id'],
              'nombre': lead['name'] ?? '',
              'fecha_alta': lead['fch_alt'],
              'campana_id': lead['crm_cam_com'] ?? 0,
              'cliente_id': lead['cli'] ?? 0,
              'asunto': lead['asu'] ?? '',
              'descripcion': lead['dsc'] ?? '',
              'comercial_id': lead['com'] ?? 0,
              'estado': lead['crm_est_lea'] ?? '',
              'fecha': lead['fch'],
              'enviado': (lead['env'] == true) ? 1 : 0,
              'agendado': (lead['age'] == true) ? 1 : 0,
              'agenda_id': lead['crm_age'] ?? 0,
            };
          }).toList();

          print('✅ ${leadsList.length} leads descargados');
          return leadsList;
        }
      }

      throw Exception('Error al obtener leads: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerLeads: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerAgenda([int? comercialId]) async {
    try {
      final allAgendas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      DebugLogger.log(
        '📄 Descargando agenda${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page': page.toString(),
          'page_size': pageSize.toString(),
          'sort': '-id', // Ordenar por ID descendente
        };

        if (comercialId != null) {
          params['com'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/CRM_AGE', params);

        DebugLogger.log('  📥 Descargando página $page...');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              DebugLogger.log('  📊 Total registros: $totalCount');
            }

            if (data['crm_age'] != null && data['crm_age'] is List) {
              final agendasList = data['crm_age'] as List;

              if (agendasList.isEmpty) {
                DebugLogger.log('  🏁 No hay más registros en página $page');
                break;
              }

              final agendas = agendasList
                  .where((agenda) {
                    return agenda['fch_ini'] != null &&
                        agenda['fch_ini'].toString().isNotEmpty;
                  })
                  .map((agenda) {
                    // Función mejorada para limpiar fechas
                    String? limpiarFecha(dynamic fecha) {
                      if (fecha == null) return null;
                      final fechaStr = fecha.toString().trim();
                      if (fechaStr.isEmpty) return null;

                      try {
                        if (fechaStr.contains('T') && fechaStr.contains('Z')) {
                          DateTime.parse(fechaStr);
                          return fechaStr;
                        }
                        if (fechaStr.contains('GMT') ||
                            fechaStr.contains('UTC')) {
                          try {
                            final dt = DateTime.parse(fechaStr);
                            return dt.toIso8601String();
                          } catch (e) {
                            DebugLogger.log(
                              '⚠️ No se pudo parsear fecha GMT: $fechaStr',
                            );
                            return null;
                          }
                        }
                        final dt = DateTime.parse(fechaStr);
                        return dt.toIso8601String();
                      } catch (e) {
                        DebugLogger.log(
                          '⚠️ Fecha inválida ignorada: $fechaStr - Error: $e',
                        );
                        return null;
                      }
                    }

                    final fechaInicio = limpiarFecha(agenda['fch_ini']);

                    if (fechaInicio == null) {
                      DebugLogger.log(
                        '⚠️ Visita sin fecha válida: ID ${agenda['id']}',
                      );
                    }

                    return {
                      'id': agenda['id'],
                      'nombre': agenda['name']?.toString() ?? '',
                      'cliente_id': agenda['cli'] ?? 0,
                      'tipo_visita': agenda['tip_vis'] ?? 0,
                      'asunto': agenda['asu']?.toString() ?? '',
                      'comercial_id': agenda['com'] ?? 0,
                      'campana_id': agenda['crm_cam_com'] ?? 0,
                      'fecha_inicio':
                          fechaInicio ?? DateTime.now().toIso8601String(),
                      'hora_inicio': fechaInicio,
                      'fecha_fin': limpiarFecha(agenda['fch_fin']),
                      'hora_fin': limpiarFecha(agenda['fch_fin']),
                      'fecha_proxima_visita': limpiarFecha(
                        agenda['fch_pro_vis'],
                      ),
                      'hora_proxima_visita': null,
                      'descripcion': agenda['dsc']?.toString() ?? '',
                      'todo_dia': (agenda['tod_dia'] == true) ? 1 : 0,
                      'lead_id': agenda['crm_lea'] ?? 0,
                      'presupuesto_id': agenda['vta_pre_g'] ?? 0,
                      'generado': (agenda['gen'] == true) ? 1 : 0,
                      'sincronizado': 1,

                      // 🟢 Añadimos los campos que faltaban de versiones anteriores
                      'no_gen_pro_vis': agenda['no_gen_pro_vis'] ?? false,
                      'no_gen_tri': agenda['no_gen_tri'] ?? false,
                    };
                  })
                  .toList();

              allAgendas.addAll(agendas);
              DebugLogger.log(
                '  ✅ Página $page: ${agendas.length} registros válidos (Total acumulado: ${allAgendas.length}/$totalCount)',
              );

              if (agendasList.length < pageSize) {
                DebugLogger.log(
                  '  🏁 Última página detectada (${agendasList.length} < $pageSize)',
                );
                break;
              }

              if (totalCount > 0 && allAgendas.length >= totalCount) {
                DebugLogger.log(
                  '  🏁 Total alcanzado (${allAgendas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              DebugLogger.log('  ⚠️ No hay campo crm_age en respuesta');
              break;
            }
          } else {
            DebugLogger.log('  ❌ Error HTTP ${response.statusCode}');
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          DebugLogger.log('  ❌ Error en página $page: $e');
          if (allAgendas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      DebugLogger.log(
        '✅ TOTAL agenda descargada: ${allAgendas.length} eventos válidos',
      );
      return allAgendas;
    } catch (e) {
      DebugLogger.log('❌ Error en obtenerAgenda: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerProvincias() async {
    try {
      print('📄 Descargando provincias...');

      final url = _buildUrlWithParams('/PRO_M', {
        'page': '1',
        'page_size': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['pro_m'] != null && data['pro_m'] is List) {
          final provinciasList = (data['pro_m'] as List).map((provincia) {
            return {
              'id': provincia['id'],
              'nombre': provincia['name'] ?? 'Sin nombre',
              'prefijo_cp': provincia['pre_cps'] ?? '',
              'pais': provincia['pai'] ?? 0,
            };
          }).toList();

          print('✅ ${provinciasList.length} provincias descargadas');
          return provinciasList;
        }
      }

      throw Exception('Error al obtener provincias: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerProvincias: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerZonasTecnicas() async {
    try {
      print('📄 Descargando zonas técnicas...');

      final url = _buildUrlWithParams('/ZN_TCN', {
        'page': '1',
        'page_size': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['zn_tcn'] != null && data['zn_tcn'] is List) {
          final zonasList = (data['zn_tcn'] as List).map((zona) {
            return {
              'id': zona['id'],
              'nombre': zona['name'] ?? 'Sin nombre',
              'observaciones': zona['observaciones'] ?? '',
              'tecnico_id': zona['tec'] ?? 0,
            };
          }).toList();

          print('✅ ${zonasList.length} zonas técnicas descargadas');
          return zonasList;
        }
      }

      throw Exception(
        'Error al obtener zonas técnicas: ${response.statusCode}',
      );
    } catch (e) {
      print('❌ Error en obtenerZonasTecnicas: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerPoblaciones() async {
    try {
      print('📄 Descargando poblaciones...');

      final url = _buildUrlWithParams('/POB', {
        'page': '1',
        'page_size': '1000',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['pob'] != null && data['pob'] is List) {
          final poblacionesList = (data['pob'] as List).map((poblacion) {
            return {
              'id': poblacion['id'],
              'nombre': poblacion['name'] ?? 'Sin nombre',
              'km': poblacion['km'] ?? 0,
              'zona_tecnica_id': poblacion['zn_tcn'] ?? 0,
              'codigo_postal': poblacion['cp'] ?? '',
            };
          }).toList();

          print('✅ ${poblacionesList.length} poblaciones descargadas');
          return poblacionesList;
        }
      }

      throw Exception('Error al obtener poblaciones: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerPoblaciones: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerUsuarios() async {
    return [];
  }

  Future<List<dynamic>> obtenerPedidos() async {
    try {
      _log('📄 Descargando pedidos desde Velneo...');

      final url = _buildUrlWithParams('/VTA_PED_G', {
        'page': '1',
        'page_size': '100',
      });

      _log('🌐 URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status code: ${response.statusCode}');

      if (response.body.length > 500) {
        _log(
          '📥 Response (primeros 500 chars): ${response.body.substring(0, 500)}...',
        );
      } else {
        _log('📥 Response completo: ${response.body}');
      }
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['vta_ped_g'] != null && data['vta_ped_g'] is List) {
          final listaPedidos = data['vta_ped_g'] as List;

          final pedidosList = listaPedidos.map((pedido) {
            return {
              'id': pedido['id'],
              'cliente_id': pedido['clt'] ?? 0,
              'cmr': pedido['cmr'] ?? 0,
              'fecha': pedido['fch'] ?? DateTime.now().toIso8601String(),
              'numero': pedido['num_ped'] ?? '', // 🟢 CAMPO AÑADIDO
              'estado': pedido['est'] ?? '',
              'observaciones': pedido['obs'] ?? '',
              'total': _convertirADouble(
                pedido['tot_ped'],
              ), // 🟢 TOTAL YA INCLUIDO
              'sincronizado': 1,
            };
          }).toList();

          _log('✅ ${pedidosList.length} pedidos procesados correctamente');
          return pedidosList;
        } else {
          _log(
            '⚠️ No se encontró campo vta_ped_g en la respuesta o está vacío',
          );
          _log('⚠️ Estructura recibida: ${data.toString().substring(0, 200)}');
          return [];
        }
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      _log('❌ Error en obtenerPedidos: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> crearPedido(Map<String, dynamic> pedido) async {
    try {
      final pedidoVelneo = {
        'emp': '1',
        'emp_div': '1',
        'clt': pedido['cliente_id'],
      };

      if (pedido['cmr'] != null) {
        pedidoVelneo['cmr'] = pedido['cmr'];
        print('📝 Asignando comercial ID: ${pedido['cmr']} al pedido');
      }

      print('📄 Creando pedido en Velneo: $pedidoVelneo');

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 30);

      try {
        final request = await httpClient
            .postUrl(Uri.parse(_buildUrl('/VTA_PED_G')))
            .timeout(const Duration(seconds: 30));

        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.headers.set('User-Agent', 'Flutter App');
        request.write(json.encode(pedidoVelneo));

        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        final stringData = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));

        print('ðŸ“¥ Respuesta crear pedido - Status: ${response.statusCode}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final respuesta = json.decode(stringData);

          int? pedidoId;
          if (respuesta['vta_ped_g'] != null &&
              respuesta['vta_ped_g'] is List &&
              (respuesta['vta_ped_g'] as List).isNotEmpty) {
            pedidoId = respuesta['vta_ped_g'][0]['id'];
          } else if (respuesta['id'] != null) {
            pedidoId = respuesta['id'];
          }

          print('âœ… Pedido creado con ID: $pedidoId');

          if (pedidoId == null) {
            throw Exception('No se pudo obtener el ID del pedido creado');
          }

          int lineasOk = 0;
          int lineasError = 0;

          if (pedido['lineas'] != null) {
            for (var linea in pedido['lineas']) {
              try {
                await crearLineaPedido(pedidoId, linea);
                lineasOk++;
                print('  âœ“ LÃ­nea $lineasOk creada');
              } catch (e) {
                lineasError++;
                print('  âœ— Error lÃ­nea: $e');
                if (lineasOk == 0 && lineasError == pedido['lineas'].length) {
                  throw Exception('No se pudo crear ninguna línea del pedido');
                }
              }
            }
          }

          print(
            '✓ Pedido completado: $lineasOk líneas OK, $lineasError errores',
          );

          return {
            'id': pedidoId,
            'lineas_creadas': lineasOk,
            'lineas_error': lineasError,
          };
        }
        throw Exception('Error HTTP ${response.statusCode}: $stringData');
      } finally {
        httpClient.close();
      }
    } catch (e) {
      print(' Error en crearPedido: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> crearLineaPedido(
    int pedidoId,
    Map<String, dynamic> linea,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 20);

    try {
      final lineaVelneo = {
        'vta_ped': pedidoId,
        'emp': '1',
        'art': linea['articulo_id'],
        'can_ped': linea['cantidad'],
        'pre': linea['precio'],
      };

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/VTA_PED_LIN_G')))
          .timeout(const Duration(seconds: 20));

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(json.encode(lineaVelneo));

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(stringData);
      }
      throw Exception(
        'Error al crear lÃ­nea: ${response.statusCode} - $stringData',
      );
    } catch (e) {
      print('â Œ Error en crearLineaPedido: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> crearVisitaAgenda(
    Map<String, dynamic> visita,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      DebugLogger.log('📝 API: Creando visita "${visita['asunto']}"');

      final visitaVelneo = {
        'cli': visita['cliente_id'],
        'tip_vis': visita['tipo_visita'],
        'asu': visita['asunto'],
        'com': visita['comercial_id'],
        'fch_ini': visita['fecha_inicio'],
        'dsc': visita['descripcion'] ?? '',
        'tod_dia': visita['todo_dia'] == 1,
        'no_gen_tri': visita['no_gen_tri'] ?? false,
        'no_gen_pro_vis': visita['no_gen_pro_vis'] ?? false,
      };

      if (visita['hora_inicio'] != null &&
          visita['hora_inicio'].toString().isNotEmpty) {
        visitaVelneo['hor_ini'] = visita['hora_inicio'];
      }
      if (visita['fecha_fin'] != null &&
          visita['fecha_fin'].toString().isNotEmpty) {
        visitaVelneo['fch_fin'] = visita['fecha_fin'];
      }
      if (visita['hora_fin'] != null &&
          visita['hora_fin'].toString().isNotEmpty) {
        visitaVelneo['hor_fin'] = visita['hora_fin'];
      }
      if (visita['fecha_proxima_visita'] != null &&
          visita['fecha_proxima_visita'].toString().isNotEmpty) {
        visitaVelneo['fch_pro_vis'] = visita['fecha_proxima_visita'];
      }
      if (visita['hora_proxima_visita'] != null &&
          visita['hora_proxima_visita'].toString().isNotEmpty) {
        visitaVelneo['hor_pro_vis'] = visita['hora_proxima_visita'];
      }
      if (visita['campana_id'] != null && visita['campana_id'] != 0) {
        visitaVelneo['crm_cam_com'] = visita['campana_id'];
      }
      if (visita['lead_id'] != null && visita['lead_id'] != 0) {
        visitaVelneo['crm_lea'] = visita['lead_id'];
      }
      DebugLogger.log('📤 API: Payload fch_ini: ${visitaVelneo['fch_ini']}');
      DebugLogger.log('📤 API: Payload hor_ini: ${visitaVelneo['hor_ini']}');
      final jsonData = json.encode(visitaVelneo);
      DebugLogger.log('📤 API: JSON enviado (${jsonData.length} chars)');
      DebugLogger.log('📤 API: Fecha en JSON: ${visitaVelneo['fch_ini']}');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_AGE')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      DebugLogger.log('📥 API: Status ${response.statusCode}');

      if (stringData.length < 500) {
        DebugLogger.log('📥 API: Respuesta: $stringData');
      } else {
        DebugLogger.log('📥 API: Respuesta larga (${stringData.length} chars)');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);

        int? visitaId;
        if (respuesta['crm_age'] != null &&
            respuesta['crm_age'] is List &&
            (respuesta['crm_age'] as List).isNotEmpty) {
          visitaId = respuesta['crm_age'][0]['id'];
        } else if (respuesta['id'] != null) {
          visitaId = respuesta['id'];
        }

        if (visitaId == null) {
          DebugLogger.log('⚠️ API: No se encontró ID en respuesta');
          throw Exception('No se pudo obtener el ID de la visita');
        }

        DebugLogger.log('✅ API: Visita creada con ID $visitaId');
        return {'id': visitaId, 'success': true};
      }

      DebugLogger.log('❌ API: Error HTTP ${response.statusCode}');
      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      DebugLogger.log('❌ API: Excepción - $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> actualizarVisitaAgenda(
    String visitaId,
    Map<String, dynamic> visita,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      DebugLogger.log(
        '📝 API: Actualizando (con POST) visita #$visitaId "${visita['asunto']}"',
      );

      final visitaVelneo = {
        'cli': visita['cliente_id'],
        'tip_vis': visita['tipo_visita'],
        'asu': visita['asunto'],
        'com': visita['comercial_id'],
        'fch_ini': visita['fecha_inicio'],
        'dsc': visita['descripcion'] ?? '',
        'tod_dia': visita['todo_dia'] == 1,
        'no_gen_tri': visita['no_gen_tri'] ?? false, // 🟢 Corrección
      };

      if (visita['hora_inicio'] != null &&
          visita['hora_inicio'].toString().isNotEmpty) {
        visitaVelneo['hor_ini'] = visita['hora_inicio'];
      }
      if (visita['fecha_fin'] != null &&
          visita['fecha_fin'].toString().isNotEmpty) {
        visitaVelneo['fch_fin'] = visita['fecha_fin'];
      }
      if (visita['hora_fin'] != null &&
          visita['hora_fin'].toString().isNotEmpty) {
        visitaVelneo['hor_fin'] = visita['hora_fin'];
      }
      if (visita['fecha_proxima_visita'] != null &&
          visita['fecha_proxima_visita'].toString().isNotEmpty) {
        visitaVelneo['fch_pro_vis'] = visita['fecha_proxima_visita'];
      }
      if (visita['hora_proxima_visita'] != null &&
          visita['hora_proxima_visita'].toString().isNotEmpty) {
        visitaVelneo['hor_pro_vis'] = visita['hora_proxima_visita'];
      }
      visitaVelneo['no_gen_pro_vis'] = visita['no_gen_pro_vis'] ?? false;

      if (visita['campana_id'] != null && visita['campana_id'] != 0) {
        visitaVelneo['crm_cam_com'] = visita['campana_id'];
      }
      if (visita['lead_id'] != null && visita['lead_id'] != 0) {
        visitaVelneo['crm_lea'] = visita['lead_id'];
      }

      final jsonData = json.encode(visitaVelneo);
      DebugLogger.log('📤 API: Payload fch_ini: ${visitaVelneo['fch_ini']}');
      DebugLogger.log('📤 API: Payload hor_ini: ${visitaVelneo['hor_ini']}');
      DebugLogger.log('📤 API: JSON enviado (${jsonData.length} chars)');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_AGE/$visitaId')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      DebugLogger.log('📥 API: Status ${response.statusCode}');
      DebugLogger.log('📥 API: Respuesta: $stringData');

      if (response.statusCode == 200) {
        final respuesta = json.decode(stringData);

        int? idRespuesta;
        if (respuesta['crm_age'] != null &&
            respuesta['crm_age'] is List &&
            (respuesta['crm_age'] as List).isNotEmpty) {
          idRespuesta = respuesta['crm_age'][0]['id'];
        } else if (respuesta['id'] != null) {
          idRespuesta = respuesta['id'];
        }

        DebugLogger.log('✅ API: Visita actualizada con ID $idRespuesta');
        return {'id': idRespuesta ?? visitaId, 'success': true};
      }

      DebugLogger.log('❌ API: Error HTTP ${response.statusCode}');
      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      DebugLogger.log('❌ API: Excepción - $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<bool> deleteVisitaAgenda(String visitaId) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      DebugLogger.log('🗑️ API: Eliminando visita #$visitaId');

      final request = await httpClient
          .deleteUrl(Uri.parse(_buildUrl('/CRM_AGE/$visitaId')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      DebugLogger.log('📥 API: Status ${response.statusCode}');
      DebugLogger.log('📥 API: Respuesta: $stringData');

      if (response.statusCode == 200 || response.statusCode == 204) {
        DebugLogger.log('✅ API: Visita #$visitaId eliminada');
        return true;
      }

      DebugLogger.log('❌ API: Error HTTP ${response.statusCode}');
      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      DebugLogger.log('❌ API: Excepción - $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }
  // Añadir estos métodos a la clase VelneoAPIService en api_service.dart

  Future<Map<String, dynamic>> crearLead(Map<String, dynamic> lead) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      print('📝 Creando lead en Velneo...');

      final leadVelneo = {
        'asu': lead['asunto'],
        'dsc': lead['descripcion'] ?? '',
        'com': lead['comercial_id'],
        'crm_est_lea': lead['estado'],
      };

      // Campos opcionales
      if (lead['cliente_id'] != null && lead['cliente_id'] != 0) {
        leadVelneo['cli'] = lead['cliente_id'];
      }
      if (lead['campana_id'] != null && lead['campana_id'] != 0) {
        leadVelneo['crm_cam_com'] = lead['campana_id'];
      }

      final jsonData = json.encode(leadVelneo);
      print('📤 JSON enviado: $jsonData');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_LEA')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      print('📥 Respuesta - Status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);

        int? leadId;
        if (respuesta['crm_lea'] != null &&
            respuesta['crm_lea'] is List &&
            (respuesta['crm_lea'] as List).isNotEmpty) {
          leadId = respuesta['crm_lea'][0]['id'];
        } else if (respuesta['id'] != null) {
          leadId = respuesta['id'];
        }

        if (leadId == null) {
          throw Exception('No se pudo obtener el ID del lead');
        }

        print('✅ Lead creado con ID $leadId');
        return {'id': leadId, 'success': true};
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      print('❌ Error al crear lead: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> actualizarLead(
    String leadId,
    Map<String, dynamic> lead,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      print('📝 Actualizando lead #$leadId en Velneo...');

      final leadVelneo = {
        'asu': lead['asunto'],
        'dsc': lead['descripcion'] ?? '',
        'com': lead['comercial_id'],
        'crm_est_lea': lead['estado'],
      };

      // Campos opcionales
      if (lead['cliente_id'] != null && lead['cliente_id'] != 0) {
        leadVelneo['cli'] = lead['cliente_id'];
      }
      if (lead['campana_id'] != null && lead['campana_id'] != 0) {
        leadVelneo['crm_cam_com'] = lead['campana_id'];
      }

      final jsonData = json.encode(leadVelneo);
      print('📤 JSON enviado: $jsonData');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_LEA/$leadId')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      print('📥 Respuesta - Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ Lead actualizado correctamente');
        return {'id': int.parse(leadId), 'success': true};
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      print('❌ Error al actualizar lead: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<bool> probarConexion() async {
    try {
      final url = _buildUrl('/ART_M');
      print('Probando conexión con: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      print('Respuesta de prueba - Status: ${response.statusCode}');

      if (response.statusCode == 400) {
        print('Error 400 - Respuesta: ${response.body}');
      }

      return response.statusCode == 200;
    } catch (e) {
      print('Error en probarConexion: $e');
      return false;
    }
  }

  Future<List<dynamic>> obtenerPresupuestos() async {
    try {
      _log('📄 Descargando presupuestos desde Velneo...');

      final url = _buildUrlWithParams('/VTA_PRE_G', {
        'page': '1',
        'page_size': '100',
      });

      _log('🌐 URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status code: ${response.statusCode}');

      if (response.body.length > 500) {
        _log(
          '📥 Response (primeros 500 chars): ${response.body.substring(0, 500)}...',
        );
      } else {
        _log('📥 Response completo: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _log('🔍 Keys en respuesta: ${data.keys.join(", ")}');

        if (data['vta_pre_g'] != null && data['vta_pre_g'] is List) {
          final listaPresupuestos = data['vta_pre_g'] as List;
          _log(
            '📋 Encontrados ${listaPresupuestos.length} presupuestos en vta_pre_g',
          );

          final presupuestosList = listaPresupuestos.map((presupuesto) {
            _log(
              '  → Presupuesto ID: ${presupuesto['id']} - Cliente: ${presupuesto['clt']} - Comercial: ${presupuesto['cmr']}',
            );
            return {
              'id': presupuesto['id'],
              'cliente_id': presupuesto['clt'] ?? 0,
              'comercial_id': presupuesto['cmr'] ?? 0,
              'fecha': presupuesto['fch'],
              'numero': presupuesto['num_pre'] ?? '',
              'observaciones': presupuesto['obs'] ?? '',
              'estado': presupuesto['est'] ?? '',
              'total': _convertirADouble(presupuesto['tot_pre']),
              'base_total': _convertirADouble(presupuesto['bas_tot']),
              'iva_total': _convertirADouble(presupuesto['iva_tot']),
              'fecha_validez': presupuesto['fch_val'],
              'fecha_aceptacion': presupuesto['fch_ace'],
            };
          }).toList();

          _log(
            '✅ ${presupuestosList.length} presupuestos procesados correctamente',
          );
          return presupuestosList;
        } else {
          _log(
            '⚠️ No se encontró campo vta_pre_g en la respuesta o está vacío',
          );
          _log('⚠️ Estructura recibida: ${data.toString().substring(0, 200)}');
          return [];
        }
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      _log('❌ Error en obtenerPresupuestos: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> crearPresupuesto(
    Map<String, dynamic> presupuesto,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      print('📝 Creando presupuesto en Velneo...');

      // Preparar datos básicos del presupuesto
      final presupuestoVelneo = {
        'emp': '1',
        'emp_div': '1',
        'clt': presupuesto['cliente_id'],
        'obs': presupuesto['observaciones'] ?? '',
      };

      // Agregar comercial si existe
      if (presupuesto['comercial_id'] != null &&
          presupuesto['comercial_id'] != 0) {
        presupuestoVelneo['cmr'] = presupuesto['comercial_id'];
      }

      final jsonData = json.encode(presupuestoVelneo);
      print('📤 JSON enviado: $jsonData');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/VTA_PRE_G')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      print('📥 Respuesta - Status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);

        int? presupuestoId;
        if (respuesta['vta_pre_g'] != null &&
            respuesta['vta_pre_g'] is List &&
            (respuesta['vta_pre_g'] as List).isNotEmpty) {
          presupuestoId = respuesta['vta_pre_g'][0]['id'];
        } else if (respuesta['id'] != null) {
          presupuestoId = respuesta['id'];
        }

        if (presupuestoId == null) {
          throw Exception('No se pudo obtener el ID del presupuesto');
        }

        print('✅ Presupuesto creado con ID $presupuestoId');

        // Ahora crear las líneas del presupuesto
        int lineasCreadas = 0;
        if (presupuesto['lineas'] != null) {
          for (var linea in presupuesto['lineas']) {
            try {
              final lineaData = {
                'vta_pre': presupuestoId,
                'art': linea['articulo_id'],
                'can': linea['cantidad'],
                'pre': linea['precio'],
              };

              final lineaRequest = await httpClient
                  .postUrl(Uri.parse(_buildUrl('/VTA_PRE_LIN_G')))
                  .timeout(const Duration(seconds: 30));

              lineaRequest.headers.set(
                'Content-Type',
                'application/json; charset=utf-8',
              );
              lineaRequest.headers.set('Accept', 'application/json');
              lineaRequest.write(json.encode(lineaData));

              final lineaResponse = await lineaRequest.close();
              if (lineaResponse.statusCode == 200 ||
                  lineaResponse.statusCode == 201) {
                lineasCreadas++;
              }
            } catch (e) {
              print('⚠️ Error al crear línea: $e');
            }
          }
        }

        return {
          'id': presupuestoId,
          'lineas_creadas': lineasCreadas,
          'success': true,
        };
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      print('❌ Error al crear presupuesto: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  void dispose() {
    _client.close();
  }
}
