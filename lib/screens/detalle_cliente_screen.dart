import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database_helper.dart';

class DetalleClienteScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const DetalleClienteScreen({super.key, required this.cliente});

  @override
  State<DetalleClienteScreen> createState() => _DetalleClienteScreenState();
}

class _DetalleClienteScreenState extends State<DetalleClienteScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 🟢 AHORA SON 5 PESTAÑAS
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _lanzarAccion(String tipo, String valor) async {
    Uri? uri;
    if (valor.isEmpty) return;

    if (tipo == 'tel') {
      uri = Uri.parse('tel:$valor');
    } else if (tipo == 'email') {
      uri = Uri.parse('mailto:$valor');
    } else if (tipo == 'map') {
      // Intenta abrir Google Maps con la dirección
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(valor)}');
    }

    try {
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      print('Error lanzando acción: $e');
    }
  }

  // 🟢 1. WIDGET GENERADOR DE LISTA DE CONTACTOS (Filtrado)
  Widget _buildListaContactosFiltrada(
    List<String> tiposPermitidos,
    IconData iconoPorDefecto,
  ) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.obtenerContactosPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final todosContactos = snapshot.data ?? [];

        // 🟢 Filtramos en memoria según lo que pida la pestaña ('T' o 'E')
        final contactosFiltrados = todosContactos.where((c) {
          final tipo = c['tipo'] ?? '';
          return tiposPermitidos.contains(tipo);
        }).toList();

        if (contactosFiltrados.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconoPorDefecto, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No hay registros de este tipo',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: contactosFiltrados.length,
          separatorBuilder: (ctx, i) => const Divider(),
          itemBuilder: (context, index) {
            final c = contactosFiltrados[index];
            final tipoReal = c['tipo']; // T, E, F...

            IconData icon = iconoPorDefecto;
            if (tipoReal == 'F') icon = Icons.fax; // Icono específico si es Fax

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF032458).withOpacity(0.1),
                child: Icon(icon, color: const Color(0xFF032458), size: 20),
              ),
              title: Text(
                c['valor'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(c['nombre'] ?? ''),
              trailing: c['es_principal'] == 1
                  ? const Chip(
                      label: Text(
                        'Principal',
                        style: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
              onTap: () {
                // Detectar acción según tipo
                if (tiposPermitidos.contains('E')) {
                  _lanzarAccion('email', c['valor']);
                } else {
                  _lanzarAccion('tel', c['valor']);
                }
              },
            );
          },
        );
      },
    );
  }

  // 🟢 2. WIDGET LISTA DIRECCIONES
  Widget _buildListaDirecciones() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.obtenerDireccionesPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final direcciones = snapshot.data ?? [];

        if (direcciones.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('No hay direcciones adicionales'),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: direcciones.length,
          separatorBuilder: (ctx, i) => const Divider(),
          itemBuilder: (context, index) {
            final d = direcciones[index];
            return ListTile(
              leading: const Icon(
                Icons.place,
                color: Colors.redAccent,
                size: 30,
              ),
              title: Text(d['direccion'] ?? 'Dirección sin nombre'),
              subtitle: Text('ID Ref: ${d['id']}'),
              trailing: const Icon(Icons.map, color: Colors.grey),
              onTap: () => _lanzarAccion('map', d['direccion']),
            );
          },
        );
      },
    );
  }

  // 🟢 3. WIDGET DATOS GENERALES
  Widget _buildDatosGenerales() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF032458), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.person, size: 60, color: Color(0xFF032458)),
          ),
          const SizedBox(height: 20),
          Text(
            widget.cliente['nombre'] ?? '',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF032458),
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.cliente['nom_com'] != null &&
              widget.cliente['nom_com'] != '')
            Text(
              widget.cliente['nom_com'],
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 30),
          const Divider(),
          _buildFilaDato(
            'NOMBRE COMERCIAL',
            widget.cliente['nom_com'] ?? '',
            // icon: Icons.business,
          ),
          const Divider(),
          _buildFilaDato(
            'NOMBRE FISCAL',
            widget.cliente['nom_fis'] ?? '',
            // icon: Icons.business,
          ),
          const Divider(),
          _buildFilaDato(
            'NIF',
            widget.cliente['cif'] ?? '',
            //  icon: Icons.badge,
          ),

          /*  const Divider(),
          // Mostramos los datos principales de la ficha (los que salen en la lista)
          _buildFilaDato(
            'TEL. PRINCIPAL',
            widget.cliente['telefono'] ?? '',
            icon: Icons.phone_android,
            isLink: true,
            tipo: 'tel',
          ),
          const Divider(),
          _buildFilaDato(
            'EMAIL PRINCIPAL',
            widget.cliente['email'] ?? '',
            icon: Icons.alternate_email,
            isLink: true,
            tipo: 'email',
          ),
          const Divider(),
          _buildFilaDato(
            'DIR. PRINCIPAL',
            widget.cliente['direccion'] ?? '',
            icon: Icons.home,
            isLink: true,
            tipo: 'map',
          ),*/
        ],
      ),
    );
  }

  Widget _buildFilaDato(
    String etiqueta,
    String valor, {
    IconData? icon,
    bool isLink = false,
    String? tipo,
  }) {
    if (valor.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: isLink ? () => _lanzarAccion(tipo!, valor) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: const Color(0xFF032458)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: 16,
                      color: isLink ? Colors.blue[800] : Colors.black87,
                      decoration: isLink ? TextDecoration.underline : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha Cliente'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable:
              true, // 🟢 IMPORTANTE: Permite scroll porque son muchas pestañas
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'DATOS', icon: Icon(Icons.info_outline)),
            Tab(text: 'TELÉFONOS', icon: Icon(Icons.phone)),
            Tab(text: 'EMAILS', icon: Icon(Icons.email)),
            Tab(text: 'DIRECCIONES', icon: Icon(Icons.location_on)),
            Tab(text: 'TARIFAS', icon: Icon(Icons.price_check)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Datos Generales
          _buildDatosGenerales(),

          // 2. Teléfonos (Incluimos 'T' y 'F' de Fax por si acaso)
          _buildListaContactosFiltrada(['T', 'F'], Icons.phone),

          // 3. Emails (Solo 'E')
          _buildListaContactosFiltrada(['E'], Icons.email),

          // 4. Direcciones
          _buildListaDirecciones(),

          // 5. Tarifas (Tu código existente)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.obtenerTarifasPorCliente(
              widget.cliente['id'],
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tarifas = snapshot.data ?? [];
              if (tarifas.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.money_off, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Sin tarifas especiales'),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tarifas.length,
                separatorBuilder: (ctx, i) => const Divider(),
                itemBuilder: (context, index) {
                  final tarifa = tarifas[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.local_offer,
                      color: Color(0xFF032458),
                    ),
                    title: Text(
                      tarifa['nombre_articulo'] ?? 'Artículo desconocido',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Código: ${tarifa['codigo_articulo']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${tarifa['precio']}€',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        if ((tarifa['por_descuento'] ?? 0) > 0)
                          Text(
                            '-${tarifa['por_descuento']}% dto',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
