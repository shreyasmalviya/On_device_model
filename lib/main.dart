import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'screens/chat_screen.dart';
import 'services/llm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flutter gemma native side
  await FlutterGemma.initialize();

  runApp(const GemmaChatApp());
}

class GemmaChatApp extends StatefulWidget {
  const GemmaChatApp({super.key});

  @override
  State<GemmaChatApp> createState() => _GemmaChatAppState();
}

class _GemmaChatAppState extends State<GemmaChatApp> {
  final LlmService _llmService = LlmService();

  @override
  void dispose() {
    _llmService.offloadModel();
    _llmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Local Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: ChatScreen(llmService: _llmService),
    );
  }
}
