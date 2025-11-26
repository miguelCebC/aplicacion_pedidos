import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../screens/debug_logs_screen.dart';

class VelneoAPIService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client = http.Client();
  final Function(String)? onLog;

  static int _fallosConsecutivos = 0;
  static const int _limiteFallos = 5; // A los 5 fallos seguidos, se cierra

  // Callback estático para avisar a la UI que debe cerrarse
  static Function(String motivo)? onCierreForzoso;

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
      // Configuración de timeout corto para no hacer esperar mucho al usuario
      final request = await httpClient.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final stringData = await response.transform(utf8.decoder).join();

      final httpResponse = http.Response(
        stringData,
        response.statusCode,
        headers: {
          'content-type':
              response.headers.contentType?.toString() ?? 'application/json',
        },
      );

      // SI LLEGAMOS AQUÍ, LA CONEXIÓN TÉCNICA FUE EXITOSA

      // Si el servidor responde (aunque sea 404 o 500), técnicamente hay conexión.
      // Pero si es un error grave (500) o de red, consideramos fallo.
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 500) {
        // ✅ ÉXITO: Reseteamos el contador global
        if (_fallosConsecutivos > 0) {
          _log('✅ Conexión recuperada. Contador de fallos reseteado.');
          _fallosConsecutivos = 0;
        }
        return httpResponse;
      } else {
        throw Exception('Error servidor ${httpResponse.statusCode}');
      }
    } catch (e) {
      // ❌ FALLO DETECTADO
      _fallosConsecutivos++;
      _log('⚠️ Fallo de conexión #$_fallosConsecutivos / $_limiteFallos: $e');

      // 🟢 VERIFICAR SI SUPERAMOS EL LÍMITE
      if (_fallosConsecutivos >= _limiteFallos) {
        _log('⛔ LÍMITE DE FALLOS ALCANZADO. SOLICITANDO CIERRE.');
        if (onCierreForzoso != null) {
          onCierreForzoso!(
            'Se ha perdido la conexión con el servidor tras $_limiteFallos intentos fallidos.',
          );
        }
      }

      // Re-lanzamos el error para que la pantalla local sepa que falló esta petición concreta
      rethrow;
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
  // En lib/services/api_service.dart

  // En lib/services/api_service.dart

  Future<List<dynamic>> obtenerArticulos() async {
    try {
      final allArticulos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📦 Descargando artículos (Todos, con campo OFF)...');

      while (true) {
        // 🟢 PEDIMOS EL CAMPO 'off' Y QUITAMOS FILTROS
        final url = _buildUrlWithParams('/art_m', {
          'fields':
              'id,ref,name,pvp,exs,fam,prv,cod_bar,off', // <--- Pedimos 'off'
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
        });

        _log('  📄 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
            }

            final listaRaw = data['art_m'] ?? data['ART_M'];

            if (listaRaw != null && listaRaw is List) {
              final articulosList = listaRaw;

              if (articulosList.isEmpty) break;

              final articulos = articulosList.map((articulo) {
                // 🟢 DETECTAR VALOR OFF (Boolean o String)
                // Velneo puede devolver true/false o "true"/"false". SQLite necesita 1/0.
                dynamic offRaw = articulo['off'] ?? articulo['OFF'];
                int offVal = 0;
                if (offRaw == true ||
                    offRaw.toString().toLowerCase() == 'true') {
                  offVal = 1;
                }

                return {
                  'id': articulo['id'] ?? articulo['ID'],
                  'codigo': articulo['ref'] ?? articulo['REF'] ?? '',
                  'nombre':
                      articulo['name'] ?? articulo['NAME'] ?? 'Sin nombre',
                  'descripcion': articulo['name'] ?? articulo['NAME'] ?? '',
                  'precio': _convertirADouble(
                    articulo['pvp'] ?? articulo['PVP'],
                  ),
                  'stock': articulo['exs'] ?? articulo['EXS'] ?? 0,
                  'img': '',
                  'familia': articulo['fam'] ?? articulo['FAM'] ?? '',
                  'proveedor_id': articulo['prv'] ?? articulo['PRV'] ?? 0,
                  'codigo_barras':
                      articulo['cod_bar'] ?? articulo['COD_BAR'] ?? '',
                  'off':
                      offVal, // 🟢 Guardamos el estado (0=Activo, 1=Inactivo)
                };
              }).toList();

              allArticulos.addAll(articulos);
              _log('    -> Recibidos ${articulos.length} artículos');

              if (articulos.length < pageSize) break;
              if (totalCount > 0 && allArticulos.length >= totalCount) break;

              page++;
              await Future.delayed(const Duration(milliseconds: 100));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('❌ Error en página $page: $e');
          if (allArticulos.isNotEmpty) break;
          rethrow;
        }
      }

      _log('✅ Total artículos descargados: ${allArticulos.length}');
      return allArticulos;
    } catch (e) {
      _log('❌ Error en obtenerArticulos: $e');
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

      _log('📦 Descargando clientes (OPTIMIZADO y SEPARADO)...');

      while (true) {
        final StringBuffer urlBuffer = StringBuffer();
        String base = baseUrl;
        if (base.endsWith('/')) base = base.substring(0, base.length - 1);

        urlBuffer.write('$base/ENT_M');
        urlBuffer.write(
          '?fields=id,nom_fis,eml,tlf,dir,es_cmr,cmr,cif,nom_com,name',
        );
        urlBuffer.write('&api_key=$apiKey');
        urlBuffer.write('&page[size]=$pageSize');
        urlBuffer.write('&page[number]=$page');

        final url = urlBuffer.toString();

        _log('  📄 Página $page...');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['total_count'] != null) totalCount = data['total_count'];

            if (data['ent_m'] != null && data['ent_m'] is List) {
              final entidadesList = data['ent_m'] as List;

              if (entidadesList.isEmpty) break;

              for (var entidad in entidadesList) {
                String nombreFinal =
                    (entidad['nom_fis'] != null &&
                        entidad['nom_fis'].toString().isNotEmpty)
                    ? entidad['nom_fis']
                    : (entidad['name'] ?? 'Sin nombre');

                int cmrSeguro = 0;
                if (entidad['cmr'] != null) {
                  cmrSeguro = int.tryParse(entidad['cmr'].toString()) ?? 0;
                }

                if (entidad['es_cmr'] == true) {
                  allComerciales.add({
                    'id': entidad['id'],
                    'nombre': nombreFinal,
                    'email': entidad['eml'] ?? '',
                    'telefono': entidad['tlf'] ?? '',
                    'direccion': entidad['dir'] ?? '',
                  });
                } else {
                  allClientes.add({
                    'id': entidad['id'],
                    'nombre': nombreFinal,
                    'email': entidad['eml'] ?? '',
                    'telefono': entidad['tlf'] ?? '',
                    'direccion': entidad['dir'] ?? '',
                    // 🟢 Guardamos el ID limpio y seguro
                    'cmr': cmrSeguro,
                    'cif': entidad['cif'] ?? '',
                    'nom_fis': entidad['nom_fis'] ?? '',
                    'nom_com': entidad['nom_com'] ?? '',
                  });
                }
              }
              // ... resto del código

              if (entidadesList.length < pageSize) break;
              if (totalCount > 0 &&
                  (allClientes.length + allComerciales.length) >= totalCount) {
                break;
              }
              page++;
              await Future.delayed(const Duration(milliseconds: 100));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          if (allClientes.isEmpty && allComerciales.isEmpty) rethrow;
          break;
        }
      }

      _log(
        '✅ Clientes: ${allClientes.length} | Comerciales: ${allComerciales.length}',
      );
      return {'clientes': allClientes, 'comerciales': allComerciales};
    } catch (e) {
      _log('❌ Error en obtenerClientes: $e');
      rethrow;
    }
  }
  // En lib/services/api_service.dart

  // 🟢 DESCARGAR MOVIMIENTOS (Para Sincronización)
  Future<List<dynamic>> obtenerMovimientos([DateTime? desde]) async {
    try {
      final allMovs = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      _log('📦 Descargando movimientos (MOV_G)...');

      while (deberiasContinuar) {
        final params = {
          'fields':
              'id,clt,art,fch,can_ent,can_sal,pre,num_doc,mod_tim', // Campos necesarios
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
          'sort': '-fch', // Ordenar por fecha (más reciente primero)
        };

        // URL segura
        final url = _buildUrlWithParams('/MOV_G', params);

        _log('  📄 Página $page');

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['mov_g'] ?? data['MOV_G'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((mov) {
              return {
                'id': mov['id'] ?? mov['ID'],
                'cliente_id': mov['clt'] ?? mov['CLT'] ?? 0,
                'articulo_id': mov['art'] ?? mov['ART'] ?? 0,
                'fecha': mov['fch'] ?? mov['FCH'] ?? '',
                'num_doc': mov['num_doc'] ?? mov['NUM_DOC'] ?? '',
                'entrada': _convertirADouble(mov['can_ent'] ?? mov['CAN_ENT']),
                'salida': _convertirADouble(mov['can_sal'] ?? mov['CAN_SAL']),
                'precio': _convertirADouble(mov['pre'] ?? mov['PRE']),
              };
            }).toList();

            // Filtro de fecha si es incremental
            if (desde != null) {
              // Lógica incremental simple: si encontramos un registro más viejo que 'desde', paramos.
              // (Asumiendo que 'mod_tim' o 'fch' son fiables)
              // ...
            }

            allMovs.addAll(lista);
            _log('    -> ${lista.length} movimientos recuperados');

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total movimientos descargados: ${allMovs.length}');
      return allMovs;
    } catch (e) {
      _log('❌ Error en obtenerMovimientos: $e');
      rethrow;
    }
  }

  // 🟢 OBTENER MOVIMIENTOS (Base de Conocimiento)
  // No guarda en BD, solo devuelve la lista para mostrar
  Future<List<dynamic>> obtenerMovimientosCliente(int clienteId) async {
    try {
      final allMovs = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando historial de movimientos del cliente $clienteId...');

      while (true) {
        // Pedimos los campos exactos que has indicado
        final url = _buildUrlWithParams('/MOV_G', {
          'filter[clt]': clienteId.toString(),
          'fields': 'id,art,fch,can_ent,can_sal,pre,num_doc',
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
          'sort': '-fch', // Ordenar por fecha (más reciente primero)
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          // Tu JSON devuelve "mov_g"
          final listaRaw = data['mov_g'] ?? data['MOV_G'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((mov) {
              return {
                'id': mov['id'],
                'articulo_id': mov['art'] ?? 0, // ID para buscar luego en local
                'fecha': mov['fch'] ?? '',
                'num_doc': mov['num_doc'] ?? '',
                // Convertimos strings numéricos a double
                'entrada': _convertirADouble(mov['can_ent']),
                'salida': _convertirADouble(mov['can_sal']),
                'precio': _convertirADouble(mov['pre']),
              };
            }).toList();

            allMovs.addAll(lista);

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total movimientos recuperados: ${allMovs.length}');
      return allMovs;
    } catch (e) {
      _log('❌ Error en obtenerMovimientosCliente: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> obtenerDetalleArticulo(int id) async {
    try {
      // 1. Construcción MANUAL de la URL para asegurar el formato exacto
      // Formato deseado: .../ART_M/1234?fields=id,img&api_key=...
      final StringBuffer urlBuffer = StringBuffer();

      // Aseguramos que no haya doble barra // entre base y endpoint
      String base = baseUrl;
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);

      urlBuffer.write('$base/ART_M/$id');
      urlBuffer.write('?fields=id,img'); // 🟢 Coma literal, sin codificar
      urlBuffer.write('&api_key=$apiKey');

      final url = urlBuffer.toString();

      // 🕵️ LOG DE DEBUG: LA LLAMADA
      print('🚀 [DEBUG API] Request URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      // 🕵️ LOG DE DEBUG: LA RESPUESTA
      print('📩 [DEBUG API] Status Code: ${response.statusCode}');
      print(
        '📦 [DEBUG API] Body (primeros 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Lógica de parsing robusta (por si devuelve objeto o lista)
        Map<String, dynamic>? articuloRaw;

        if (data is Map<String, dynamic>) {
          // Caso A: Devuelve objeto directo { "id": ... }
          // A veces Velneo devuelve el objeto directo si se pide por ID
          if (data.containsKey('id')) {
            articuloRaw = data;
          }
          // Caso B: Devuelve envuelto en { "art_m": [ ... ] }
          else if (data['art_m'] != null && data['art_m'] is List) {
            final lista = data['art_m'] as List;
            if (lista.isNotEmpty) articuloRaw = lista[0];
          }
        }

        if (articuloRaw != null) {
          print(
            '✅ [DEBUG API] Imagen encontrada: ${articuloRaw['img'] != null ? "SÍ (${articuloRaw['img'].toString().length} chars)" : "NO"}',
          );

          return {'id': articuloRaw['id'], 'img': articuloRaw['img'] ?? ''};
        } else {
          print(
            '⚠️ [DEBUG API] No se pudo extraer el objeto articulo del JSON',
          );
        }
      } else {
        print('❌ [DEBUG API] Error del servidor: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      print('❌ [DEBUG API] Excepción: $e');
      return null;
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
                dynamic conKyrRaw = pedido['con_kyr'] ?? pedido['CON_KYR'];
                int conKyr = 0;
                if (conKyrRaw == true ||
                    conKyrRaw == 1 ||
                    conKyrRaw.toString() == 'true') {
                  conKyr = 1;
                }

                return {
                  'id': pedido['id'],
                  'cliente_id': pedido['clt'] ?? 0,
                  'cmr': pedido['cmr'] ?? 0,
                  'serie_id': pedido['ser'] ?? 0,
                  'fecha': pedido['fch'] ?? DateTime.now().toIso8601String(),
                  'numero': pedido['num_ped'] ?? '',
                  'num_doc': pedido['num_doc'] ?? 0,
                  'fecha_entrega': pedido['fch_ent'],
                  'forma_pago': pedido['fpg'] ?? 0,
                  'direccion_entrega_id': pedido['dir_env'] ?? 0,
                  'estado': pedido['est'] ?? '',

                  'con_kyr': conKyr, // 🟢 GUARDAMOS EL DATO

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

  // En lib/services/api_service.dart
  // 🟢 1. OBTENER FORMAS DE PAGO (Con estructura: id, name)
  Future<List<dynamic>> obtenerFormasPago() async {
    try {
      final allItems = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📦 Descargando formas de pago...');

      while (true) {
        // Pedimos ID y NAME (según tu JSON)
        final url = _buildUrlWithParams('/FPG_M', {
          'fields': 'id,name',
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // Buscamos la lista (fpg_m o FPG_M)
          final listaRaw = data['fpg_m'] ?? data['FPG_M'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((item) {
              return {
                'id': item['id'],
                // 🟢 IMPORTANTE: Leemos 'name' como indica tu JSON
                'nombre': item['name'] ?? item['NAME'] ?? 'Sin nombre',
              };
            }).toList();

            allItems.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      _log('✅ Formas de pago descargadas: ${allItems.length}');
      return allItems;
    } catch (e) {
      _log('❌ Error en obtenerFormasPago: $e');
      return [];
    }
  }

  // 🟢 2. OBTENER SERIES (Asumiendo misma estructura: id, name)
  Future<List<dynamic>> obtenerSeries() async {
    try {
      final allSeries = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📦 Descargando series...');

      while (true) {
        final url = _buildUrlWithParams('/SER_M', {
          'fields':
              'id,name,ser_tip', // Pedimos name y también el tipo si existe
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['ser_m'] ?? data['SER_M'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((serie) {
              return {
                'id': serie['id'],
                // 🟢 IMPORTANTE: Leemos 'name'
                'nombre':
                    serie['name'] ?? serie['NAME'] ?? 'Serie ${serie['id']}',
                // Tipo (Ventas/Compras) si viniera, sino por defecto
                'tipo': serie['ser_tip'] ?? 'V',
              };
            }).toList();

            allSeries.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      _log('✅ Series descargadas: ${allSeries.length}');
      return allSeries;
    } catch (e) {
      _log('❌ Error en obtenerSeries: $e');
      return [];
    }
  }

  // 🟢 MÉTODO NUEVO: Descargar Contactos
  Future<List<Map<String, dynamic>>> obtenerContactos() async {
    try {
      final allContactos = <Map<String, dynamic>>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📦 Descargando contactos (Teléfonos/Emails)...');

      while (true) {
        // Endpoint /CTT_M (Tabla de contactos)
        final url = _buildUrlWithParams('/CTT_M', {
          'fields': 'id,ent,ctt_clf,val,prn,name', // Campos necesarios
          'page[size]': '$pageSize',
          'page[number]': '$page',
        });

        _log('  📄 Página $page...');

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['ctt_m'] != null && data['ctt_m'] is List) {
            final lista = data['ctt_m'] as List;
            if (lista.isEmpty) break;

            for (var c in lista) {
              allContactos.add({
                'id': c['id'],
                'cliente_id': c['ent'] ?? 0,
                'tipo': c['ctt_clf'] ?? '', // T=Tel, E=Email, F=Fax
                'nombre': c['name'] ?? '',
                'valor': c['val'] ?? '',
                // Convertimos "1" string a 1 entero
                'es_principal': (c['prn'] != null && c['prn'].toString() == '1')
                    ? 1
                    : 0,
              });
            }

            if (lista.length < pageSize) break;
            page++;
            await Future.delayed(const Duration(milliseconds: 100));
          } else {
            break;
          }
        } else {
          // Si falla (ej: no existe el endpoint) salimos para no bloquear
          _log('⚠️ Error descargando contactos: ${response.statusCode}');
          break;
        }
      }

      _log('✅ Total contactos descargados: ${allContactos.length}');
      return allContactos;
    } catch (e) {
      _log('❌ Error en obtenerContactos: $e');
      return []; // Retornamos vacío para no romper la sincronización global
    }
  }

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

      if (pedido['direccion_entrega_id'] != null &&
          pedido['direccion_entrega_id'] != 0) {
        pedidoVelneo['dir_env'] = pedido['direccion_entrega_id'];
      }
      if (pedido['cmr'] != null) pedidoVelneo['cmr'] = pedido['cmr'];
      if (pedido['observaciones'] != null) {
        pedidoVelneo['obs'] = pedido['observaciones'];
      }

      // Enviar estado 'con_kyr' si existe
      if (pedido['con_kyr'] != null) {
        pedidoVelneo['con_kyr'] = pedido['con_kyr'];
      }

      print('📝 Actualizando pedido #$pedidoId: $pedidoVelneo');

      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 45);

      try {
        // 1. Borrar líneas antiguas si se envían líneas nuevas
        if (pedido.containsKey('lineas')) {
          final lineasActuales = await obtenerLineasPedido(pedidoId);
          for (var linea in lineasActuales) {
            if (linea['id'] != null) {
              final reqDel = await httpClient.deleteUrl(
                Uri.parse(_buildUrl('/VTA_PED_LIN_G/${linea['id']}')),
              );
              reqDel.headers.set('Accept', 'application/json');
              final resDel = await reqDel.close();
              await resDel.drain();
            }
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // 2. Actualizar Cabecera
        final request = await httpClient.postUrl(
          Uri.parse(_buildUrl('/VTA_PED_G/$pedidoId')),
        );
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.write(json.encode(pedidoVelneo));

        final response = await request.close();
        final stringData = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200 || response.statusCode == 201) {
          // 3. Crear nuevas líneas
          int lineasOk = 0;
          if (pedido['lineas'] != null) {
            for (var linea in pedido['lineas']) {
              try {
                await crearLineaPedido(pedidoId, linea);
                lineasOk++;
              } catch (e) {
                print('   ⚠️ Error línea: $e');
              }
            }
          }
          // 🟢 RETORNO EXITOSO
          return {'id': pedidoId, 'lineas_creadas': lineasOk, 'success': true};
        } else {
          // 🔴 ERROR SI NO ES 200/201
          throw Exception('Error HTTP ${response.statusCode}: $stringData');
        }
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

  // 🟢 1. OBTENER FOTO PEDIDO (Sin guardar en local)
  Future<String?> obtenerFotoPedido(int pedidoId) async {
    try {
      // Pedimos solo el campo 'fot' para no traer datos innecesarios
      final url = _buildUrl('/VTA_PED_G/$pedidoId') + '&fields=id,fot';

      print('📸 Descargando foto del pedido #$pedidoId...');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Lógica para extraer el dato sea cual sea el formato de respuesta
        Map<String, dynamic>? registro;

        if (data is Map<String, dynamic>) {
          if (data.containsKey('id')) {
            registro = data;
          } else if (data['vta_ped_g'] != null &&
              (data['vta_ped_g'] is List) &&
              (data['vta_ped_g'] as List).isNotEmpty) {
            registro = data['vta_ped_g'][0];
          }
        }

        if (registro != null) {
          final foto = registro['fot'] as String?;
          if (foto != null && foto.isNotEmpty) {
            print('✅ Foto encontrada (${foto.length} caracteres)');
            return foto;
          }
        }
      }
      print('⚠️ No hay foto o error en respuesta');
      return null;
    } catch (e) {
      print('❌ Error obteniendo foto: $e');
      return null;
    }
  }

  // 🟢 2. ACTUALIZAR FOTO PEDIDO (Subir o Borrar)
  Future<bool> actualizarFotoPedido(int pedidoId, String? base64Foto) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(
        seconds: 60,
      ); // Más tiempo para subir imágenes

    try {
      print('📤 Subiendo/Actualizando foto pedido #$pedidoId...');

      // Enviamos cadena vacía "" si base64Foto es null, para borrarla en Velneo
      final bodyVelneo = {'fot': base64Foto ?? ""};

      // Petición POST al recurso específico ID para hacer update parcial
      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_G/$pedidoId')),
      );

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(bodyVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        print('✅ Foto actualizada correctamente en servidor');
        return true;
      } else {
        print('❌ Error subiendo foto (${response.statusCode}): $stringData');
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Excepción subiendo foto: $e');
      return false;
    } finally {
      httpClient.close();
    }
  }

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
                  'dto1': _convertirADouble(linea['dto1']),
                  'dto2': _convertirADouble(linea['dto2']),
                  'dto3': _convertirADouble(linea['dto3']),
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
            return {
              'id': linea['id'],
              'pedido_id': linea['vta_ped'] ?? pedidoId,
              'articulo_id': linea['art'] ?? 0,
              'cantidad': _convertirADouble(linea['can_ped']),
              'precio': _convertirADouble(linea['pre']),
              'por_descuento': _convertirADouble(linea['por_dto']),
              'dto1': _convertirADouble(linea['dto1']),
              'dto2': _convertirADouble(linea['dto2']),
              'dto3': _convertirADouble(linea['dto3']),
              // ----------------
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
        'fch': pedido['fecha'],
      };

      // 🟢 CAMBIO: Usamos 'dir_env'
      if (pedido['direccion_entrega_id'] != null &&
          pedido['direccion_entrega_id'] != 0) {
        pedidoVelneo['dir_env'] = pedido['direccion_entrega_id'];
      }

      if (pedido['cmr'] != null) {
        pedidoVelneo['cmr'] = pedido['cmr'];
      }
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

          final listaRaw = respuesta['vta_ped_g'] ?? respuesta['VTA_PED_G'];

          if (listaRaw != null &&
              listaRaw is List &&
              (listaRaw as List).isNotEmpty) {
            final primerElemento = listaRaw[0];
            pedidoId =
                _parseIntSeguro(primerElemento['id']) ??
                _parseIntSeguro(primerElemento['ID']);
          } else {
            pedidoId =
                _parseIntSeguro(respuesta['id']) ??
                _parseIntSeguro(respuesta['ID']);
          }

          if (pedidoId == null) {
            throw Exception(
              'No se pudo obtener el ID del pedido creado. Respuesta: $stringData',
            );
          }

          print('✅ Pedido creado con ID: $pedidoId');

          int lineasOk = 0;
          if (pedido['lineas'] != null) {
            for (var linea in pedido['lineas']) {
              try {
                await crearLineaPedido(pedidoId, linea);
                lineasOk++;
              } catch (e) {
                print('  ✗ Error línea: $e');
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
      print('❌ Error en crearPedido: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> crearLineaPedido(
    int pedidoId,
    Map<String, dynamic> linea,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      // Preparamos el objeto JSON con TODOS los campos necesarios
      final lineaVelneo = {
        'vta_ped': pedidoId,
        'emp': '1',
        'art': linea['articulo_id'],
        'can_ped': _convertirADouble(linea['cantidad']),
        'pre': _convertirADouble(linea['precio']),
        'reg_iva_vta': linea['tipo_iva'] ?? 'G', // IVA
        // Descuentos en cascada
        'dto1': _convertirADouble(linea['dto1']),
        'dto2': _convertirADouble(linea['dto2']),
        'dto3': _convertirADouble(linea['dto3']),

        // Tipo de descuento (0=%, 1=Importe)
        //'tip_dto': linea['tipo_dto'] ?? 0,
      };

      // Compatibilidad: Si hay descuento general, lo mandamos también
      if (linea['por_dto'] != null) {
        lineaVelneo['por_dto'] = _convertirADouble(linea['por_dto']);
      }

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_LIN_G')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(lineaVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(stringData);
      }
      throw Exception('Error línea (${response.statusCode}): $stringData');
    } finally {
      httpClient.close();
    }
  }

  int? _parseIntSeguro(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      return int.tryParse(value);
    }
    return null;
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

  Future<List<dynamic>> obtenerDirecciones() async {
    try {
      final allDirecciones = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando direcciones...');

      while (true) {
        final url = _buildUrlWithParams('/DIR_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['dir_m'] != null && data['dir_m'] is List) {
            final lista = (data['dir_m'] as List).map((d) {
              return {
                'id': d['id'],
                'ent': d['ent'], // ID del cliente
                'direccion': d['dir_ver'] ?? d['dir'] ?? 'Sin dirección',
              };
            }).toList();

            if (lista.isEmpty) break;
            allDirecciones.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      _log('✅ Direcciones descargadas: ${allDirecciones.length}');
      return allDirecciones;
    } catch (e) {
      _log('❌ Error obtenerDirecciones: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> crearVisitaAgenda(
    Map<String, dynamic> visita,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
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

      if (visita['hora_inicio'] != null) {
        visitaVelneo['hor_ini'] = visita['hora_inicio'];
      }
      if (visita['fecha_fin'] != null) {
        visitaVelneo['fch_fin'] = visita['fecha_fin'];
      }
      if (visita['hora_fin'] != null) {
        visitaVelneo['hor_fin'] = visita['hora_fin'];
      }
      if (visita['campana_id'] != 0) {
        visitaVelneo['crm_cam_com'] = visita['campana_id'];
      }

      // 🟢 NUEVO: Enviar Dirección
      if (visita['direccion_id'] != null && visita['direccion_id'] != 0) {
        visitaVelneo['dir'] = visita['direccion_id'];
      }

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/CRM_AGE')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(visitaVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);
        final id =
            (respuesta['crm_age'] != null && respuesta['crm_age'].isNotEmpty)
            ? respuesta['crm_age'][0]['id']
            : respuesta['id'];
        return {'id': id, 'success': true};
      }
      throw Exception('Error HTTP ${response.statusCode}');
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
                  // 🟢 Mapear nombre tarifa si viene en el JSON (ej: 'tar_name' o 'nom')
                  'nombre_tarifa':
                      tarifa['tar_name'] ??
                      tarifa['nom'] ??
                      'Tarifa ${tarifa['tar'] ?? ''}',
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
  // ... dentro de la clase VelneoAPIService ...

  Future<List<dynamic>> obtenerFamilias() async {
    try {
      print('📄 Descargando familias...');
      final allFamilias = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      while (true) {
        final url = _buildUrlWithParams('/FAM_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['fam_m'] != null && data['fam_m'] is List) {
            final lista = (data['fam_m'] as List).map((fam) {
              return {
                'id': fam['id'],
                'nombre': fam['name'] ?? fam['nom'] ?? 'Sin nombre',
              };
            }).toList();

            if (lista.isEmpty) break;
            allFamilias.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      print('✅ Familias descargadas: ${allFamilias.length}');
      return allFamilias;
    } catch (e) {
      print('❌ Error en obtenerFamilias: $e');
      return []; // Retornar vacío en caso de error para no bloquear sync
    }
  }

  // Obtener todos los usuarios
  Future<List> obtenerTodosUsuarios() async {
    final allUsuarios = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        final url = _buildUrlWithParams('/USR_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['USR_M'] ?? data['usr_m'];

          if (listaRaw != null && listaRaw is List) {
            final lista = listaRaw;

            if (lista.isEmpty) break;

            final listaMapeada = lista.map((item) {
              return {
                'id': item['id'] ?? item['ID'],
                'name': item['name'] ?? item['NAME'] ?? '',
                'ent': item['ent'] ?? item['ENT'],
              };
            }).toList();

            allUsuarios.addAll(listaMapeada.cast<Map<String, dynamic>>());

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allUsuarios;
    } catch (e) {
      throw Exception('Error al obtener usuarios: $e');
    }
  }

  Future<List> obtenerTodosUsrApl() async {
    final allUsrApl = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        // 🟢 Usamos MAYÚSCULAS para la tabla y QUITAMOS el filtro 'fields'
        // Esto asegura que baje todo el objeto tal cual
        final url = _buildUrlWithParams('/USR_APL', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          // Intentamos leer con mayúsculas o minúsculas
          final listaRaw = data['USR_APL'] ?? data['usr_apl'];

          if (listaRaw != null && listaRaw is List) {
            final lista = listaRaw;

            if (lista.isEmpty) break;

            final listaMapeada = lista.map((item) {
              // Mapeo flexible
              final id = item['id'] ?? item['ID'];
              final usrM = item['usr_m'] ?? item['USR_M'];
              final aplTec = item['apl_tec'] ?? item['APL_TEC'];

              // Campo OFF (opcional, por defecto false si no viene)
              dynamic offRaw = item['off'] ?? item['OFF'];
              bool offValue = false;
              if (offRaw == true ||
                  offRaw.toString().toLowerCase() == 'true' ||
                  offRaw == 1 ||
                  offRaw.toString() == '1') {
                offValue = true;
              }

              return {
                'id': id,
                'usr_m': usrM,
                'apl_tec': aplTec,
                'off': offValue,
              };
            }).toList();

            allUsrApl.addAll(listaMapeada);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allUsrApl;
    } catch (e) {
      throw Exception('Error al obtener USR_APL: $e');
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

  Future<int> crearCliente(Map<String, dynamic> cliente) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final clienteVelneo = {
        'nom_fis': cliente['nombre'],
        'nom_com': cliente['nombre_comercial'] ?? '',
        'cif': cliente['cif'] ?? '',
        'tlf': cliente['telefono'] ?? '',
        'eml': cliente['email'] ?? '',
        'dir': cliente['direccion'] ?? '',
        'es_clt': true,
        'emp': '1',
      };

      if (cliente['comercial_id'] != null) {
        clienteVelneo['cmr'] = cliente['comercial_id'];
      }

      //  IMPRIMIR LA URL PARA VERIFICARLA
      final urlDestino = _buildUrl('/ENT_M');
      print(
        '🚀 [DEBUG] URL API: $urlDestino',
      ); // <--- ESTA LÍNEA TE DIRÁ LA URL

      final request = await httpClient.postUrl(Uri.parse(urlDestino));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(clienteVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      //  IMPRIMIR LA RESPUESTA DEL SERVIDOR SI FALLA
      print('📥 [DEBUG] Status: ${response.statusCode}');
      if (response.statusCode != 200 && response.statusCode != 201) {
        print('📥 [DEBUG] Error Body: $stringData');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(stringData);
        if (data['id'] != null) return data['id'];
        if (data['ent_m'] != null && (data['ent_m'] as List).isNotEmpty) {
          return data['ent_m'][0]['id'];
        }
      }
      throw Exception(
        'Error creando cliente: ${response.statusCode} - $stringData',
      );
    } finally {
      httpClient.close();
    }
  }

  //  2. CREAR CONTACTO (CORREGIDO: Ignora SSL)
  Future<void> crearContacto(Map<String, dynamic> contacto) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final contactoVelneo = {
        'ent': contacto['cliente_id'],
        'ctt_clf': contacto['tipo'],
        'val': contacto['valor'],
        'name': contacto['nombre'] ?? '',
        'prn': contacto['es_principal'] == 1,
      };

      final request = await httpClient.postUrl(Uri.parse(_buildUrl('/CTT_M')));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(contactoVelneo));

      final response = await request.close();
      await response.drain();
    } catch (e) {
      print('⚠️ Error creando contacto: $e');
    } finally {
      httpClient.close();
    }
  }

  Future<void> crearDireccion(Map<String, dynamic> direccion) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final direccionVelneo = {
        'ent': direccion['cliente_id'],
        'dir': direccion['direccion'],
        'cps': direccion['cp'] ?? '',
        'loc': direccion['poblacion'] ?? '',
        'cmr': direccion['comercial_id'],
        'tip_de_dir': 1,
        'pai': 1,
        'name': direccion['direccion'],
        'off': false,
      };

      print(
        '🚀 [DEBUG DIR] Enviando JSON CORRECTO: ${json.encode(direccionVelneo)}',
      );

      final request = await httpClient.postUrl(Uri.parse(_buildUrl('/DIR_M')));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(direccionVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      print('📥 [DEBUG DIR] Respuesta: ${response.statusCode} - $stringData');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error al crear dirección: $stringData');
      }
    } catch (e) {
      print('❌ Error creando dirección: $e');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, double>> obtenerConfiguracionIVA() async {
    try {
      final url = _buildUrlWithParams('/IMP_M', {'page[size]': '100'});
      print('📥 Descargando configuración de IVA desde $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        double general = 21.0;
        double reducido = 10.0;
        double superReducido = 4.0;
        double exento = 0.0;

        // Mapeo de la respuesta
        if (data['imp_m'] != null && data['imp_m'] is List) {
          for (var imp in data['imp_m']) {
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
