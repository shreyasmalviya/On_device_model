import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

enum LlmStatus { unloaded, loading, loaded, error }

class LlmService extends ChangeNotifier {
  LlmStatus _status = LlmStatus.unloaded;
  LlmStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  InferenceModel? _model;
  InferenceChat? _chat;
  bool _supportsVision = false;

  /// Whether the loaded model supports image input (has SigLIP vision encoder)
  bool get supportsVision => _supportsVision;

  /// Loads the model from a local device path using the Modern API.
  /// Enables image support so multimodal models (1B+) can process images.
  Future<void> loadModel(String filePath) async {
    try {
      _status = LlmStatus.loading;
      _errorMessage = null;
      notifyListeners();

      if (!File(filePath).existsSync()) {
        throw Exception("Model file does not exist at path: $filePath");
      }

      // 1. Install the model from the file
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(filePath)
          .install();

      // 2. Load the active model into memory
      // Try with vision support first (works for 1B+ models with SigLIP encoder)
      // Falls back to text-only if model lacks TF_LITE_VISION_ENCODER (270M)
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: PreferredBackend.cpu,
          supportImage: true,
          maxNumImages: 1,
        );
        _supportsVision = true;
        debugPrint('✅ Model loaded WITH vision support');
      } catch (_) {
        // 270M and other text-only models don't have a vision encoder
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: PreferredBackend.cpu,
        );
        _supportsVision = false;
        debugPrint('ℹ️ Model loaded WITHOUT vision (text-only, no SigLIP encoder)');
      }

      // 3. Create a chat session matching Google AI Edge Gallery defaults
      _chat = await _model?.createChat(
         topK: 64,
         temperature: 1.0,
         topP: 0.95,
      );

      _status = LlmStatus.loaded;
      notifyListeners();
    } catch (e) {
      _status = LlmStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Unloads / frees up memory from the running model.
  Future<void> offloadModel() async {
    try {
       await _model?.close();
       _model = null;
       _chat = null;
       _status = LlmStatus.unloaded;
       notifyListeners();
    } catch (e) {
      debugPrint("Error offloading model: $e");
    }
  }

  /// Send text-only prompt to Gemma model locally and return async response.
  Future<String?> generateResponse(String prompt) async {
    if (_status != LlmStatus.loaded || _chat == null) return null;
    try {
      await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await _chat!.generateChatResponse();
      if (response is TextResponse) {
        return response.token;
      }
      return null;
    } catch (e) {
      debugPrint("Generation error: $e");
      return null;
    }
  }

  /// Send image + text prompt (multimodal) to the model.
  /// For 270M models: image will be ignored (no vision encoder), text-only response.
  /// For 1B+ models: image will be processed by SigLIP and included in inference.
  Future<String?> generateResponseWithImage(String prompt, Uint8List imageBytes) async {
    if (_status != LlmStatus.loaded || _chat == null) return null;
    try {
      // Gemma 3 requires the '<image>' token explicitly in the prompt!
      final visionPrompt = prompt.contains('<image>') ? prompt : '<image>\n$prompt';
      
      await _chat!.addQueryChunk(
        Message.withImage(
          text: visionPrompt,
          imageBytes: imageBytes,
          isUser: true,
        ),
      );
      final response = await _chat!.generateChatResponse();
      if (response is TextResponse) {
        return response.token;
      }
      return null;
    } catch (e) {
      debugPrint("Multimodal generation error: $e");
      return null;
    }
  }

  /// Stream prompt response.
  Stream<String>? generateResponseStream(String prompt) async* {
    if (_status != LlmStatus.loaded || _chat == null) return;
    await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));
    final stream = _chat!.generateChatResponseAsync();
    await for (final response in stream) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }
}
