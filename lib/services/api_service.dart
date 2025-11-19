import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../screens/debug_logs_screen.dart';

class VelneoAPIService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client = http.Client();
  final Function(String)? onLog;

  VelneoAPIService(this.baseUrl, this.apiKey, {this.onLog});

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

  String _buildUrlWithParams(String endpoint, Map<String, String>? params) {
    final uri = Uri.parse('$baseUrl$endpoint');
    final queryParams = {'api_key': apiKey};
    if (params != null) {
      queryParams.addAll(params);
    }
    return uri.replace(queryParameters: queryParams).toString();
  }

  double _convertirADouble(dynamic valor) {
    if (valor == null) return 0.0;
    if (valor is double) return valor;
    if (valor is int) return valor.toDouble();
    if (valor is String) return double.tryParse(valor) ?? 0.0;
    return 0.0;
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
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        print('  🛑 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              print('  📊 Total registros en servidor: $totalCount');
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

              if (articulos.length < pageSize) {
                print('  🛑 Última página (${articulos.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allArticulos.length >= totalCount) {
                print(
                  '  🏁 Total alcanzado (${allArticulos.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              print('  🛑 No hay campo art_m en respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('❌ Error en página $page: $e');
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
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        print('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              print('  📊 Total registros en servidor: $totalCount');
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

  Future<List<dynamic>> obtenerPedidos([int? comercialId]) async {
    try {
      final allPedidos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log(
        '📄 Descargando pedidos${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };

        // Agregar filtro de comercial si se proporciona
        if (comercialId != null) {
          params['filter[cmr]'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/VTA_PED_G', params);
        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_ped_g'] != null && data['vta_ped_g'] is List) {
              final listaPedidos = data['vta_ped_g'] as List;

              if (listaPedidos.isEmpty) {
                _log('  🏁 No hay más pedidos, finalizando');
                break;
              }

              final pedidosList = listaPedidos.map((pedido) {
                return {
                  'id': pedido['id'],
                  'cliente_id': pedido['clt'] ?? 0,
                  'cmr': pedido['cmr'] ?? 0,
                  'fecha': pedido['fch'] ?? DateTime.now().toIso8601String(),
                  'numero': pedido['num_ped'] ?? '',
                  'estado': pedido['est'] ?? '',
                  'observaciones': pedido['obs'] ?? '',
                  'total': _convertirADouble(pedido['tot_ped']),
                  'sincronizado': 1,
                };
              }).toList();

              allPedidos.addAll(pedidosList);
              _log(
                '  ✅ Página $page: ${pedidosList.length} pedidos (Acumulado: ${allPedidos.length}/$totalCount)',
              );

              if (listaPedidos.length < pageSize) {
                _log('  🏁 Última página (${listaPedidos.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allPedidos.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allPedidos.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontró campo vta_ped_g en la respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allPedidos.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL pedidos descargados: ${allPedidos.length}');
      return allPedidos;
    } catch (e) {
      _log('❌ Error en obtenerPedidos: $e');
      rethrow;
    }
  }

  // Actualizar pedido existente
  Future<Map<String, dynamic>> actualizarPedido(
    int pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    try {
      final pedidoVelneo = {
        'emp': '1',
        'emp_div': '1',
        'clt': pedido['cliente_id'],
      };

      if (pedido['cmr'] != null) pedidoVelneo['cmr'] = pedido['cmr'];
      if (pedido['observaciones'] != null)
        pedidoVelneo['obs'] = pedido['observaciones'];

      print('📝 Actualizando pedido #$pedidoId en Velneo');

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 45);

      try {
        // 1. Obtener líneas actuales
        final lineasActuales = await obtenerLineasPedido(pedidoId);

        // 2. Eliminar líneas antiguas
        print('🗑️ Eliminando ${lineasActuales.length} líneas antiguas...');
        for (var linea in lineasActuales) {
          if (linea['id'] != null) {
            final request = await httpClient.deleteUrl(
              Uri.parse(_buildUrl('/VTA_PED_LIN_G/${linea['id']}')),
            );
            request.headers.set('Accept', 'application/json');
            final response = await request.close();
            await response.drain();
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));

        // 3. Actualizar Cabecera
        final request = await httpClient.postUrl(
          Uri.parse(_buildUrl('/VTA_PED_G/$pedidoId')),
        );
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.write(json.encode(pedidoVelneo));

        final response = await request.close();
        final stringData = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200 || response.statusCode == 201) {
          print('   ✅ Cabecera actualizada');

          // 4. Crear nuevas líneas
          int lineasOk = 0;
          if (pedido['lineas'] != null) {
            for (var linea in pedido['lineas']) {
              try {
                final nuevaLinea = {
                  'articulo_id': linea['articulo_id'],
                  'cantidad': (linea['cantidad'] as num).toDouble(),
                  'precio': (linea['precio'] as num).toDouble(),
                  'tipo_iva': linea['tipo_iva'] ?? 'G', // Pasamos el dato
                };
                // crearLineaPedido se encargará de ponerlo en 'reg_iva_vta'
                await crearLineaPedido(pedidoId, nuevaLinea);
                lineasOk++;
              } catch (e) {
                print('   ⚠️ Error creando línea: $e');
              }
            }
          }
          return {'id': pedidoId, 'lineas_creadas': lineasOk, 'success': true};
        }
        throw Exception('Error HTTP ${response.statusCode}: $stringData');
      } finally {
        httpClient.close();
      }
    } catch (e) {
      print('❌ Error en actualizarPedido: $e');
      rethrow;
    }
  }

  // Actualizar presupuesto existente
  Future<Map<String, dynamic>> actualizarPresupuesto(
    int presupuestoId,
    Map<String, dynamic> presupuesto,
  ) async {
    try {
      final presupuestoVelneo = {
        'emp': '1',
        'emp_div': '1',
        'clt': presupuesto['cliente_id'],
      };

      if (presupuesto['comercial_id'] != null) {
        presupuestoVelneo['cmr'] = presupuesto['comercial_id'];
      }
      if (presupuesto['observaciones'] != null) {
        presupuestoVelneo['obs'] = presupuesto['observaciones'];
      }
      if (presupuesto['estado'] != null) {
        presupuestoVelneo['est'] = presupuesto['estado'];
      }

      print('📝 Actualizando presupuesto #$presupuestoId en Velneo');

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 45);

      try {
        // 1. Obtener líneas actuales
        final lineasActuales = await obtenerLineasPresupuesto(presupuestoId);

        // 2. Eliminar líneas antiguas
        print('🗑️ Eliminando ${lineasActuales.length} líneas antiguas');
        for (var linea in lineasActuales) {
          if (linea['id'] != null) {
            final request = await httpClient.deleteUrl(
              Uri.parse(_buildUrl('/VTA_PRE_LIN_G/${linea['id']}')),
            );
            request.headers.set('Accept', 'application/json');
            final response = await request.close();
            await response.drain();
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));

        // 3. Actualizar Cabecera
        final request = await httpClient
            .postUrl(Uri.parse(_buildUrl('/VTA_PRE_G/$presupuestoId')))
            .timeout(const Duration(seconds: 30));

        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.write(json.encode(presupuestoVelneo));

        final response = await request.close();
        final stringData = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200 || response.statusCode == 201) {
          // 4. Crear nuevas líneas
          int lineasOk = 0;
          if (presupuesto['lineas'] != null) {
            for (var linea in presupuesto['lineas']) {
              try {
                // 🟢 CORRECCIÓN: Añadido campo IVA para presupuestos
                final lineaData = {
                  'vta_pre': presupuestoId,
                  'art': linea['articulo_id'],
                  'can': (linea['cantidad'] as num).toDouble(),
                  'pre': (linea['precio'] as num).toDouble(),
                  'reg_iva_vta': linea['tipo_iva'] ?? 'G', // CAMPO CRUCIAL
                };

                final lineaRequest = await httpClient
                    .postUrl(Uri.parse(_buildUrl('/VTA_PRE_LIN_G')))
                    .timeout(const Duration(seconds: 30));

                lineaRequest.headers.set('Content-Type', 'application/json');
                lineaRequest.headers.set('Accept', 'application/json');
                lineaRequest.write(json.encode(lineaData));

                final lineaResponse = await lineaRequest.close();
                await lineaResponse.drain();

                if (lineaResponse.statusCode == 200 ||
                    lineaResponse.statusCode == 201) {
                  lineasOk++;
                }
              } catch (e) {
                print('⚠️ Error línea presupuesto: $e');
              }
            }
          }
          return {
            'id': presupuestoId,
            'lineas_creadas': lineasOk,
            'success': true,
          };
        }
        throw Exception('Error HTTP ${response.statusCode}: $stringData');
      } finally {
        httpClient.close();
      }
    } catch (e) {
      print('❌ Error en actualizarPresupuesto: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerSeries() async {
    try {
      final allSeries = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando series...');

      while (true) {
        final url = _buildUrlWithParams('/SER_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['ser_m'] != null && data['ser_m'] is List) {
              final seriesList = (data['ser_m'] as List).map((serie) {
                return {
                  'id': serie['id'],
                  'nombre': serie['name'] ?? 'Sin nombre',
                  'tipo':
                      serie['ser_tip'] ??
                      '', // 'V' para ventas, 'C' para compras
                };
              }).toList();

              if (seriesList.isEmpty) {
                _log('  🏁 No hay más series');
                break;
              }

              allSeries.addAll(seriesList);
              _log('  ✅ Página $page: ${seriesList.length} series');

              if (seriesList.length < pageSize) break;

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron series');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allSeries.isEmpty) rethrow;
          break;
        }
      }

      _log('✅ TOTAL series descargadas: ${allSeries.length}');
      return allSeries;
    } catch (e) {
      _log('❌ Error en obtenerSeries: $e');
      return [];
    }
  }

  // Eliminar líneas de pedido (DELETE) - SIN CAMBIOS
  Future<void> eliminarLineasPedido(int pedidoId) async {
    try {
      print('🗑️ Obteniendo líneas del pedido #$pedidoId para eliminar');

      final lineas = await obtenerLineasPedido(pedidoId);
      print('📋 Encontradas ${lineas.length} líneas a eliminar');

      if (lineas.isEmpty) {
        print('✓ No hay líneas que eliminar');
        return;
      }

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      try {
        int eliminadas = 0;
        for (var linea in lineas) {
          try {
            final lineaId = linea['id'];
            if (lineaId == null) continue;

            final request = await httpClient.deleteUrl(
              Uri.parse(_buildUrl('/VTA_PED_LIN_G/$lineaId')),
            );
            request.headers.set('Accept', 'application/json');
            final response = await request.close();

            if (response.statusCode == 200 || response.statusCode == 204) {
              eliminadas++;
              print(
                '  ✓ Línea $lineaId eliminada ($eliminadas/${lineas.length})',
              );
            } else {
              print(
                '  ⚠️ Error eliminando línea $lineaId: ${response.statusCode}',
              );
            }

            // 🔥 PEQUEÑO DELAY ENTRE ELIMINACIONES
            await Future.delayed(const Duration(milliseconds: 50));
          } catch (e) {
            print('  ⚠️ Error eliminando línea: $e');
          }
        }
        print('✅ Total líneas eliminadas: $eliminadas/${lineas.length}');
      } finally {
        httpClient.close();
      }
    } catch (e) {
      print('⚠️ Error eliminando líneas: $e');
    }
  }

  // Eliminar líneas de presupuesto (DELETE) - SIN CAMBIOS
  Future<void> eliminarLineasPresupuesto(int presupuestoId) async {
    try {
      print(
        '🗑️ Obteniendo líneas del presupuesto #$presupuestoId para eliminar',
      );

      final lineas = await obtenerLineasPresupuesto(presupuestoId);
      print('📋 Encontradas ${lineas.length} líneas a eliminar');

      if (lineas.isEmpty) {
        print('✓ No hay líneas que eliminar');
        return;
      }

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      try {
        int eliminadas = 0;
        for (var linea in lineas) {
          try {
            final lineaId = linea['id'];
            if (lineaId == null) continue;

            final request = await httpClient.deleteUrl(
              Uri.parse(_buildUrl('/VTA_PRE_LIN_G/$lineaId')),
            );
            request.headers.set('Accept', 'application/json');
            final response = await request.close();

            if (response.statusCode == 200 || response.statusCode == 204) {
              eliminadas++;
              print(
                '  ✓ Línea $lineaId eliminada ($eliminadas/${lineas.length})',
              );
            } else {
              print(
                '  ⚠️ Error eliminando línea $lineaId: ${response.statusCode}',
              );
            }

            // 🔥 PEQUEÑO DELAY ENTRE ELIMINACIONES
            await Future.delayed(const Duration(milliseconds: 50));
          } catch (e) {
            print('  ⚠️ Error eliminando línea: $e');
          }
        }
        print('✅ Total líneas eliminadas: $eliminadas/${lineas.length}');
      } finally {
        httpClient.close();
      }
    } catch (e) {
      print('⚠️ Error eliminando líneas: $e');
    }
  }

  Future<List<dynamic>> obtenerPresupuestos([int? comercialId]) async {
    try {
      final allPresupuestos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log(
        '📄 Descargando presupuestos${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };

        // Agregar filtro de comercial si se proporciona
        if (comercialId != null) {
          params['filter[cmr]'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/VTA_PRE_G', params);
        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_pre_g'] != null && data['vta_pre_g'] is List) {
              final listaPresupuestos = data['vta_pre_g'] as List;

              if (listaPresupuestos.isEmpty) {
                _log('  🏁 No hay más presupuestos, finalizando');
                break;
              }

              final presupuestosList = listaPresupuestos.map((presupuesto) {
                return {
                  'id': presupuesto['id'],
                  'cliente_id': presupuesto['clt'] ?? 0,
                  'comercial_id':
                      presupuesto['cmr'] ??
                      0, // 👈 CAMBIAR 'comercial_id' por 'cmr'
                  'fecha':
                      presupuesto['fch'] ?? DateTime.now().toIso8601String(),
                  'numero': presupuesto['num_pre'] ?? '',
                  'estado': presupuesto['est'] ?? '',
                  'observaciones': presupuesto['obs'] ?? '',
                  'total': _convertirADouble(presupuesto['tot']),
                  'sincronizado': 1,
                };
              }).toList();

              allPresupuestos.addAll(presupuestosList);
              _log(
                '  ✅ Página $page: ${presupuestosList.length} presupuestos (Acumulado: ${allPresupuestos.length}/$totalCount)',
              );

              if (listaPresupuestos.length < pageSize) {
                _log(
                  '  🏁 Última página (${listaPresupuestos.length} < $pageSize)',
                );
                break;
              }

              if (totalCount > 0 && allPresupuestos.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allPresupuestos.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontró campo vta_pre_g en la respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allPresupuestos.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL presupuestos descargados: ${allPresupuestos.length}');
      return allPresupuestos;
    } catch (e) {
      _log('❌ Error en obtenerPresupuestos: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerTodasLineasPedido() async {
    try {
      final allLineas = <dynamic>[];
      int page = 1;
      const int pageSize = 2000;
      int totalCount = 0;

      _log('📄 Descargando TODAS las líneas de pedido...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_ped_lin_g'] != null &&
                data['vta_ped_lin_g'] is List) {
              final lineasList = (data['vta_ped_lin_g'] as List).map((linea) {
                return {
                  'pedido_id': linea['vta_ped'] ?? 0,
                  'articulo_id': linea['art'] ?? 0,
                  'cantidad': _convertirADouble(linea['can_ped']),
                  'precio': _convertirADouble(linea['pre']),
                  'por_descuento': _convertirADouble(linea['por_dto']),
                  'por_iva': _convertirADouble(linea['iva_pje']),
                  'tipo_iva': linea['reg_iva_vta'] ?? 'G',
                };
              }).toList();
              if (lineasList.isEmpty) {
                _log('  🏁 No hay más líneas de pedido');
                break;
              }

              allLineas.addAll(lineasList);
              _log(
                '  ✅ Página $page: ${lineasList.length} líneas (Acumulado: ${allLineas.length}/$totalCount)',
              );

              if (lineasList.length < pageSize) {
                _log('  🏁 Última página (${lineasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allLineas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allLineas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron líneas de pedido');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allLineas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL líneas de pedido descargadas: ${allLineas.length}');
      return allLineas;
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPedido: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerTodasLineasPresupuesto() async {
    try {
      final allLineas = <dynamic>[];
      int page = 1;
      const int pageSize = 2000;
      int totalCount = 0;

      _log('📄 Descargando TODAS las líneas de presupuesto...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_PRE_LIN_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_pre_lin_g'] != null &&
                data['vta_pre_lin_g'] is List) {
              final lineasList = (data['vta_pre_lin_g'] as List).map((linea) {
                return {
                  'presupuesto_id': linea['vta_pre'] ?? 0,
                  'articulo_id': linea['art'] ?? 0,
                  'cantidad': _convertirADouble(linea['can']),
                  'precio': _convertirADouble(linea['pre']),
                  'por_descuento': _convertirADouble(linea['por_dto']),
                  'por_iva': _convertirADouble(linea['iva_pje']),
                  'tipo_iva': linea['reg_iva_vta'] ?? 'G',
                };
              }).toList();

              if (lineasList.isEmpty) {
                _log('  🏁 No hay más líneas de presupuesto');
                break;
              }

              allLineas.addAll(lineasList);
              _log(
                '  ✅ Página $page: ${lineasList.length} líneas (Acumulado: ${allLineas.length}/$totalCount)',
              );

              if (lineasList.length < pageSize) {
                _log('  🏁 Última página (${lineasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allLineas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allLineas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron líneas de presupuesto');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allLineas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL líneas de presupuesto descargadas: ${allLineas.length}');
      return allLineas;
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPresupuesto: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerLeads([int? comercialId]) async {
    try {
      final allLeads = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      print(
        '📄 Descargando leads${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };

        // Agregar filtro de comercial si se proporciona
        if (comercialId != null) {
          params['filter[cmr]'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/CRM_LEA', params);

        print('  📥 Página $page');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              print('  📊 Total registros en servidor: $totalCount');
            }

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

              if (leadsList.isEmpty) {
                print('  🏁 No hay más leads');
                break;
              }

              allLeads.addAll(leadsList);
              print(
                '  ✅ Página $page: ${leadsList.length} leads (Acumulado: ${allLeads.length}/$totalCount)',
              );

              if (leadsList.length < pageSize) {
                print('  🏁 Última página (${leadsList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allLeads.length >= totalCount) {
                print(
                  '  🏁 Total alcanzado (${allLeads.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              print('  ⚠️ No hay campo crm_lea en respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('  ❌ Error en página $page: $e');
          if (allLeads.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      print('✅ TOTAL leads descargados: ${allLeads.length}');
      return allLeads;
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
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-id',
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
              if (page == 1 && agendasList.isNotEmpty) {
                print('========================================');
                print('🔍 DEBUG API - Primer registro RAW:');
                final primer = agendasList[0];
                print('ID: ${primer['id']}');
                print('asu: ${primer['asu']}');
                print('fch_ini: ${primer['fch_ini']}');
                print('hor_ini RAW: "${primer['hor_ini']}"');
                print('hor_ini TIPO: ${primer['hor_ini'].runtimeType}');
                print('hor_fin RAW: "${primer['hor_fin']}"');
                print('========================================');
              }
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
                    String? limpiarFecha(dynamic fecha) {
                      if (fecha == null) return null;
                      String fechaStr = fecha.toString();
                      if (fechaStr.isEmpty) return null;

                      fechaStr = fechaStr
                          .replaceAll(RegExp(r'[^\d\-T:.\s]'), '')
                          .trim();

                      if (fechaStr.length >= 19) {
                        fechaStr = fechaStr.substring(0, 19);
                      }

                      if (RegExp(
                        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
                      ).hasMatch(fechaStr)) {
                        return fechaStr;
                      }

                      return null;
                    }

                    String? limpiarHora(dynamic hora) {
                      if (hora == null) return null;

                      String horaStr = hora.toString().trim();
                      if (horaStr.isEmpty) return null;

                      print('🕐 limpiarHora RAW: "$horaStr"');

                      // Si viene en formato GMT: "Mon Nov 17 09:00:00 2025 GMT"
                      if (horaStr.contains('GMT')) {
                        try {
                          // Extraer la hora usando regex
                          final regex = RegExp(r'\d{2}:\d{2}:\d{2}');
                          final match = regex.firstMatch(horaStr);

                          if (match != null) {
                            final horaExtraida = match.group(0)!;
                            print('✅ Hora extraída de GMT: "$horaExtraida"');
                            return horaExtraida;
                          }
                        } catch (e) {
                          print('❌ Error parseando hora GMT: $horaStr - $e');
                        }
                      }

                      // Si ya viene en formato "HH:MM:SS" directo
                      if (horaStr.contains(':')) {
                        final resultado = horaStr.split('.').first;
                        print('✅ Hora formato directo: "$resultado"');
                        return resultado;
                      }

                      print('⚠️ No se pudo extraer hora de: "$horaStr"');
                      return null;
                    }

                    DebugLogger.log(
                      '🕐 Hora RAW: ${agenda['hor_ini']} → Limpia: ${limpiarHora(agenda['hor_ini'])}',
                    );

                    return {
                      'id': agenda['id'],
                      'nombre': agenda['name'] ?? '',
                      'cliente_id': agenda['cli'] ?? 0,
                      'tipo_visita': agenda['tip_vis'] ?? 0,
                      'asunto': agenda['asu'] ?? '',
                      'comercial_id': agenda['com'] ?? 0,
                      'campana_id': agenda['crm_cam_com'] ?? 0,
                      'fecha_inicio': limpiarFecha(agenda['fch_ini']) ?? '',
                      'hora_inicio': limpiarHora(agenda['hor_ini']) ?? '',
                      'fecha_fin': limpiarFecha(agenda['fch_fin']) ?? '',
                      'hora_fin': limpiarHora(agenda['hor_fin']) ?? '',
                      'fecha_proxima_visita':
                          limpiarFecha(agenda['fch_pro_vis']) ?? '',
                      'hora_proxima_visita':
                          limpiarHora(agenda['hor_pro_vis']) ?? '',
                      'descripcion': agenda['dsc'] ?? '',
                      'todo_dia': (agenda['tod_dia'] == true) ? 1 : 0,
                      'lead_id': agenda['crm_lea'] ?? 0,
                      'presupuesto_id': agenda['vta_pre_g'] ?? 0,
                      'generado': (agenda['gen'] == true) ? 1 : 0,
                      'sincronizado': 1,
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

  Future<List<dynamic>> obtenerCampanas() async {
    try {
      print('📄 Descargando campañas comerciales...');

      final url = _buildUrlWithParams('/CRM_CAM_COM', {
        'page[number]': '1',
        'page[size]': '100',
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
        'page[number]': '1',
        'page[size]': '50',
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

  Future<List<dynamic>> obtenerProvincias() async {
    try {
      print('📄 Descargando provincias...');

      final url = _buildUrlWithParams('/PRO_M', {
        'page[number]': '1',
        'page[size]': '100',
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
        'page[number]': '1',
        'page[size]': '100',
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
        'page[number]': '1',
        'page[size]': '1000',
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

  Future<List<dynamic>> obtenerLineasPedido(int pedidoId) async {
    try {
      _log('📄 Descargando líneas del pedido $pedidoId...');

      final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
        'vta_ped': pedidoId.toString(),
        'page[size]': '100',
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
            _log('  → Línea ID: ${linea['id']} - Art ${linea['art']}');
            return {
              'id': linea['id'], // <--- ¡IMPORTANTE! Necesario para borrar
              'pedido_id': linea['vta_ped'] ?? pedidoId,
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can_ped']),
              'precio': _convertirADouble(linea['pre']),
              'por_descuento': _convertirADouble(linea['por_dto']),
              'por_iva': _convertirADouble(linea['iva_pje']),
              'tipo_iva': linea['reg_iva_vta'] ?? 'G',
            };
          }).toList();

          return lineasList;
        } else {
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
        'page[size]': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['vta_pre_lin_g'] != null && data['vta_pre_lin_g'] is List) {
          final lineasList = (data['vta_pre_lin_g'] as List).map((linea) {
            return {
              'id': linea['id'], // <--- ¡IMPORTANTE! Necesario para borrar
              'presupuesto_id': linea['vta_pre'] ?? presupuestoId,
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can']),
              'precio': _convertirADouble(linea['pre']),
              'por_descuento': _convertirADouble(linea['por_dto']),
              'por_iva': _convertirADouble(linea['iva_pje']),
              'tipo_iva': linea['reg_iva_vta'] ?? 'G',
            };
          }).toList();

          return lineasList;
        } else {
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

      // 🟢 NUEVO: Asignar Serie
      if (pedido['serie_id'] != null) {
        pedidoVelneo['ser'] = pedido['serie_id'];
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

        print('📥 Respuesta crear pedido - Status: ${response.statusCode}');

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

          print('✅ Pedido creado con ID: $pedidoId');

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
                print('  ✓ Línea $lineasOk creada');
              } catch (e) {
                lineasError++;
                print('  ✗ Error línea: $e');
                if (lineasOk == 0 && lineasError == pedido['lineas'].length) {
                  throw Exception('No se pudo crear ninguna línea del pedido');
                }
              }
            }
          }

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
      print('❌ Error en crearPedido: $e');
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
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      // Robustez para nombres de campos
      final artId = linea['articulo_id'] ?? linea['art'];
      final cantidad = linea['cantidad'] ?? linea['can_ped'];
      final precio = linea['precio'] ?? linea['pre_ven'] ?? linea['pre'];

      // Buscamos el IVA en cualquiera de sus posibles nombres
      final tipoIva = linea['tipo_iva'] ?? linea['reg_iva_vta'] ?? 'G';

      final lineaVelneo = {
        'vta_ped': pedidoId,
        'emp': '1',
        'art': artId,
        'can_ped': _convertirADouble(cantidad),
        'pre': _convertirADouble(precio),
        'reg_iva_vta':
            tipoIva, // 🟢 CORREGIDO: Nombre exacto del campo en Velneo
      };

      if (linea['descuento'] != null || linea['por_dto'] != null) {
        lineaVelneo['por_dto'] = _convertirADouble(
          linea['descuento'] ?? linea['por_dto'],
        );
      }

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/VTA_PED_LIN_G')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(json.encode(lineaVelneo));

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(stringData);
      }
      throw Exception(
        'Error al crear línea: ${response.statusCode} - $stringData',
      );
    } catch (e) {
      print('❌ Error en crearLineaPedido: $e');
      rethrow;
    } finally {
      httpClient.close();
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

      final presupuestoVelneo = {
        'emp': '1',
        'emp_div': '1',
        'clt': presupuesto['cliente_id'],
        'obs': presupuesto['observaciones'] ?? '',
      };

      if (presupuesto['comercial_id'] != null &&
          presupuesto['comercial_id'] != 0) {
        presupuestoVelneo['cmr'] = presupuesto['comercial_id'];
      }

      // 🟢 NUEVO: Asignar Serie
      if (presupuesto['serie_id'] != null) {
        presupuestoVelneo['ser'] = presupuesto['serie_id'];
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

      final jsonData = json.encode(visitaVelneo);
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
  // En lib/services/api_service.dart, añadir estas dos funciones después de obtenerTodasLineasPresupuesto():

  Future<List<dynamic>> obtenerTarifasCliente() async {
    try {
      final allTarifas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📄 Descargando tarifas por cliente...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_TAR_CLI_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));
          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_tar_cli_g'] != null &&
                data['vta_tar_cli_g'] is List) {
              final tarifasList = (data['vta_tar_cli_g'] as List).map((tarifa) {
                return {
                  'id': tarifa['id'],
                  'cliente_id': tarifa['clt'] ?? 0,
                  'articulo_id': tarifa['art'] ?? 0,
                  'precio': _convertirADouble(tarifa['pre']),
                  'por_descuento': _convertirADouble(tarifa['por_dto']),
                };
              }).toList();

              if (tarifasList.isEmpty) {
                _log('  🏁 No hay más tarifas por cliente');
                break;
              }

              allTarifas.addAll(tarifasList);
              _log(
                '  ✅ Página $page: ${tarifasList.length} tarifas (Acumulado: ${allTarifas.length}/$totalCount)',
              );

              if (tarifasList.length < pageSize) {
                _log('  🏁 Última página (${tarifasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allTarifas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allTarifas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron tarifas por cliente');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allTarifas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL tarifas por cliente descargadas: ${allTarifas.length}');
      return allTarifas;
    } catch (e) {
      _log('❌ Error en obtenerTarifasCliente: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerTarifasArticulo() async {
    try {
      final allTarifas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📄 Descargando tarifas por artículo...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_TAR_ART_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));
          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_tar_art_g'] != null &&
                data['vta_tar_art_g'] is List) {
              final tarifasList = (data['vta_tar_art_g'] as List).map((tarifa) {
                return {
                  'id': tarifa['id'],
                  'articulo_id': tarifa['art'] ?? 0,
                  'precio': _convertirADouble(tarifa['pre']),
                  'por_descuento': _convertirADouble(tarifa['por_dto']),
                };
              }).toList();

              if (tarifasList.isEmpty) {
                _log('  🏁 No hay más tarifas por artículo');
                break;
              }

              allTarifas.addAll(tarifasList);
              _log(
                '  ✅ Página $page: ${tarifasList.length} tarifas (Acumulado: ${allTarifas.length}/$totalCount)',
              );

              if (tarifasList.length < pageSize) {
                _log('  🏁 Última página (${tarifasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allTarifas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allTarifas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron tarifas por artículo');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allTarifas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL tarifas por artículo descargadas: ${allTarifas.length}');
      return allTarifas;
    } catch (e) {
      _log('❌ Error en obtenerTarifasArticulo: $e');
      return [];
    }
  }

  // Obtener todos los usuarios
  Future<List> obtenerTodosUsuarios() async {
    final allUsuarios = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        final url = _buildUrlWithParams('/usr_m', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['usr_m'] != null && data['usr_m'] is List) {
            final lista = data['usr_m'] as List;

            if (lista.isEmpty) break;

            allUsuarios.addAll(lista.cast<Map<String, dynamic>>());

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total usuarios obtenidos: ${allUsuarios.length}');
      return allUsuarios;
    } catch (e) {
      _log('❌ Error obteniendo usuarios: $e');
      throw Exception('Error al obtener usuarios: $e');
    }
  }

  // Obtener todos los registros de usr_apl
  Future<List> obtenerTodosUsrApl() async {
    final allUsrApl = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        final url = _buildUrlWithParams('/usr_apl', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['usr_apl'] != null && data['usr_apl'] is List) {
            final lista = data['usr_apl'] as List;

            if (lista.isEmpty) break;

            allUsrApl.addAll(lista.cast<Map<String, dynamic>>());

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total usr_apl obtenidos: ${allUsrApl.length}');
      return allUsrApl;
    } catch (e) {
      _log('❌ Error obteniendo usr_apl: $e');
      throw Exception('Error al obtener usr_apl: $e');
    }
  }

  // Buscar comercial por ID en ENT_M
  Future<Map<String, dynamic>?> obtenerComercialPorId(int id) async {
    try {
      final url = _buildUrl('/ent_m/$id');
      _log('🔍 Buscando comercial ID $id');
      _log('📡 URL completa: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status: ${response.statusCode}');
      _log('📥 Response COMPLETO: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('📊 Tipo de data: ${data.runtimeType}');
        _log(
          '📊 Keys disponibles: ${data is Map ? data.keys.toList() : "No es Map"}',
        );

        // Intentar diferentes estructuras de respuesta
        if (data is Map<String, dynamic>) {
          if (data.containsKey('ent_m')) {
            _log('✓ Tiene clave ent_m');
            final entM = data['ent_m'];
            _log('✓ Tipo de ent_m: ${entM.runtimeType}');

            if (entM is List && entM.isNotEmpty) {
              _log('✅ Comercial encontrado (formato lista)');
              final comercial = entM.first as Map<String, dynamic>;
              _log('   Nombre: ${comercial['nom']}');
              _log('   ID: ${comercial['id']}');
              return comercial;
            } else if (entM is Map<String, dynamic>) {
              _log('✅ Comercial encontrado (formato map directo)');
              _log('   Nombre: ${entM['nom']}');
              _log('   ID: ${entM['id']}');
              return entM;
            }
          } else {
            // Podría ser el objeto directo sin envolver
            _log('✅ Comercial encontrado (sin clave ent_m)');
            _log('   Nombre: ${data['nom']}');
            _log('   ID: ${data['id']}');
            return data;
          }
        } else if (data is List && data.isNotEmpty) {
          _log('✅ Comercial encontrado (lista directa)');
          final comercial = data.first as Map<String, dynamic>;
          _log('   Nombre: ${comercial['nom']}');
          _log('   ID: ${comercial['id']}');
          return comercial;
        }

        _log('⚠️ Formato de respuesta no reconocido');
        return null;
      } else if (response.statusCode == 404) {
        _log('❌ Comercial no encontrado (404)');
        return null;
      } else {
        _log('❌ Error HTTP ${response.statusCode}');
        _log('❌ Body: ${response.body}');
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Excepción al buscar comercial: $e');
      throw Exception('Error al buscar comercial por ID: $e');
    }
  }

  // Buscar usuario de app por ID de comercial (ENT) en USR_M
  Future<Map<String, dynamic>?> obtenerUsuarioPorComercial(
    int comercialId,
  ) async {
    try {
      final url = _buildUrl('/usr_m?filter[ent]=$comercialId');
      _log('🔍 Buscando usuario de app para comercial $comercialId');
      _log('📡 URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status: ${response.statusCode}');
      _log('📥 Response completo: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _log('📊 Total registros: ${data['total_count']}');

        final lista = data['usr_m'] as List?;

        if (lista != null && lista.isNotEmpty) {
          _log('✅ Usuarios encontrados: ${lista.length}');
          for (var usr in lista) {
            _log(
              '   - Usuario ID: ${usr['id']}, Nombre: ${usr['name']}, ENT: ${usr['ent']}',
            );
          }
          return lista.first as Map<String, dynamic>;
        } else {
          _log('⚠️ No se encontró usuario de app para comercial $comercialId');
          return null;
        }
      } else {
        _log('❌ Error HTTP ${response.statusCode}: ${response.body}');
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Error al buscar usuario: $e');
      throw Exception('Error al buscar usuario por comercial: $e');
    }
  }

  // Verificar si usuario tiene acceso a la aplicación en USR_APL
  Future<bool> verificarAccesoApp(int usuarioId, int codigoApp) async {
    try {
      final url = _buildUrl(
        '/usr_apl?filter[usr_m]=$usuarioId&filter[apl_tec]=$codigoApp',
      );
      _log('🔐 Verificando acceso en USR_APL');
      _log('   Usuario ID (usr_m): $usuarioId');
      _log('   Código App (apl_tec): $codigoApp');
      _log('📡 URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status: ${response.statusCode}');
      _log('📥 Response completo: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _log('📊 Total registros USR_APL: ${data['total_count']}');

        final lista = data['usr_apl'] as List?;

        if (lista != null && lista.isNotEmpty) {
          _log('✅ Registros de acceso encontrados: ${lista.length}');
          for (var acc in lista) {
            _log(
              '   - ID: ${acc['id']}, usr_m: ${acc['usr_m']}, apl_tec: ${acc['apl_tec']}',
            );
          }
          return true;
        } else {
          _log(
            '❌ No se encontró acceso para usuario $usuarioId en app $codigoApp',
          );
          _log(
            '💡 Verifica que exista un registro en usr_apl con usr_m=$usuarioId y apl_tec=$codigoApp',
          );
          return false;
        }
      } else {
        _log('❌ Error HTTP ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      _log('❌ Error al verificar acceso: $e');
      return false;
    }
  }

  // Buscar usuario de app por ID de comercial Y código de app
  Future<Map<String, dynamic>?> obtenerUsuarioPorComercialYCodigo(
    int comercialId,
    String codigoApp,
  ) async {
    try {
      final url = _buildUrl(
        '/usr_m?filter[ent]=$comercialId&filter[asp]=$codigoApp',
      );
      _log(
        '🔍 Buscando usuario para comercial $comercialId con código app $codigoApp',
      );

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      _log('📥 Status: ${response.statusCode}');
      _log('📥 Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lista = data['usr_m'] as List?;

        if (lista != null && lista.isNotEmpty) {
          _log('✅ Usuario de app encontrado: ${lista.first['name']}');
          return lista.first as Map<String, dynamic>;
        } else {
          _log('⚠️ No se encontró usuario con ese comercial y código de app');
          return null;
        }
      } else {
        _log('❌ Error HTTP ${response.statusCode}');
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Error al buscar usuario: $e');
      throw Exception('Error al buscar usuario: $e');
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
  // Añadir al final de la clase VelneoAPIService en lib/services/api_service.dart (antes del último })

  Future<List<dynamic>> obtenerPedidosIncrementales(DateTime? desde) async {
    try {
      final allPedidos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      _log(
        '📄 Descargando pedidos incrementales desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim', // Más recientes primero
        };

        final url = _buildUrlWithParams('/VTA_PED_G', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['vta_ped_g'] != null && data['vta_ped_g'] is List) {
              final listaPedidos = data['vta_ped_g'] as List;

              if (listaPedidos.isEmpty) {
                _log('  🏁 No hay más pedidos');
                break;
              }

              // Filtrar por fecha de modificación
              final pedidosFiltrados = <Map<String, dynamic>>[];
              for (var pedido in listaPedidos) {
                if (desde != null && pedido['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(
                      pedido['mod_tim'].toString(),
                    );
                    if (fechaMod.isBefore(desde)) {
                      // Ya llegamos a pedidos más antiguos, parar
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    _log('  ⚠️ Error parseando fecha: $e');
                  }
                }

                pedidosFiltrados.add({
                  'id': pedido['id'],
                  'cliente_id': pedido['clt'] ?? 0,
                  'cmr': pedido['cmr'] ?? 0,
                  'fecha': pedido['fch'] ?? DateTime.now().toIso8601String(),
                  'numero': pedido['num_ped'] ?? '',
                  'estado': pedido['est'] ?? '',
                  'observaciones': pedido['obs'] ?? '',
                  'total': _convertirADouble(pedido['tot_ped']),
                  'sincronizado': 1,
                });
              }

              allPedidos.addAll(pedidosFiltrados);
              _log(
                '  ✅ Página $page: ${pedidosFiltrados.length} pedidos nuevos (${listaPedidos.length} totales)',
              );

              if (listaPedidos.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allPedidos.isEmpty) rethrow;
          break;
        }
      }

      _log('✅ TOTAL pedidos incrementales: ${allPedidos.length}');
      return allPedidos;
    } catch (e) {
      _log('❌ Error en obtenerPedidosIncrementales: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerPresupuestosIncrementales(
    DateTime? desde,
  ) async {
    try {
      final allPresupuestos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      _log(
        '📄 Descargando presupuestos incrementales desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim',
        };

        final url = _buildUrlWithParams('/VTA_PRE_G', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['vta_pre_g'] != null && data['vta_pre_g'] is List) {
              final listaPresupuestos = data['vta_pre_g'] as List;

              if (listaPresupuestos.isEmpty) {
                _log('  🏁 No hay más presupuestos');
                break;
              }

              final presupuestosFiltrados = <Map<String, dynamic>>[];
              for (var presupuesto in listaPresupuestos) {
                if (desde != null && presupuesto['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(
                      presupuesto['mod_tim'].toString(),
                    );
                    if (fechaMod.isBefore(desde)) {
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    _log('  ⚠️ Error parseando fecha: $e');
                  }
                }

                presupuestosFiltrados.add({
                  'id': presupuesto['id'],
                  'cliente_id': presupuesto['clt'] ?? 0,
                  'comercial_id': presupuesto['cmr'] ?? 0,
                  'fecha':
                      presupuesto['fch'] ?? DateTime.now().toIso8601String(),
                  'numero': presupuesto['num'] ?? '',
                  'estado': presupuesto['est'] ?? '',
                  'observaciones': presupuesto['obs'] ?? '',
                  'total': _convertirADouble(presupuesto['tot']),
                  'sincronizado': 1,
                });
              }

              allPresupuestos.addAll(presupuestosFiltrados);
              _log(
                '  ✅ Página $page: ${presupuestosFiltrados.length} presupuestos nuevos',
              );

              if (listaPresupuestos.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allPresupuestos.isEmpty) rethrow;
          break;
        }
      }

      _log('✅ TOTAL presupuestos incrementales: ${allPresupuestos.length}');
      return allPresupuestos;
    } catch (e) {
      _log('❌ Error en obtenerPresupuestosIncrementales: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerLeadsIncrementales(DateTime? desde) async {
    try {
      final allLeads = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      _log(
        '📄 Descargando leads incrementales desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim',
        };

        final url = _buildUrlWithParams('/CRM_LEA', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['crm_lea'] != null && data['crm_lea'] is List) {
              final listaLeads = data['crm_lea'] as List;

              if (listaLeads.isEmpty) {
                _log('  🏁 No hay más leads');
                break;
              }

              final leadsFiltrados = <Map<String, dynamic>>[];
              for (var lead in listaLeads) {
                if (desde != null && lead['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(lead['mod_tim'].toString());
                    if (fechaMod.isBefore(desde)) {
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    _log('  ⚠️ Error parseando fecha: $e');
                  }
                }

                leadsFiltrados.add({
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
                });
              }

              allLeads.addAll(leadsFiltrados);
              _log('  ✅ Página $page: ${leadsFiltrados.length} leads nuevos');

              if (listaLeads.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allLeads.isEmpty) rethrow;
          break;
        }
      }

      _log('✅ TOTAL leads incrementales: ${allLeads.length}');
      return allLeads;
    } catch (e) {
      _log('❌ Error en obtenerLeadsIncrementales: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerAgendaIncremental(
    DateTime? desde, [
    int? comercialId,
  ]) async {
    try {
      final allAgendas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      DebugLogger.log(
        '📄 Descargando agenda incremental desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim',
        };

        if (comercialId != null) {
          params['com'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/CRM_AGE', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['crm_age'] != null && data['crm_age'] is List) {
              final agendasList = data['crm_age'] as List;

              if (agendasList.isEmpty) {
                DebugLogger.log('  🏁 No hay más eventos');
                break;
              }

              final agendasFiltradas = <Map<String, dynamic>>[];
              for (var agenda in agendasList) {
                // Validar que tenga fecha de inicio
                if (agenda['fch_ini'] == null ||
                    agenda['fch_ini'].toString().isEmpty) {
                  continue;
                }

                if (desde != null && agenda['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(
                      agenda['mod_tim'].toString(),
                    );
                    if (fechaMod.isBefore(desde)) {
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    DebugLogger.log('  ⚠️ Error parseando fecha: $e');
                  }
                }

                String? limpiarFecha(dynamic fecha) {
                  if (fecha == null) return null;
                  return fecha.toString().replaceAll(RegExp(r'[TZ].*'), '');
                }

                String? limpiarHora(dynamic hora) {
                  if (hora == null) return null;

                  String horaStr = hora.toString().trim();
                  if (horaStr.isEmpty) return null;

                  print('🕐 limpiarHora RAW: "$horaStr"');

                  // Si viene en formato GMT: "Mon Nov 17 09:00:00 2025 GMT"
                  if (horaStr.contains('GMT')) {
                    try {
                      // Extraer la hora usando regex
                      final regex = RegExp(r'\d{2}:\d{2}:\d{2}');
                      final match = regex.firstMatch(horaStr);

                      if (match != null) {
                        final horaExtraida = match.group(0)!;
                        print('✅ Hora extraída de GMT: "$horaExtraida"');
                        return horaExtraida;
                      }
                    } catch (e) {
                      print('❌ Error parseando hora GMT: $horaStr - $e');
                    }
                  }

                  // Si ya viene en formato "HH:MM:SS" directo
                  if (horaStr.contains(':')) {
                    final resultado = horaStr.split('.').first;
                    print('✅ Hora formato directo: "$resultado"');
                    return resultado;
                  }

                  print('⚠️ No se pudo extraer hora de: "$horaStr"');
                  return null;
                }

                agendasFiltradas.add({
                  'id': agenda['id'],
                  'nombre': agenda['name'] ?? '',
                  'cliente_id': agenda['cli'] ?? 0,
                  'tipo_visita': agenda['tip_vis'] ?? 0,
                  'asunto': agenda['asu'] ?? '',
                  'comercial_id': agenda['com'] ?? 0,
                  'campana_id': agenda['crm_cam_com'] ?? 0,
                  'fecha_inicio': limpiarFecha(agenda['fch_ini']) ?? '',
                  'hora_inicio': limpiarHora(agenda['hor_ini']) ?? '',
                  'fecha_fin': limpiarFecha(agenda['fch_fin']) ?? '',
                  'hora_fin': limpiarHora(agenda['hor_fin']) ?? '',
                  'fecha_proxima_visita':
                      limpiarFecha(agenda['fch_pro_vis']) ?? '',
                  'hora_proxima_visita':
                      limpiarHora(agenda['hor_pro_vis']) ?? '',
                  'descripcion': agenda['dsc'] ?? '',
                  'todo_dia': (agenda['tod_dia'] == true) ? 1 : 0,
                  'lead_id': agenda['crm_lea'] ?? 0,
                  'presupuesto_id': agenda['vta_pre_g'] ?? 0,
                  'generado': (agenda['gen'] == true) ? 1 : 0,
                  'sincronizado': 1,
                  'no_gen_pro_vis': agenda['no_gen_pro_vis'] ?? false,
                  'no_gen_tri': agenda['no_gen_tri'] ?? false,
                });
              }

              allAgendas.addAll(agendasFiltradas);
              DebugLogger.log(
                '  ✅ Página $page: ${agendasFiltradas.length} eventos nuevos',
              );

              if (agendasList.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          DebugLogger.log('  ❌ Error en página $page: $e');
          if (allAgendas.isEmpty) rethrow;
          break;
        }
      }

      DebugLogger.log('✅ TOTAL agenda incremental: ${allAgendas.length}');
      return allAgendas;
    } catch (e) {
      DebugLogger.log('❌ Error en obtenerAgendaIncremental: $e');
      rethrow;
    }
  }
  // Añadir después de obtenerAgendaIncremental() en lib/services/api_service.dart

  Future<List<dynamic>> obtenerArticulosIncrementales(DateTime? desde) async {
    try {
      final allArticulos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      print(
        '📄 Descargando artículos incrementales desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim', // Más recientes primero
        };

        final url = _buildUrlWithParams('/ART_M', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['art_m'] != null && data['art_m'] is List) {
              final articulosList = data['art_m'] as List;

              if (articulosList.isEmpty) {
                print('  🏁 No hay más artículos');
                break;
              }

              // Filtrar por fecha de modificación
              final articulosFiltrados = <Map<String, dynamic>>[];
              for (var articulo in articulosList) {
                if (desde != null && articulo['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(
                      articulo['mod_tim'].toString(),
                    );
                    if (fechaMod.isBefore(desde)) {
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    print('  ⚠️ Error parseando fecha: $e');
                  }
                }

                articulosFiltrados.add({
                  'id': articulo['id'],
                  'codigo': articulo['ref'] ?? '',
                  'nombre': articulo['name'] ?? 'Sin nombre',
                  'descripcion': articulo['name'] ?? 'Sin descripción',
                  'precio': _convertirADouble(articulo['pvp']),
                  'stock': articulo['exs'] ?? 0,
                });
              }

              allArticulos.addAll(articulosFiltrados);
              print(
                '  ✅ Página $page: ${articulosFiltrados.length} artículos nuevos (${articulosList.length} totales)',
              );

              if (articulosList.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('  ❌ Error en página $page: $e');
          if (allArticulos.isEmpty) rethrow;
          break;
        }
      }

      print('✅ TOTAL artículos incrementales: ${allArticulos.length}');
      return allArticulos;
    } catch (e) {
      print('❌ Error en obtenerArticulosIncrementales: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> obtenerClientesIncrementales(
    DateTime? desde,
  ) async {
    try {
      final allClientes = <dynamic>[];
      final allComerciales = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      print(
        '📄 Descargando clientes/comerciales incrementales desde: ${desde?.toIso8601String() ?? "inicio"}',
      );

      while (deberiasContinuar) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-mod_tim',
        };

        final url = _buildUrlWithParams('/ENT_M', params);

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['ent_m'] != null && data['ent_m'] is List) {
              final entidadesList = data['ent_m'] as List;

              if (entidadesList.isEmpty) {
                print('  🏁 No hay más registros');
                break;
              }

              // Filtrar por fecha de modificación
              for (var entidad in entidadesList) {
                if (desde != null && entidad['mod_tim'] != null) {
                  try {
                    final fechaMod = DateTime.parse(
                      entidad['mod_tim'].toString(),
                    );
                    if (fechaMod.isBefore(desde)) {
                      deberiasContinuar = false;
                      break;
                    }
                  } catch (e) {
                    print('  ⚠️ Error parseando fecha: $e');
                  }
                }

                final registro = {
                  'id': entidad['id'],
                  'nombre': entidad['nom_fis'] ?? 'Sin nombre',
                  'email': entidad['eml'] ?? '',
                  'telefono': entidad['tlf'] ?? '',
                  'direccion': entidad['dir'] ?? '',
                };

                if (entidad['es_cmr'] == true) {
                  allComerciales.add(registro);
                } else {
                  allClientes.add(registro);
                }
              }

              print(
                '  ✅ Página $page: Clientes: ${allClientes.length}, Comerciales: ${allComerciales.length}',
              );

              if (entidadesList.length < pageSize || !deberiasContinuar) {
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('  ❌ Error en página $page: $e');
          if (allClientes.isEmpty && allComerciales.isEmpty) rethrow;
          break;
        }
      }

      print('✅ TOTAL clientes incrementales: ${allClientes.length}');
      print('✅ TOTAL comerciales incrementales: ${allComerciales.length}');

      return {'clientes': allClientes, 'comerciales': allComerciales};
    } catch (e) {
      print('❌ Error en obtenerClientesIncrementales: $e');
      rethrow;
    }
  }

  Future<Map<String, double>> obtenerConfiguracionIVA() async {
    try {
      // Usamos IMP_M que es la tabla estándar de impuestos.
      // Si tu tabla es diferente, cambia '/IMP_M'
      final url = _buildUrlWithParams('/IMP_M', {'page[size]': '100'});
      print('📥 Descargando configuración de IVA desde $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Valores por defecto seguros
        double general = 21.0;
        double reducido = 10.0;
        double superReducido = 4.0;
        double exento = 0.0;

        // Mapeo de la respuesta
        if (data['imp_m'] != null && data['imp_m'] is List) {
          for (var imp in data['imp_m']) {
            // Asumimos 'cod' para el código (G, R, S) y 'por' para el porcentaje
            // Si en tu vServer los campos son diferentes, cámbialos aquí.
            final codigo = imp['cod']?.toString() ?? '';
            final porcentaje = _convertirADouble(imp['por']);

            if (codigo == 'G') general = porcentaje;
            if (codigo == 'R') reducido = porcentaje;
            if (codigo == 'S') superReducido = porcentaje;
            if (codigo == 'X') exento = porcentaje;
          }
        }

        return {
          'iva_general': general,
          'iva_reducido': reducido,
          'iva_superreducido': superReducido,
          'iva_exento': exento,
        };
      }
      print('⚠️ Error descargando IVA: Status ${response.statusCode}');
      return {};
    } catch (e) {
      print('❌ Error en obtenerConfiguracionIVA: $e');
      return {};
    }
  }

  void dispose() {
    _client.close();
  }
}
