import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('velneo_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFilePath = path_helper.join(dbPath, filePath);

    return await openDatabase(
      dbFilePath,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    print('🔨 Creando base de datos versión $version');

    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT,
        telefono TEXT,
        direccion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        precio REAL NOT NULL,
        stock INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT NOT NULL,
        rol TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE comerciales (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT,
        telefono TEXT,
        direccion TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE provincias (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        prefijo_cp TEXT,
        pais INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE zonas_tecnicas (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        observaciones TEXT,
        tecnico_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE poblaciones (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        km INTEGER,
        zona_tecnica_id INTEGER,
        codigo_postal TEXT,
        FOREIGN KEY (zona_tecnica_id) REFERENCES zonas_tecnicas (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE campanas_comerciales (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        fecha_inicio TEXT,
        fecha_fin TEXT,
        sector INTEGER,
        provincia_id INTEGER,
        poblacion_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE tipos_visita (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE leads (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        fecha_alta TEXT,
        campana_id INTEGER,
        cliente_id INTEGER,
        asunto TEXT,
        descripcion TEXT,
        comercial_id INTEGER,
        estado TEXT,
        fecha TEXT,
        enviado INTEGER DEFAULT 0,
        agendado INTEGER DEFAULT 0,
        agenda_id INTEGER,
        FOREIGN KEY (campana_id) REFERENCES campanas_comerciales (id),
        FOREIGN KEY (cliente_id) REFERENCES clientes (id),
        FOREIGN KEY (comercial_id) REFERENCES comerciales (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE agenda (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        cliente_id INTEGER,
        tipo_visita INTEGER,
        asunto TEXT,
        comercial_id INTEGER,
        campana_id INTEGER,
        fecha_inicio TEXT,
        hora_inicio TEXT,
        fecha_fin TEXT,
        hora_fin TEXT,
        fecha_proxima_visita TEXT,
        hora_proxima_visita TEXT,
        descripcion TEXT,
        todo_dia INTEGER DEFAULT 0,
        lead_id INTEGER,
        presupuesto_id INTEGER,
        generado INTEGER DEFAULT 1,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (cliente_id) REFERENCES clientes (id),
        FOREIGN KEY (comercial_id) REFERENCES comerciales (id),
        FOREIGN KEY (campana_id) REFERENCES campanas_comerciales (id),
        FOREIGN KEY (lead_id) REFERENCES leads (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY,
        cliente_id INTEGER NOT NULL,
        usuario_id INTEGER,
        cmr INTEGER,
        fecha TEXT NOT NULL,
        estado TEXT,
        observaciones TEXT,
        total REAL,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (cliente_id) REFERENCES clientes (id),
        FOREIGN KEY (cmr) REFERENCES comerciales (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE lineas_pedido (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id INTEGER NOT NULL,
        articulo_id INTEGER NOT NULL,
        cantidad REAL NOT NULL,
        precio REAL NOT NULL,
        FOREIGN KEY (pedido_id) REFERENCES pedidos (id),
        FOREIGN KEY (articulo_id) REFERENCES articulos (id)
      )
    ''');

    print('✅ Base de datos creada correctamente');
  }

  Future<int> obtenerUltimoIdAgenda() async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(id) as max_id FROM agenda');

    if (result.isNotEmpty && result.first['max_id'] != null) {
      return result.first['max_id'] as int;
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> obtenerAgendasNoSincronizadas([
    int? comercialId,
  ]) async {
    final db = await database;
    if (comercialId != null) {
      return await db.query(
        'agenda',
        where: 'sincronizado = 0 AND comercial_id = ?',
        whereArgs: [comercialId],
        orderBy: 'fecha_inicio DESC',
      );
    }
    return await db.query(
      'agenda',
      where: 'sincronizado = 0',
      orderBy: 'fecha_inicio DESC',
    );
  }

  Future<int> actualizarAgendaSincronizada(
    int agendaId,
    int idVelneo,
    int sincronizado,
  ) async {
    final db = await database;
    return await db.update(
      'agenda',
      {
        'id': idVelneo, // Actualizar con el ID de Velneo
        'sincronizado': sincronizado,
      },
      where: 'id = ?',
      whereArgs: [agendaId],
    );
  }

  Future<int> contarAgendasPendientes([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM agenda WHERE sincronizado = 0 AND comercial_id = ?',
        [comercialId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM agenda WHERE sincronizado = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Actualizando BD de versión $oldVersion a $newVersion');

    if (oldVersion < 2) {
      // Crear tabla comerciales si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS comerciales (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          email TEXT,
          telefono TEXT,
          direccion TEXT
        )
      ''');

      // Agregar columna cmr a pedidos si no existe
      try {
        await db.execute('ALTER TABLE pedidos ADD COLUMN cmr INTEGER');
        print('✅ Columna cmr agregada a pedidos');
      } catch (e) {
        print('⚠️ Columna cmr ya existe o error: $e');
      }

      // Crear tablas CRM
      await db.execute('''
        CREATE TABLE IF NOT EXISTS provincias (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          prefijo_cp TEXT,
          pais INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS zonas_tecnicas (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          observaciones TEXT,
          tecnico_id INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS poblaciones (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          km INTEGER,
          zona_tecnica_id INTEGER,
          codigo_postal TEXT,
          FOREIGN KEY (zona_tecnica_id) REFERENCES zonas_tecnicas (id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS campanas_comerciales (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          fecha_inicio TEXT,
          fecha_fin TEXT,
          sector INTEGER,
          provincia_id INTEGER,
          poblacion_id INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS leads (
          id INTEGER PRIMARY KEY,
          nombre TEXT,
          fecha_alta TEXT,
          campana_id INTEGER,
          cliente_id INTEGER,
          asunto TEXT,
          descripcion TEXT,
          comercial_id INTEGER,
          estado TEXT,
          fecha TEXT,
          enviado INTEGER DEFAULT 0,
          agendado INTEGER DEFAULT 0,
          agenda_id INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS agenda (
          id INTEGER PRIMARY KEY,
          nombre TEXT,
          cliente_id INTEGER,
          tipo_visita INTEGER,
          asunto TEXT,
          comercial_id INTEGER,
          campana_id INTEGER,
          fecha_inicio TEXT NOT NULL,
          hora_inicio TEXT,
          fecha_fin TEXT,
          hora_fin TEXT,
          fecha_proxima_visita TEXT,
          hora_proxima_visita TEXT,
          descripcion TEXT,
          todo_dia INTEGER DEFAULT 0,
          lead_id INTEGER,
          presupuesto_id INTEGER,
          generado INTEGER DEFAULT 1
        )
      ''');

      print('✅ Tablas CRM creadas');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS poblaciones (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          km INTEGER,
          zona_tecnica_id INTEGER,
          codigo_postal TEXT,
          FOREIGN KEY (zona_tecnica_id) REFERENCES zonas_tecnicas (id)
        )
      ''');

      print('✅ Tablas CRM creadas');
    }
    if (oldVersion < 3) {
      // Recrear tabla agenda sin NOT NULL en fecha_inicio
      try {
        await db.execute('DROP TABLE IF EXISTS agenda');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS agenda (
          id INTEGER PRIMARY KEY,
          nombre TEXT,
          cliente_id INTEGER,
          tipo_visita INTEGER,
          asunto TEXT,
          comercial_id INTEGER,
          campana_id INTEGER,
          fecha_inicio TEXT,
          hora_inicio TEXT,
          fecha_fin TEXT,
          hora_fin TEXT,
          fecha_proxima_visita TEXT,
          hora_proxima_visita TEXT,
          descripcion TEXT,
          todo_dia INTEGER DEFAULT 0,
          lead_id INTEGER,
          presupuesto_id INTEGER,
          generado INTEGER DEFAULT 1,
          sincronizado INTEGER DEFAULT 0
        )
      ''');
        print('✅ Tabla agenda recreada sin restricción NOT NULL');
      } catch (e) {
        print('⚠️ Error recreando tabla agenda: $e');
      }
    }
    if (oldVersion < 4) {
      // Agregar columna sincronizado a agenda
      try {
        await db.execute(
          'ALTER TABLE agenda ADD COLUMN sincronizado INTEGER DEFAULT 0',
        );
        print('✅ Columna sincronizado agregada a agenda');
      } catch (e) {
        print('⚠️ Columna sincronizado ya existe en agenda: $e');
      }

      // Crear tabla tipos_visita
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tipos_visita (
          id INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL
        )
      ''');
      print('✅ Tabla tipos_visita creada');
    }
    if (oldVersion < 4) {
      // Agregar columna sincronizado a agenda
      try {
        await db.execute(
          'ALTER TABLE agenda ADD COLUMN sincronizado INTEGER DEFAULT 0',
        );
        print('✅ Columna sincronizado agregada a agenda');
      } catch (e) {
        print('⚠️ Columna sincronizado ya existe en agenda: $e');
      }
    }
  }

  Future<int> insertarCliente(Map<String, dynamic> cliente) async {
    final db = await database;
    return await db.insert(
      'clientes',
      cliente,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerClientes([String? busqueda]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'clientes',
        where: 'nombre LIKE ? OR id LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('clientes', orderBy: 'nombre');
  }

  Future<int> actualizarPedidoSincronizado(
    int pedidoId,
    int sincronizado,
  ) async {
    final db = await database;
    return await db.update(
      'pedidos',
      {'sincronizado': sincronizado},
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
  }

  // Insertar artículos por lotes
  Future<void> insertarArticulosLote(
    List<Map<String, dynamic>> articulos,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var articulo in articulos) {
      batch.insert(
        'articulos',
        articulo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Insertar clientes por lotes
  Future<void> insertarClientesLote(List<Map<String, dynamic>> clientes) async {
    final db = await database;
    final batch = db.batch();

    for (var cliente in clientes) {
      batch.insert(
        'clientes',
        cliente,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Insertar comerciales por lotes
  Future<void> insertarComercialesLote(
    List<Map<String, dynamic>> comerciales,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var comercial in comerciales) {
      batch.insert(
        'comerciales',
        comercial,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerComerciales() async {
    final db = await database;
    return await db.query('comerciales', orderBy: 'nombre');
  }
  // ========== MÉTODOS PARA CRM ==========

  // Provincias
  Future<void> insertarProvinciasLote(
    List<Map<String, dynamic>> provincias,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var provincia in provincias) {
      batch.insert(
        'provincias',
        provincia,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerProvincias() async {
    final db = await database;
    return await db.query('provincias', orderBy: 'nombre');
  }

  Future<void> limpiarProvincias() async {
    final db = await database;
    await db.delete('provincias');
  }

  // Zonas Técnicas
  Future<void> insertarZonasTecnicasLote(
    List<Map<String, dynamic>> zonas,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var zona in zonas) {
      batch.insert(
        'zonas_tecnicas',
        zona,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerZonasTecnicas() async {
    final db = await database;
    return await db.query('zonas_tecnicas', orderBy: 'nombre');
  }

  Future<void> limpiarZonasTecnicas() async {
    final db = await database;
    await db.delete('zonas_tecnicas');
  }

  // Poblaciones
  Future<void> insertarPoblacionesLote(
    List<Map<String, dynamic>> poblaciones,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var poblacion in poblaciones) {
      batch.insert(
        'poblaciones',
        poblacion,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerPoblaciones([
    String? busqueda,
  ]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'poblaciones',
        where: 'nombre LIKE ? OR codigo_postal LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('poblaciones', orderBy: 'nombre');
  }
  // ========== CAMPAÑAS COMERCIALES ==========

  Future<void> insertarCampanasLote(List<Map<String, dynamic>> campanas) async {
    final db = await database;
    final batch = db.batch();

    for (var campana in campanas) {
      batch.insert(
        'campanas_comerciales',
        campana,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerCampanas() async {
    final db = await database;
    return await db.query('campanas_comerciales', orderBy: 'fecha_inicio DESC');
  }

  Future<void> limpiarCampanas() async {
    final db = await database;
    await db.delete('campanas_comerciales');
  }
  // ========== TIPOS DE VISITA ==========

  Future<void> insertarTiposVisitaLote(List<Map<String, dynamic>> tipos) async {
    final db = await database;
    final batch = db.batch();

    for (var tipo in tipos) {
      batch.insert(
        'tipos_visita',
        tipo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerTiposVisita() async {
    final db = await database;
    return await db.query('tipos_visita', orderBy: 'id');
  }

  Future<void> limpiarTiposVisita() async {
    final db = await database;
    await db.delete('tipos_visita');
  }

  // ========== CAMPAÑAS COMERCIALES ==========
  // ========== LEADS ==========

  Future<void> insertarLeadsLote(List<Map<String, dynamic>> leads) async {
    final db = await database;
    final batch = db.batch();

    for (var lead in leads) {
      batch.insert('leads', lead, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerLeads([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      return await db.query(
        'leads',
        where: 'comercial_id = ?',
        whereArgs: [comercialId],
        orderBy: 'fecha DESC',
      );
    }
    return await db.query('leads', orderBy: 'fecha DESC');
  }

  Future<void> limpiarLeads() async {
    final db = await database;
    await db.delete('leads');
  }

  // ========== AGENDA ==========

Future<void> insertarAgendasLote(List<Map<String, dynamic>> agendas) async {
  final db = await database;
  final batch = db.batch();

  for (var agenda in agendas) {
    // Validar que la fecha sea correcta antes de insertar
    if (agenda['fecha_inicio'] != null) {
      try {
        final fecha = DateTime.parse(agenda['fecha_inicio'].toString());
        if (fecha.year < 2000) {
          print('⚠️ Fecha inválida detectada: ${agenda['fecha_inicio']}, omitiendo visita ${agenda['id']}');
          continue; // Saltar esta visita
        }
      } catch (e) {
        print('⚠️ Error al parsear fecha: ${agenda['fecha_inicio']}, omitiendo visita ${agenda['id']}');
        continue;
      }
    }
    
    batch.insert(
      'agenda',
      agenda,
      conflictAlgorithm: ConflictAlgorithm.ignore, // ← Cambiar de replace a ignore
    );
  }

  await batch.commit(noResult: true);
}

  Future<List<Map<String, dynamic>>> obtenerAgenda([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      return await db.query(
        'agenda',
        where: 'comercial_id = ?',
        whereArgs: [comercialId],
        orderBy: 'fecha_inicio DESC',
      );
    }
    return await db.query('agenda', orderBy: 'fecha_inicio DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerAgendaPorFecha(
    int comercialId,
    DateTime fecha,
  ) async {
    final db = await database;
    final fechaStr = fecha.toIso8601String().split('T')[0];

    return await db.query(
      'agenda',
      where: 'comercial_id = ? AND date(fecha_inicio) = ?',
      whereArgs: [comercialId, fechaStr],
      orderBy: 'hora_inicio',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerAgendaRango(
    int comercialId,
    DateTime inicio,
    DateTime fin,
  ) async {
    final db = await database;

    return await db.query(
      'agenda',
      where:
          'comercial_id = ? AND date(fecha_inicio) >= ? AND date(fecha_inicio) <= ?',
      whereArgs: [
        comercialId,
        inicio.toIso8601String().split('T')[0],
        fin.toIso8601String().split('T')[0],
      ],
      orderBy: 'fecha_inicio, hora_inicio',
    );
  }

  Future<void> limpiarAgenda() async {
    final db = await database;
    await db.delete('agenda');
  }

  Future<void> limpiarPoblaciones() async {
    final db = await database;
    await db.delete('poblaciones');
  }

  // Limpiar tablas específicas
  Future<void> limpiarArticulos() async {
    final db = await database;
    await db.delete('articulos');
  }

  Future<void> limpiarClientes() async {
    final db = await database;
    await db.delete('clientes');
  }

  Future<void> limpiarComerciales() async {
    final db = await database;
    await db.delete('comerciales');
  }

  Future<int> insertarArticulo(Map<String, dynamic> articulo) async {
    final db = await database;
    return await db.insert(
      'articulos',
      articulo,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerArticulos([
    String? busqueda,
  ]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'articulos',
        where: 'nombre LIKE ? OR codigo LIKE ? OR id LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('articulos', orderBy: 'nombre');
  }

  Future<int> insertarUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert(
      'usuarios',
      usuario,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertarPedido(Map<String, dynamic> pedido) async {
    final db = await database;
    return await db.insert(
      'pedidos',
      pedido,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertarLineaPedido(Map<String, dynamic> linea) async {
    final db = await database;
    return await db.insert('lineas_pedido', linea);
  }

  Future<List<Map<String, dynamic>>> obtenerPedidos() async {
    final db = await database;
    return await db.query('pedidos', orderBy: 'fecha DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerLineasPedido(int pedidoId) async {
    final db = await database;
    return await db.query(
      'lineas_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<void> limpiarBaseDatos() async {
    final db = await database;
    await db.delete('lineas_pedido');
    await db.delete('pedidos');
    await db.delete('agenda');
    await db.delete('leads');
    await db.delete('campanas_comerciales');
    await db.delete('tipos_visita');
    await db.delete('articulos');
    await db.delete('clientes');
    await db.delete('comerciales');
    await db.delete('usuarios');
    await db.delete('poblaciones');
    await db.delete('zonas_tecnicas');
    await db.delete('provincias');
  }

  Future<void> cargarDatosPrueba() async {
    final db = await database;

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM clientes'),
    );

    if (count != null && count > 0) return;

    await db.insert('clientes', {
      'id': 1,
      'nombre': 'Juan Pérez',
      'email': 'juan@email.com',
      'telefono': '600123456',
      'direccion': 'Calle Mayor 1, Madrid',
    });

    await db.insert('clientes', {
      'id': 2,
      'nombre': 'María García',
      'email': 'maria@email.com',
      'telefono': '600234567',
      'direccion': 'Av. Principal 25, Barcelona',
    });

    await db.insert('clientes', {
      'id': 3,
      'nombre': 'Carlos López',
      'email': 'carlos@email.com',
      'telefono': '600345678',
      'direccion': 'Plaza España 10, Valencia',
    });

    await db.insert('articulos', {
      'id': 101,
      'codigo': 'ART001',
      'nombre': 'Portátil HP',
      'descripcion': 'Portátil HP 15.6"',
      'precio': 599.99,
      'stock': 15,
    });

    await db.insert('articulos', {
      'id': 102,
      'codigo': 'ART002',
      'nombre': 'Ratón Logitech',
      'descripcion': 'Ratón inalámbrico',
      'precio': 29.99,
      'stock': 50,
    });

    await db.insert('articulos', {
      'id': 103,
      'codigo': 'ART003',
      'nombre': 'Teclado Mecánico',
      'descripcion': 'Teclado RGB',
      'precio': 89.99,
      'stock': 30,
    });

    await db.insert('articulos', {
      'id': 104,
      'codigo': 'ART004',
      'nombre': 'Monitor LG 24"',
      'descripcion': 'Monitor Full HD',
      'precio': 179.99,
      'stock': 20,
    });

    await db.insert('articulos', {
      'id': 105,
      'codigo': 'ART005',
      'nombre': 'Webcam HD',
      'descripcion': 'Webcam 1080p',
      'precio': 49.99,
      'stock': 40,
    });
  }
}
