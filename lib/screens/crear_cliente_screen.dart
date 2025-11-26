import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

class CrearClienteScreen extends StatefulWidget {
  const CrearClienteScreen({super.key});

  @override
  State<CrearClienteScreen> createState() => _CrearClienteScreenState();
}

class _CrearClienteScreenState extends State<CrearClienteScreen>
    with SingleTickerProviderStateMixin {
  // Controladores Datos Principales
  final _nombreFiscalController = TextEditingController();
  final _nombreComercialController = TextEditingController();
  final _cifController = TextEditingController();

  // Controladores Ficha Principal
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _direccionController = TextEditingController();

  // 🟢 Listas Separadas
  final List<Map<String, String>> _listaTelefonos = [];
  final List<Map<String, String>> _listaEmails = [];
  final List<Map<String, String>> _listaDirecciones = [];

  late TabController _tabController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 🟢 AHORA SON 4 PESTAÑAS
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _nombreFiscalController.dispose();
    _nombreComercialController.dispose();
    _cifController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _direccionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- DIÁLOGO: AÑADIR TELÉFONO ---
  void _dialogAddTelefono() {
    String valor = '';
    String desc = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir Teléfono'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Número',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
              onChanged: (v) => valor = v,
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Descripción (Ej. Móvil, Trabajo)',
              ),
              onChanged: (v) => desc = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (valor.isNotEmpty) {
                setState(() {
                  _listaTelefonos.add({'valor': valor, 'descripcion': desc});
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGO: AÑADIR EMAIL ---
  void _dialogAddEmail() {
    String valor = '';
    String desc = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => valor = v,
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Descripción (Ej. Facturación)',
              ),
              onChanged: (v) => desc = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (valor.isNotEmpty) {
                setState(() {
                  _listaEmails.add({'valor': valor, 'descripcion': desc});
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGO: AÑADIR DIRECCIÓN (MEJORADO) ---
  void _dialogAddDireccion() {
    String calle = '';
    String cp = '';
    String poblacion = '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir Dirección'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Dirección / Calle *',
                ),
                maxLines: 2,
                onChanged: (v) => calle = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'C.P.'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => cp = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Población'),
                      onChanged: (v) => poblacion = v,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (calle.isNotEmpty) {
                setState(() {
                  _listaDirecciones.add({
                    'direccion': calle,
                    'cp': cp,
                    'poblacion': poblacion,
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  // --- GUARDAR TODO ---
  Future<void> _guardarCliente() async {
    if (_nombreFiscalController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El Nombre Fiscal es obligatorio')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url') ?? '';
      final apiKey = prefs.getString('velneo_api_key') ?? '';
      final comercialId = prefs.getInt('comercial_id');

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      // 1. Crear Cliente (Ficha base)
      final nuevoId = await apiService.crearCliente({
        'nombre': _nombreFiscalController.text,
        'nombre_comercial': _nombreComercialController.text,
        'cif': _cifController.text,
        'telefono': _telefonoController.text,
        'email': _emailController.text,
        'direccion': _direccionController.text,
        'comercial_id': comercialId,
      });

      print('✅ Cliente creado con ID: $nuevoId');

      // 2. Enviar Teléfonos
      for (var t in _listaTelefonos) {
        await apiService.crearContacto({
          'cliente_id': nuevoId,
          'tipo': 'T',
          'valor': t['valor'],
          'nombre': t['descripcion'],
          'es_principal': 0,
        });
      }

      // 3. Enviar Emails
      for (var e in _listaEmails) {
        await apiService.crearContacto({
          'cliente_id': nuevoId,
          'tipo': 'E',
          'valor': e['valor'],
          'nombre': e['descripcion'],
          'es_principal': 0,
        });
      }

      for (var d in _listaDirecciones) {
        await apiService.crearDireccion({
          'cliente_id': nuevoId,
          'direccion': d['direccion'],
          'cp': d['cp'],
          'poblacion': d['poblacion'],
          'comercial_id': comercialId,
        });
      }
      // ...
      await db.insertarCliente({
        'id': nuevoId,
        'nombre': _nombreFiscalController.text,
        'nom_fis': _nombreFiscalController.text,
        'nom_com': _nombreComercialController.text,
        'cif': _cifController.text,
        'telefono': _telefonoController.text,
        'email': _emailController.text,
        'direccion': _direccionController.text,
        'cmr': comercialId,
      });

      // Contactos locales (unificamos listas para la tabla 'contactos')
      final todosContactos = [
        ..._listaTelefonos.map((t) => {'tipo': 'T', ...t}),
        ..._listaEmails.map((e) => {'tipo': 'E', ...e}),
      ];

      for (var c in todosContactos) {
        await db.insertarContacto({
          'cliente_id': nuevoId,
          'tipo': c['tipo'],
          'nombre': c['descripcion'],
          'valor': c['valor'],
          'es_principal': 0,
        });
      }

      // Direcciones locales
      for (var d in _listaDirecciones) {
        String dirCompleta = d['direccion']!;
        if (d['cp']!.isNotEmpty) dirCompleta += ", ${d['cp']!}";
        if (d['poblacion']!.isNotEmpty) dirCompleta += " ${d['poblacion']!}";

        await db.insertarDireccion({
          'ent': nuevoId,
          'direccion': dirCompleta, // En local guardamos string completo
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Volver con éxito
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado correctamente')),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Cliente'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true, // Permitir scroll si no caben
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'DATOS'),
            Tab(text: 'TELÉFONOS'),
            Tab(text: 'EMAILS'),
            Tab(text: 'DIRECCIONES'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _guardarCliente,
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. DATOS GENERALES
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _nombreFiscalController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Fiscal *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nombreComercialController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Comercial',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cifController,
                      decoration: const InputDecoration(
                        labelText: 'CIF / NIF',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

                // 2. TELÉFONOS
                Scaffold(
                  floatingActionButton: FloatingActionButton(
                    onPressed: _dialogAddTelefono,
                    backgroundColor: const Color(0xFF032458),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  body: _listaTelefonos.isEmpty
                      ? const Center(child: Text('Sin teléfonos adicionales'))
                      : ListView.builder(
                          itemCount: _listaTelefonos.length,
                          itemBuilder: (ctx, i) => ListTile(
                            leading: const Icon(Icons.phone_android),
                            title: Text(_listaTelefonos[i]['valor']!),
                            subtitle: Text(_listaTelefonos[i]['descripcion']!),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  setState(() => _listaTelefonos.removeAt(i)),
                            ),
                          ),
                        ),
                ),

                // 3. EMAILS
                Scaffold(
                  floatingActionButton: FloatingActionButton(
                    onPressed: _dialogAddEmail,
                    backgroundColor: const Color(0xFF032458),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  body: _listaEmails.isEmpty
                      ? const Center(child: Text('Sin emails adicionales'))
                      : ListView.builder(
                          itemCount: _listaEmails.length,
                          itemBuilder: (ctx, i) => ListTile(
                            leading: const Icon(Icons.email),
                            title: Text(_listaEmails[i]['valor']!),
                            subtitle: Text(_listaEmails[i]['descripcion']!),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  setState(() => _listaEmails.removeAt(i)),
                            ),
                          ),
                        ),
                ),

                // 4. DIRECCIONES
                Scaffold(
                  floatingActionButton: FloatingActionButton(
                    onPressed: _dialogAddDireccion,
                    backgroundColor: const Color(0xFF032458),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  body: _listaDirecciones.isEmpty
                      ? const Center(child: Text('Sin direcciones adicionales'))
                      : ListView.builder(
                          itemCount: _listaDirecciones.length,
                          itemBuilder: (ctx, i) {
                            final d = _listaDirecciones[i];
                            return ListTile(
                              leading: const Icon(Icons.place),
                              title: Text(d['direccion']!),
                              subtitle: Text("${d['cp']} - ${d['poblacion']}"),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => setState(
                                  () => _listaDirecciones.removeAt(i),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
