import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;
import 'screens/debug_logs_screen.dart';

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
      version: 6, // 🟢 VERSIÓN INCREMENTADA A 6
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
    name TEXT NOT NULL,
    ent INTEGER
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
        no_gen_pro_vis INTEGER DEFAULT 0, 
        no_gen_tri INTEGER DEFAULT 0,     
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
        numero TEXT, 
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
        por_descuento REAL DEFAULT 0,
        por_iva REAL DEFAULT 0,
        tipo_iva TEXT DEFAULT 'G',
        FOREIGN KEY (pedido_id) REFERENCES pedidos (id),
        FOREIGN KEY (articulo_id) REFERENCES articulos (id)
      )
    ''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS presupuestos (
    id INTEGER PRIMARY KEY,
    cliente_id INTEGER NOT NULL,
    comercial_id INTEGER,
    usuario_id INTEGER,
    fecha TEXT NOT NULL,
    numero TEXT,
    estado TEXT,
    observaciones TEXT,
    total REAL,
    base_total REAL,
    iva_total REAL,
    fecha_validez TEXT,
    fecha_aceptacion TEXT,
    sincronizado INTEGER DEFAULT 0,
    FOREIGN KEY (cliente_id) REFERENCES clientes (id),
    FOREIGN KEY (comercial_id) REFERENCES comerciales (id)
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS lineas_presupuesto (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    presupuesto_id INTEGER NOT NULL,
    articulo_id INTEGER NOT NULL,
    cantidad REAL NOT NULL,
    precio REAL NOT NULL,
    por_descuento REAL DEFAULT 0,
    por_iva REAL DEFAULT 0,
    tipo_iva TEXT DEFAULT 'G',
    FOREIGN KEY (presupuesto_id) REFERENCES presupuestos (id),
    FOREIGN KEY (articulo_id) REFERENCES articulos (id)
  )
''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tarifas_cliente (
        id INTEGER PRIMARY KEY,
        cliente_id INTEGER NOT NULL,
        articulo_id INTEGER NOT NULL,
        precio REAL NOT NULL,
        por_descuento REAL DEFAULT 0,
        FOREIGN KEY (cliente_id) REFERENCES clientes (id),
        FOREIGN KEY (articulo_id) REFERENCES articulos (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tarifas_articulo (
        id INTEGER PRIMARY KEY,
        articulo_id INTEGER NOT NULL,
        precio REAL NOT NULL,
        por_descuento REAL DEFAULT 0,
        FOREIGN KEY (articulo_id) REFERENCES articulos (id)
      )
    ''');
    await db.execute('''
  CREATE TABLE config_local (
    clave TEXT PRIMARY KEY,
    valor TEXT
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

  Future<void> guardarContrasenaLocal(String contrasena) async {
    final db = await database;
    await db.insert('config_local', {
      'clave': 'contrasena_local',
      'valor': contrasena,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Obtener contraseña local
  Future<String?> obtenerContrasenaLocal() async {
    final db = await database;
    final resultado = await db.query(
      'config_local',
      where: 'clave = ?',
      whereArgs: ['contrasena_local'],
    );

    return resultado.isNotEmpty ? resultado.first['valor'] as String? : null;
  }

  Future<bool> existeContrasenaLocal() async {
    final contrasena = await obtenerContrasenaLocal();
    return contrasena != null && contrasena.isNotEmpty;
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

  Future<int> insertarPresupuesto(Map<String, dynamic> presupuesto) async {
    final db = await database;
    return await db.insert(
      'presupuestos',
      presupuesto,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertarLineaPresupuesto(Map<String, dynamic> linea) async {
    final db = await database;
    return await db.insert('lineas_presupuesto', linea);
  }

  Future<List<Map<String, dynamic>>> obtenerPresupuestos() async {
    final db = await database;
    return await db.query('presupuestos', orderBy: 'fecha DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerLineasPresupuesto(
    int presupuestoId,
  ) async {
    final db = await database;
    return await db.query(
      'lineas_presupuesto',
      where: 'presupuesto_id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<void> insertarPresupuestosLote(
    List<Map<String, dynamic>> presupuestos,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var presupuesto in presupuestos) {
      batch.insert(
        'presupuestos',
        presupuesto,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> limpiarPresupuestos() async {
    final db = await database;
    // 1. Borrar primero las líneas (dependencia)
    await db.delete('lineas_presupuesto');
    // 2. Borrar después los presupuestos (principal)
    await db.delete('presupuestos');
  }

  Future<int> actualizarPresupuestoSincronizado(
    int presupuestoId,
    int sincronizado,
  ) async {
    final db = await database;
    return await db.update(
      'presupuestos',
      {'sincronizado': sincronizado},
      where: 'id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<void> insertarUsuariosLote(List<Map<String, dynamic>> usuarios) async {
    final db = await database;
    final batch = db.batch();

    for (var usuario in usuarios) {
      batch.insert('usuarios', {
        'id': usuario['id'],
        'name': usuario['name'],
        'ent': usuario['ent'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
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

    // 🟢 INICIO DE NUEVA LÓGICA DE UPGRADE
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE agenda ADD COLUMN no_gen_pro_vis INTEGER DEFAULT 0',
        );
        print('✅ Columna no_gen_pro_vis agregada a agenda');
      } catch (e) {
        print('⚠️ Columna no_gen_pro_vis ya existe en agenda: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE agenda ADD COLUMN no_gen_tri INTEGER DEFAULT 0',
        );
        print('✅ Columna no_gen_tri agregada a agenda');
      } catch (e) {
        print('⚠️ Columna no_gen_tri ya existe en agenda: $e');
      }

      // También asegurarse de que la tabla 'agenda' recreada en < 3
      // tenga los campos si la versión 4 se saltó.
      // (Esta es una salvaguarda)
      try {
        await db.execute('DROP TABLE IF EXISTS agenda_temp_migration');
        await db.execute('ALTER TABLE agenda RENAME TO agenda_temp_migration');

        // Crear la tabla final con todas las columnas
        await _createDB(db, 5);

        // Copiar datos antiguos
        await db.execute('''
          INSERT INTO agenda(
            id, nombre, cliente_id, tipo_visita, asunto, comercial_id, campana_id,
            fecha_inicio, hora_inicio, fecha_fin, hora_fin, 
            fecha_proxima_visita, hora_proxima_visita,
            descripcion, todo_dia, lead_id, presupuesto_id, generado, sincronizado
          )
          SELECT 
            id, nombre, cliente_id, tipo_visita, asunto, comercial_id, campana_id,
            fecha_inicio, hora_inicio, fecha_fin, hora_fin, 
            fecha_proxima_visita, hora_proxima_visita,
            descripcion, todo_dia, lead_id, presupuesto_id, generado, sincronizado
          FROM agenda_temp_migration
        ''');
        await db.execute('DROP TABLE agenda_temp_migration');
        print('✅ Tabla agenda migrada forzosamente a v5');
      } catch (e) {
        print(
          '⚠️ Error en migración forzosa v5 (puede ser normal si no fue necesaria): $e',
        );
        // Si falla la migración forzosa, volver a crear la tabla original
        // e intentar añadir las columnas de nuevo.
        try {
          await db.execute('DROP TABLE IF EXISTS agenda_temp_migration');
          await _createDB(db, 5); // Re-crear todo si falla
        } catch (e2) {
          print('❌ Error fatal en migración v5: $e2');
        }
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE pedidos ADD COLUMN numero TEXT');
        print('✅ Columna numero agregada a pedidos');
      } catch (e) {
        print('⚠️ Columna numero ya existe en pedidos: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE lineas_pedido ADD COLUMN por_descuento REAL DEFAULT 0',
        );
        print('✅ Columna por_descuento agregada a lineas_pedido');
      } catch (e) {
        print('⚠️ Columna por_descuento ya existe en lineas_pedido: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE lineas_pedido ADD COLUMN por_iva REAL DEFAULT 0',
        );
        print('✅ Columna por_iva agregada a lineas_pedido');
      } catch (e) {
        print('⚠️ Columna por_iva ya existe en lineas_pedido: $e');
      }
    }
    // 🟢 FIN DE NUEVA LÓGICA DE UPGRADE
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

  // Tabla usuarios

  // Obtener comercial por ID
  Future<Map<String, dynamic>?> obtenerComercialPorId(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> resultado = await db.query(
      'comerciales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return resultado.isNotEmpty ? resultado.first : null;
  }

  Future<Map<String, dynamic>?> obtenerUsuarioPorComercial(
    int comercialId,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> resultado = await db.query(
      'usuarios',
      where: 'ent = ?',
      whereArgs: [comercialId],
      limit: 1,
    );

    return resultado.isNotEmpty ? resultado.first : null;
  }
  // ========== AGENDA ==========

  Future<void> insertarAgendasLote(List<Map<String, dynamic>> agendas) async {
    final db = await database;
    final batch = db.batch();

    DebugLogger.log('💾 Insertando ${agendas.length} agendas en BD local...');

    for (var agenda in agendas) {
      DebugLogger.log(
        '💾 BD: Agenda #${agenda['id']} - hora_inicio: "${agenda['hora_inicio']}"',
      );
      batch.insert(
        'agenda',
        agenda,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    DebugLogger.log('✅ ${agendas.length} agendas insertadas en BD');
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

  Future<int> eliminarVisita(int id) async {
    final db = await database;
    DebugLogger.log('🗑️ DB: Eliminando visita local #$id');
    return await db.delete('agenda', where: 'id = ?', whereArgs: [id]);
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
        where:
            '(nombre LIKE ? OR codigo LIKE ? OR id LIKE ?) AND nombre IS NOT NULL AND nombre != ""',
        whereArgs: ['%$busqueda%', '%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query(
      'articulos',
      where: 'nombre IS NOT NULL AND nombre != ""',
      orderBy: 'nombre',
    );
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

  Future<void> insertarPedidosLote(List<Map<String, dynamic>> pedidos) async {
    final db = await database;
    final batch = db.batch();

    for (var pedido in pedidos) {
      batch.insert(
        'pedidos',
        pedido,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }
  // [DENTRO DE database_helper.dart, en la clase DatabaseHelper]

  Future<void> insertarLineasPedidoLote(
    List<Map<String, dynamic>> lineas,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var linea in lineas) {
      batch.insert(
        'lineas_pedido',
        linea,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> insertarLineasPresupuestoLote(
    List<Map<String, dynamic>> lineas,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var linea in lineas) {
      batch.insert(
        'lineas_presupuesto',
        linea,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Actualizar pedido
  Future<int> actualizarPedido(int pedidoId, Map<String, dynamic> datos) async {
    final db = await database;
    return await db.update(
      'pedidos',
      datos,
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
  }

  // Eliminar líneas de pedido
  Future<int> eliminarLineasPedido(int pedidoId) async {
    final db = await database;
    return await db.delete(
      'lineas_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
    );
  }

  // Actualizar presupuesto
  Future<int> actualizarPresupuesto(
    int presupuestoId,
    Map<String, dynamic> datos,
  ) async {
    final db = await database;
    return await db.update(
      'presupuestos',
      datos,
      where: 'id = ?',
      whereArgs: [presupuestoId],
    );
  }

  // Eliminar líneas de presupuesto
  Future<int> eliminarLineasPresupuesto(int presupuestoId) async {
    final db = await database;
    return await db.delete(
      'lineas_presupuesto',
      where: 'presupuesto_id = ?',
      whereArgs: [presupuestoId],
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

  Future<void> limpiarPedidos() async {
    final db = await database;
    // 1. Borrar primero las líneas (dependencia)
    await db.delete('lineas_pedido');
    // 2. Borrar después los pedidos (principal)
    await db.delete('pedidos');
  }

  Future<void> insertarTarifasClienteLote(
    List<Map<String, dynamic>> tarifas,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var tarifa in tarifas) {
      batch.insert(
        'tarifas_cliente',
        tarifa,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> insertarTarifasArticuloLote(
    List<Map<String, dynamic>> tarifas,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var tarifa in tarifas) {
      batch.insert(
        'tarifas_articulo',
        tarifa,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> limpiarTarifasCliente() async {
    final db = await database;
    await db.delete('tarifas_cliente');
  }

  Future<void> limpiarTarifasArticulo() async {
    final db = await database;
    await db.delete('tarifas_articulo');
  }

  Future<Map<String, dynamic>?> obtenerTarifaCliente(
    int clienteId,
    int articuloId,
  ) async {
    final db = await database;
    final result = await db.query(
      'tarifas_cliente',
      where: 'cliente_id = ? AND articulo_id = ?',
      whereArgs: [clienteId, articuloId],
    );

    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<Map<String, dynamic>?> obtenerTarifaArticulo(int articuloId) async {
    final db = await database;
    final result = await db.query(
      'tarifas_articulo',
      where: 'articulo_id = ?',
      whereArgs: [articuloId],
    );

    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Función para obtener precio y descuento según la jerarquía
  Future<Map<String, double>> obtenerPrecioYDescuento(
    int clienteId,
    int articuloId,
    double pvpBase,
  ) async {
    // 1. Buscar en tarifas por cliente
    final tarifaCliente = await obtenerTarifaCliente(clienteId, articuloId);
    if (tarifaCliente != null) {
      return {
        'precio': tarifaCliente['precio'] as double,
        'descuento': tarifaCliente['por_descuento'] as double,
      };
    }

    // 2. Buscar en tarifas por artículo
    final tarifaArticulo = await obtenerTarifaArticulo(articuloId);
    if (tarifaArticulo != null) {
      return {
        'precio': tarifaArticulo['precio'] as double,
        'descuento': tarifaArticulo['por_descuento'] as double,
      };
    }

    // 3. Usar PVP del artículo sin descuento
    return {'precio': pvpBase, 'descuento': 0.0};
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
