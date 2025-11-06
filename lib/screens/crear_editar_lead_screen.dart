import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../widgets/buscar_cliente_dialog.dart';

class CrearEditarLeadScreen extends StatefulWidget {
  final Map<String, dynamic>? lead; // null = crear nuevo, con datos = editar

  const CrearEditarLeadScreen({super.key, this.lead});

  @override
  State<CrearEditarLeadScreen> createState() => _CrearEditarLeadScreenState();
}

class _CrearEditarLeadScreenState extends State<CrearEditarLeadScreen> {
  final _asuntoController = TextEditingController();
  final _descripcionController = TextEditingController();

  Map<String, dynamic>? _clienteSeleccionado;
  int? _comercialId;
  int? _campanaSeleccionada;
  int _estado = 1; // Por defecto "Sin Asignar"

  List<Map<String, dynamic>> _campanas = [];
  bool _isLoading = false;
  bool _guardando = false;

  final List<Map<String, dynamic>> _estados = [
    {'id': 1, 'nombre': 'Sin Asignar'},
    {'id': 2, 'nombre': 'Asignado'},
    {'id': 3, 'nombre': 'Finalizado'},
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');

    final db = DatabaseHelper.instance;
    final campanas = await db.obtenerCampanas();

    setState(() {
      _comercialId = comercialId;
      _campanas = campanas;
    });

    // Si estamos editando, cargar datos del lead
    if (widget.lead != null) {
      _asuntoController.text = widget.lead!['asunto'] ?? '';
      _descripcionController.text = widget.lead!['descripcion'] ?? '';
      _estado = int.tryParse(widget.lead!['estado']?.toString() ?? '1') ?? 1;
      _campanaSeleccionada = widget.lead!['campana_id'] == 0
          ? null
          : widget.lead!['campana_id'];

      // Cargar cliente si existe
      if (widget.lead!['cliente_id'] != null &&
          widget.lead!['cliente_id'] != 0) {
        final clientes = await db.obtenerClientes();
        _clienteSeleccionado = clientes.firstWhere(
          (c) => c['id'] == widget.lead!['cliente_id'],
          orElse: () => {
            'id': widget.lead!['cliente_id'],
            'nombre': 'Cliente no encontrado',
          },
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BuscarClienteDialog(),
    );

    if (cliente != null) {
      setState(() => _clienteSeleccionado = cliente);
    }
  }

  String _getNombreEstado(int estadoId) {
    return _estados.firstWhere(
      (e) => e['id'] == estadoId,
      orElse: () => {'nombre': 'Desconocido'},
    )['nombre'];
  }

  Future<void> _guardarLead() async {
    if (_guardando) return;

    if (_asuntoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El asunto es obligatorio')));
      return;
    }

    if (_comercialId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay comercial asignado')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      final leadData = {
        'asunto': _asuntoController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'comercial_id': _comercialId,
        'estado': _estado.toString(),
        'cliente_id': _clienteSeleccionado?['id'] ?? 0,
        'campana_id': _campanaSeleccionada ?? 0,
      };

      Map<String, dynamic> resultado;

      if (widget.lead == null) {
        // Crear nuevo lead
        resultado = await apiService.crearLead(leadData);

        // Guardar en BD local
        await db.database.then((database) {
          return database.insert('leads', {
            'id': resultado['id'],
            'nombre': '',
            'fecha_alta': DateTime.now().toIso8601String(),
            'campana_id': leadData['campana_id'],
            'cliente_id': leadData['cliente_id'],
            'asunto': leadData['asunto'],
            'descripcion': leadData['descripcion'],
            'comercial_id': leadData['comercial_id'],
            'estado': leadData['estado'],
            'fecha': DateTime.now().toIso8601String(),
            'enviado': 0,
            'agendado': 0,
            'agenda_id': 0,
          });
        });
      } else {
        // Actualizar lead existente
        final leadId = widget.lead!['id'].toString();
        resultado = await apiService.actualizarLead(leadId, leadData);

        // Actualizar en BD local
        await db.database.then((database) {
          return database.update(
            'leads',
            {
              'asunto': leadData['asunto'],
              'descripcion': leadData['descripcion'],
              'estado': leadData['estado'],
              'cliente_id': leadData['cliente_id'],
              'campana_id': leadData['campana_id'],
            },
            where: 'id = ?',
            whereArgs: [widget.lead!['id']],
          );
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.lead == null
                ? '✅ Lead creado correctamente'
                : '✅ Lead actualizado correctamente',
          ),
          backgroundColor: const Color(0xFF032458),
        ),
      );

      Navigator.pop(context, true); // Devolver true para recargar la lista
    } catch (e) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lead == null ? 'Crear Lead' : 'Editar Lead'),
        backgroundColor: const Color(0xFF162846),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                TextField(
                  controller: _asuntoController,
                  decoration: const InputDecoration(
                    labelText: 'Asunto *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(
                      _clienteSeleccionado?['nombre'] ??
                          'Seleccionar cliente (opcional)',
                      style: TextStyle(
                        fontWeight: _clienteSeleccionado != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: _clienteSeleccionado != null
                        ? Text('ID: ${_clienteSeleccionado!['id']}')
                        : null,
                    leading: const Icon(Icons.business),
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _estado,
                  decoration: const InputDecoration(
                    labelText: 'Estado *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: _estados.map((estado) {
                    return DropdownMenuItem<int>(
                      value: estado['id'],
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: estado['id'] == 1
                                  ? Colors.blue
                                  : estado['id'] == 2
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                          Text(estado['nombre']),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _estado = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _campanaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Campaña (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.campaign),
                  ),
                  isExpanded: true,
                  menuMaxHeight: 300,
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin campaña'),
                    ),
                    ..._campanas.map((campana) {
                      return DropdownMenuItem<int>(
                        value: campana['id'],
                        child: Text(
                          campana['nombre'],
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() => _campanaSeleccionada = value);
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarLead,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.lead == null ? 'Crear Lead' : 'Guardar Cambios',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '* Campos obligatorios',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }
}
