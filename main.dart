import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fllama/fllama.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const LocalLLMApp());
}

class LocalLLMApp extends StatelessWidget {
  const LocalLLMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prueva-1XLX LLM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFBB86FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _manualTrainController = TextEditingController();
  final List> _messages = [];
  String? _modelPath;
  String _knowledgeBase = "";
  bool _isGenerating = false;
  int _activeRequestId = -1;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _modelPath = prefs.getString('model_path');
      _knowledgeBase = prefs.getString('knowledge_base') ?? "";
      _messages.add({
        'sender': 'ai',
        'text': _modelPath != null
            ? 'Modelo cargado: ${_modelPath!.split('/').last}\nMemoria entrenada: ${_knowledgeBase.length} caracteres.'
            : 'Bienvenido a Prueva-1XLX LLM.\n\n1. Toca la carpeta arriba para cargar tu modelo .gguf.\n2. Toca el cerebro para entrenarlo con textos o archivos .txt.'
      });
    });
  }

  Future<void> _pickModelFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.gguf')) {
        _showSnack('Selecciona un archivo válido con extensión .gguf');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('model_path', path);
      setState(() {
        _modelPath = path;
        _messages.add({
          'sender': 'ai',
          'text': 'Modelo vinculado con éxito:\n${path.split('/').last}'
        });
      });
    }
  }

  void _openTrainDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Entrenar IA Local (Memoria RAG)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Capacidad usada: ${_knowledgeBase.length} / 6000 caracteres',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualTrainController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Escribe reglas, datos o conocimiento nuevo aquí...',
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _trainWithTextFile();
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir .TXT'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFBB86FC),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      final text = _manualTrainController.text.trim();
                      if (text.isNotEmpty) {
                        await _appendKnowledge(text);
                        _manualTrainController.clear();
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Texto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _trainWithTextFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'json', 'csv'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      String content = await file.readAsString();
      await _appendKnowledge(content);
    }
  }

  Future<void> _appendKnowledge(String newContent) async {
    String combined = "$_knowledgeBase\n$newContent".trim();
    if (combined.length > 6000) {
      combined = combined.substring(combined.length - 6000);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('knowledge_base', combined);
    setState(() {
      _knowledgeBase = combined;
      _messages.add({
        'sender': 'ai',
        'text': 'Conocimiento guardado (${_knowledgeBase.length} caracteres activos en memoria).'
      });
    });
  }

  Future<void> _clearTraining() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('knowledge_base');
    setState(() {
      _knowledgeBase = "";
    });
    _showSnack('Memoria de entrenamiento limpiada');
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    if (_modelPath == null) {
      _showSnack('Primero carga un modelo .gguf desde el ícono de carpeta');
      return;
    }

    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _messages.add({'sender': 'ai', 'text': ''});
      _isGenerating = true;
    });
    _msgController.clear();

    final systemPrompt = _knowledgeBase.isNotEmpty
        ? "Usa estrictamente este conocimiento entrenado como contexto principal para responder:\n$_knowledgeBase"
        : "Eres un asistente de IA eficiente ejecutándose 100% offline en Android.";

    final request = OpenAiRequest(
      maxTokens: 512,
      messages: [
        Message(Role.system, systemPrompt),
        Message(Role.user, text),
      ],
      numGpuLayers: 0,
      modelPath: _modelPath!,
      frequencyPenalty: 0.0,
      presencePenalty: 1.1,
      topP: 0.9,
      contextSize: 2048,
      temperature: 0.7,
      logger: (log) {},
    );

    _activeRequestId = fllamaChat(request, (response, responseJson, done) {
      setState(() {
        _messages.last['text'] = response;
        if (done) {
          _isGenerating = false;
        }
      });
    });
  }

  void _stopGeneration() {
    if (_isGenerating && _activeRequestId != -1) {
      fllamaCancelInference(_activeRequestId);
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueva-1XLX LLM', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'Entrenar modelo',
            onPressed: _openTrainDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Borrar memoria',
            onPressed: _clearTraining,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Cargar .gguf',
            onPressed: _pickModelFile,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF3700B3) : const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text'] ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Escribe tu mensaje...',
                      filled: true,
                      fillColor: const Color(0xFF2C2C2C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_isGenerating ? Icons.stop_circle : Icons.send),
                  color: const Color(0xFFBB86FC),
                  iconSize: 30,
                  onPressed: _isGenerating ? _stopGeneration : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
