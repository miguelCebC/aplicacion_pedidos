import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de Depuración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              final logs = DebugLogger.getLogs();
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copiados al portapapeles')),
              );
            },
            tooltip: 'Copiar logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                DebugLogger.clear();
              });
            },
            tooltip: 'Limpiar logs',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: DebugLogger.logs.length,
        itemBuilder: (context, index) {
          final log = DebugLogger.logs[index];
          Color color = Colors.black87;

          if (log.contains('❌') || log.contains('ERROR')) {
            color = Colors.red;
          } else if (log.contains('⚠️') || log.contains('WARNING')) {
            color = Colors.orange;
          } else if (log.contains('✅') || log.contains('SUCCESS')) {
            color = Colors.green;
          } else if (log.contains('📤') || log.contains('📥')) {
            color = Colors.blue;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              log,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {});
        },
        tooltip: 'Refrescar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class DebugLogger {
  static final List<String> logs = [];
  static const int maxLogs = 500;

  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';

    logs.add(logMessage);

    // Mantener solo los últimos maxLogs
    if (logs.length > maxLogs) {
      logs.removeAt(0);
    }

    // También imprimir en consola por si acaso
    print(logMessage);
  }

  static void clear() {
    logs.clear();
  }

  static List<String> getLogs() {
    return List.from(logs);
  }
}
