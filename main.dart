import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const ScaraPcApp());
}

class ScaraPcApp extends StatelessWidget {
  const ScaraPcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SCARAPC Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Color(0xFF4DA6FF)),
      ),
      home: const SyncHomePage(),
    );
  }
}

class SyncHomePage extends StatefulWidget {
  const SyncHomePage({super.key});

  @override
  State<SyncHomePage> createState() => _SyncHomePageState();
}

class _SyncHomePageState extends State<SyncHomePage> {
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.1.10:5000');

  bool _sincronizando = false;
  String _status = 'Pronto para sincronizar.';
  String _arquivoAtual = '';
  int _totalEncontrados = 0;
  int _enviados = 0;
  int _pulados = 0;
  int _erros = 0;

  final List<String> _pastasAlvo = [
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Pictures',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Movies',
  ];

  Future<bool> _pedirPermissao() async {
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<Set<String>> _buscarArquivosNoPC(String baseUrl) async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/existentes'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final List<dynamic> lista = jsonDecode(resp.body)['arquivos'];
        return lista.map((e) => e.toString().toLowerCase()).toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<List<File>> _varrerCelular() async {
    final List<File> arquivos = [];
    for (final caminho in _pastasAlvo) {
      final dir = Directory(caminho);
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final nome = entity.path.split('/').last;
            if (!nome.startsWith('.') && !entity.path.contains('.thumbnails')) {
              arquivos.add(entity);
            }
          }
        }
      }
    }
    return arquivos;
  }

  Future<void> _iniciarSincronizacao() async {
    final ipTexto = _ipController.text.trim();
    if (ipTexto.isEmpty) return;

    final baseUrl = ipTexto.startsWith('http') ? ipTexto : 'http://$ipTexto';

    setState(() {
      _sincronizando = true;
      _status = 'Verificando permissões...';
      _arquivoAtual = '';
      _totalEncontrados = 0;
      _enviados = 0;
      _pulados = 0;
      _erros = 0;
    });

    final permitido = await _pedirPermissao();
    if (!permitido) {
      setState(() {
        _sincronizando = false;
        _status = 'Permissão negada. Ative "Acesso a todos os arquivos".';
      });
      return;
    }

    setState(() => _status = 'Conectando ao PC e checando duplicatas...');
    final existentesNoPC = await _buscarArquivosNoPC(baseUrl);

    setState(() => _status = 'Varrendo pastas do celular...');
    final arquivos = await _varrerCelular();

    setState(() {
      _totalEncontrados = arquivos.length;
      _status = 'Enviando arquivos para o PC...';
    });

    for (final arquivo in arquivos) {
      final nome = arquivo.path.split('/').last;

      if (existentesNoPC.contains(nome.toLowerCase())) {
        setState(() => _pulados++);
        continue;
      }

      setState(() => _arquivoAtual = nome);

      try {
        final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
        req.files.add(await http.MultipartFile.fromPath('arquivos', arquivo.path));
        final streamed = await req.send();

        if (streamed.statusCode == 200) {
          setState(() => _enviados++);
        } else {
          setState(() => _erros++);
        }
      } catch (_) {
        setState(() => _erros++);
      }
    }

    setState(() {
      _sincronizando = false;
      _arquivoAtual = '';
      _status = 'Sincronização concluída!';
    });
  }

  @override
  Widget build(BuildContext context) {
    final processados = _enviados + _pulados + _erros;
    final progresso =
        _totalEncontrados > 0 ? processados / _totalEncontrados : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('SCARAPC Sync'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Endereço do servidor no PC (IP:Porta):'),
            const SizedBox(height: 8),
            TextField(
              controller: _ipController,
              enabled: !_sincronizando,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex: 192.168.1.10:5000',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _sincronizando ? null : _iniciarSincronizacao,
              icon: const Icon(Icons.sync),
              label: Text(
                _sincronizando ? 'Sincronizando...' : 'SINCRONIZAR AGORA',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_arquivoAtual.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Enviando: $_arquivoAtual',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            if (_totalEncontrados > 0) ...[
              LinearProgressIndicator(value: progresso, minHeight: 10),
              const SizedBox(height: 12),
              Text(
                'Encontrados: $_totalEncontrados  |  Enviados: $_enviados  |  Já no PC: $_pulados  |  Erros: $_erros',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
