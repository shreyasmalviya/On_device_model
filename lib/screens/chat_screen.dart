import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import '../services/llm_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends StatefulWidget {
  final LlmService llmService;

  const ChatScreen({super.key, required this.llmService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class ChatMessage {
  final String text;
  final bool isUser;
  final Uint8List? imageBytes;

  ChatMessage({required this.text, required this.isUser, this.imageBytes});
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isGenerating = false;
  Uint8List? _pendingImage;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickAndLoadModel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final String originalPath = result.files.single.path!;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Securing model inside application cache... Please wait.'),
          ),
        );

        final directory = await getApplicationDocumentsDirectory();
        final fileName = result.files.single.name;
        final localPath = '${directory.path}/$fileName';

        // Clean up any stale .litertlm files from previous attempts
        final staleFile = File(
          '${directory.path}/${fileName.replaceAll(RegExp(r'\.[^.]+$'), '.litertlm')}',
        );
        if (await staleFile.exists()) {
          await staleFile.delete();
        }

        final localFile = File(localPath);
        if (!await localFile.exists()) {
          await File(originalPath).copy(localPath);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading model into memory... This may take a while.'),
          ),
        );

        await widget.llmService.loadModel(localPath);

        if (!mounted) return;
        if (widget.llmService.status == LlmStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${widget.llmService.errorMessage}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Model loaded successfully!')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load model: $e')),
      );
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 896,
        maxHeight: 896,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pendingImage = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 896,
        maxHeight: 896,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pendingImage = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture image: $e')),
        );
      }
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF313244),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Attach Image',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: Colors.purpleAccent,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImageFromGallery();
                    },
                  ),
                  _buildImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: Colors.cyanAccent,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImageFromCamera();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _removePendingImage() {
    setState(() {
      _pendingImage = null;
    });
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty && _pendingImage == null) return;
    if (_isGenerating) return;

    if (widget.llmService.status != LlmStatus.loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a model first.')),
      );
      return;
    }

    final prompt = text.trim().isEmpty && _pendingImage != null
        ? 'Describe this image.'
        : text.trim();

    _textController.clear();

    final imageToSend = _pendingImage;
    setState(() {
      _messages.add(ChatMessage(
        text: prompt,
        isUser: true,
        imageBytes: imageToSend,
      ));
      _pendingImage = null;
      _isGenerating = true;
    });

    _scrollToBottom();

    setState(() {
      _messages.add(ChatMessage(text: "", isUser: false));
    });

    try {
      String? response;

      if (imageToSend != null && widget.llmService.supportsVision) {
        // Model has vision encoder — send image + text
        response = await widget.llmService.generateResponseWithImage(
          prompt,
          imageToSend,
        );
      } else {
        // Text-only (either no image, or model doesn't support vision)
        if (imageToSend != null && !widget.llmService.supportsVision) {
          // Notify user that image is ignored
          setState(() {
            _messages.last = ChatMessage(
              text: '⚠️ The loaded model lacks a vision encoder (Gemma 3 270M and 1B are text-only, not multimodal). The image will be ignored. Use Gemma 3 4B+ for image understanding.\n\n_Processing text only..._',
              isUser: false,
            );
            _messages.add(ChatMessage(text: '', isUser: false));
          });
          _scrollToBottom();
        }
        response = await widget.llmService.generateResponse(prompt);
      }

      if (!mounted) return;

      if (response != null && response.isNotEmpty) {
        setState(() {
          _messages.last = ChatMessage(text: response!, isUser: false);
        });
        _scrollToBottom();
      } else {
        setState(() {
          _messages.last = ChatMessage(
            text: "⚠️ Model generated an empty response. The 270M model does not support image analysis — try a 1B+ model for vision tasks.",
            isUser: false,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.last = ChatMessage(
            text: "Error during generation: $e",
            isUser: false,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.llmService,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF1E1E2E),
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _buildStatusBar(),
              Expanded(child: _buildMessageList()),
              if (_isGenerating)
                const LinearProgressIndicator(color: Colors.purpleAccent),
              if (_pendingImage != null) _buildImagePreview(),
              _buildMessageComposer(),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF181825),
      elevation: 0,
      title: const Text(
        'Gemma Local AI',
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
      ),
      actions: [
        if (widget.llmService.status == LlmStatus.loaded)
          IconButton(
            icon: const Icon(Icons.eject, color: Colors.redAccent),
            tooltip: 'Offload Model',
            onPressed: () {
              widget.llmService.offloadModel();
            },
          )
        else
          IconButton(
            icon: const Icon(Icons.add, color: Colors.purpleAccent),
            tooltip: 'Load Model',
            onPressed: widget.llmService.status == LlmStatus.loading
                ? null
                : _pickAndLoadModel,
          ),
      ],
    );
  }

  Widget _buildStatusBar() {
    Color statusColor;
    String statusText;

    switch (widget.llmService.status) {
      case LlmStatus.unloaded:
        statusColor = Colors.grey;
        statusText = 'Model Unloaded (Press + to select)';
        break;
      case LlmStatus.loading:
        statusColor = Colors.orange;
        statusText = 'Loading Model into Memory...';
        break;
      case LlmStatus.loaded:
        statusColor = Colors.green;
        statusText = widget.llmService.supportsVision
            ? 'Gemma 3 Online — Vision + Text 📷'
            : 'Gemma 3 Online — Text Only (no vision)';
        break;
      case LlmStatus.error:
        statusColor = Colors.red;
        statusText = 'Model Error. Try again.';
        break;
    }

    return Container(
      width: double.infinity,
      color: statusColor.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: Text(
        statusText,
        style: TextStyle(
          color: statusColor,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              "No messages yet",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "📷 Tap the image icon to send photos",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.purpleAccent : const Color(0xFF313244),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(message.isUser ? 20 : 0),
            bottomRight: Radius.circular(message.isUser ? 0 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show image if present
            if (message.imageBytes != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    Image.memory(
                      message.imageBytes!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Image',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Text content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: message.isUser
                  ? Text(
                      message.text,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    )
                  : MarkdownBody(
                      data: message.text,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(color: Colors.white, fontSize: 15),
                        code: TextStyle(
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Image preview strip above the message composer
  Widget _buildImagePreview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: const BoxDecoration(color: Color(0xFF181825)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.memory(
                  _pendingImage!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _removePendingImage,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📷 Image attached',
                  style: TextStyle(
                    color: Colors.purpleAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(_pendingImage!.length / 1024).toStringAsFixed(0)} KB • Type a prompt or just send',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    final isLoaded = widget.llmService.status == LlmStatus.loaded;
    final canSend = isLoaded && !_isGenerating;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF181825),
        border: Border(top: BorderSide(color: Color(0xFF313244), width: 1)),
      ),
      child: Row(
        children: [
          // Image picker button
          Container(
            decoration: BoxDecoration(
              color: _pendingImage != null
                  ? Colors.purpleAccent.withValues(alpha: 0.3)
                  : const Color(0xFF313244),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _pendingImage != null
                    ? Icons.image_rounded
                    : Icons.add_photo_alternate_outlined,
                color: _pendingImage != null
                    ? Colors.purpleAccent
                    : Colors.white.withValues(alpha: 0.5),
                size: 22,
              ),
              tooltip: 'Attach Image',
              onPressed: canSend ? _showImageSourcePicker : null,
            ),
          ),
          const SizedBox(width: 8),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF313244),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _pendingImage != null
                      ? "Ask about this image..."
                      : "Chat with Gemma...",
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
                enabled: canSend,
                onSubmitted: _handleSubmitted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          Container(
            decoration: BoxDecoration(
              gradient: canSend
                  ? const LinearGradient(
                      colors: [Colors.purpleAccent, Colors.deepPurpleAccent],
                    )
                  : null,
              color: canSend ? null : Colors.grey.shade800,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: canSend
                  ? () => _handleSubmitted(_textController.text)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
