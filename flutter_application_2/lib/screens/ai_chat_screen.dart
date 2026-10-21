import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const String _apiKey =
      'AQ.Ab8RN6Jn2XETWXDUPF1FGrXmKebuBvhnGUhCNInEZglzJVPVSw';

  late final GenerativeModel _model;
  late final ChatSession _chatSession;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.system(
        'あなたは一人暮らしの若者向けの節約アドバイザーです。'
        'レシートや冷蔵庫の画像、またはテキストでの質問をもとに、具体的で実践しやすい節約術・レシピ・買い物のコツを提案してください。'
        '回答は日本語で、スマホで読みやすいよう短めの段落にしてください。'
        'Markdownの記号は使わず、プレーンテキストで書いてください。',
      ),
    );
    _chatSession = _model.startChat();

    _messages.add({
      'isUser': false,
      'text': 'こんにちは！家計のこと、節約レシピ、買い物の悩みなどなんでも相談してね。\nレシートや冷蔵庫の写真を送ってくれてもOKだよ！',
      'image': null,
    });
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('画像選択エラー: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    final imageToSend = _selectedImage;

    setState(() {
      _messages.add({'isUser': true, 'text': text, 'image': imageToSend});
      _isLoading = true;
      _selectedImage = null;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      final parts = <Part>[];
      if (text.isNotEmpty) {
        parts.add(TextPart(text));
      } else if (imageToSend != null) {
        parts.add(TextPart('この画像についてアドバイスをお願いします。'));
      }

      if (imageToSend != null) {
        final bytes = await imageToSend.readAsBytes();
        parts.add(DataPart('image/jpeg', bytes));
      }

      final response = await _chatSession.sendMessage(Content.multi(parts));

      setState(() {
        _messages.add({
          'isUser': false,
          'text': response.text ?? 'ごめんね、うまく答えられなかったみたい。',
          'image': null,
        });
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'isUser': false,
          'text': 'エラーが起きました。APIキーが設定されているか確認してね。\n詳細: $e',
          'image': null,
        });
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI節約アドバイザー',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: 120.0,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(
                  text: message['text'],
                  isUser: message['isUser'],
                  imageFile: message['image'],
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isUser,
    File? imageFile,
  }) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isUser
                ? const Radius.circular(20)
                : const Radius.circular(0),
            bottomRight: isUser
                ? const Radius.circular(0)
                : const Radius.circular(20),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(imageFile, fit: BoxFit.cover),
              ),
            if (imageFile != null && text.isNotEmpty) const SizedBox(height: 8),
            if (text.isNotEmpty)
              Text(
                text,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.only(
        left: 12.0,
        right: 12.0,
        top: 8.0,
        bottom: 100.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedImage != null)
            Stack(
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: FileImage(_selectedImage!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.black54),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ),
              ],
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image_outlined, color: Colors.blue),
                onPressed: _pickImage,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'AIに相談する...',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blue,
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
