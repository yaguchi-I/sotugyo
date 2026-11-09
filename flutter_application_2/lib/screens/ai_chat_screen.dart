import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const String _apiKey = '';

  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isCheckingSetup = true;
  bool _isSetupComplete = false;

  final TextEditingController _areaController = TextEditingController();
  final List<String> _cookingAppliances = [
    '電子レンジ',
    'オーブン',
    '炊飯器',
    'トースター',
    'コンロ(2口以上)',
    'ミキサー',
    '冷蔵庫',
  ];
  final List<String> _missingAppliances = [];
  String _userArea = '';

  GenerativeModel? _model;
  ChatSession? _chatSession;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _checkInitialSetup();
  }

  Future<void> _checkInitialSetup() async {
    if (_currentUserId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      if (doc.exists && doc.data()!['aiSetupComplete'] == true) {
        _userArea = doc.data()!['area'] ?? '';
        _missingAppliances.addAll(
          List<String>.from(doc.data()!['missingAppliances'] ?? []),
        );
        _initAiModel();
        setState(() {
          _isSetupComplete = true;
          _isCheckingSetup = false;
        });
      } else {
        setState(() {
          _isCheckingSetup = false;
        });
      }
    } catch (e) {
      debugPrint('セットアップ確認エラー: $e');
      setState(() => _isCheckingSetup = false);
    }
  }

  Future<void> _saveSetupAndStart() async {
    if (_currentUserId.isEmpty || _areaController.text.isEmpty) return;

    setState(() => _isCheckingSetup = true);
    _userArea = _areaController.text.trim();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .set({
          'aiSetupComplete': true,
          'area': _userArea,
          'missingAppliances': _missingAppliances,
        }, SetOptions(merge: true));

    _initAiModel();

    setState(() {
      _isSetupComplete = true;
      _isCheckingSetup = false;
    });
  }

  void _initAiModel() {
    final missingApplianceText = _missingAppliances.isEmpty
        ? '特にありません。'
        : _missingAppliances.join('、');

    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.system(
        'あなたは一人暮らし向けの節約・料理アドバイザーです。'
        'ユーザーは「$_userArea」に住んでおり、以下の調理家電を持っていません：【$missingApplianceText】。'
        '必ず持っていない家電を「一切使わずに」作れる料理を提案してください。'
        '回答はレシピ帳に保存されるため、必ず以下の構成で出力してください。\n\n'
        '【料理名】\n'
        '【材料】\n'
        '【作り方】\n\n'
        'スマホで読みやすいよう、全体を250文字程度で簡潔にまとめてください。Markdown記号は使用しないでください。',
      ),
    );
    _chatSession = _model!.startChat();
    _messages.add({
      'isUser': false,
      'text':
          '設定完了！\n持っていない家電（$missingApplianceText）を使わないレシピや、$_userArea の気候に合わせた節約術を提案するよ。何を作る？',
      'image': null,
    });
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _selectedImage = File(pickedFile.path));
      }
    } catch (e) {
      debugPrint('画像選択エラー: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_chatSession == null) return;

    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    FocusScope.of(context).unfocus();
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
      if (text.isNotEmpty)
        parts.add(TextPart(text));
      else if (imageToSend != null)
        parts.add(TextPart('この画像についてアドバイスをお願いします。'));

      if (imageToSend != null) {
        final bytes = await imageToSend.readAsBytes();
        parts.add(DataPart('image/jpeg', bytes));
      }

      final response = await _chatSession!.sendMessage(Content.multi(parts));

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
          'text': 'エラーが起きました。通信状況を確認してね。',
          'image': null,
        });
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _saveAiSuggestion(String suggestionText) async {
    if (_currentUserId.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'content': suggestionText,
        'userName': 'AI提案レシピ',
        'hasImage': false,
        'mainCategory': 'AI',
        'subCategory': 'レシピ',
        'savedUsers': [_currentUserId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AIタグに保存しました！'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('保存エラー: $e');
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
    _areaController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSetup) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isSetupComplete) {
      return _buildSetupScreen();
    }

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

  Widget _buildSetupScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('AIアシスタント初期設定'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'お住まいの地域',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaController,
              decoration: InputDecoration(
                hintText: '例: 東京都、北海道 など',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '持っていない調理家電 (複数選択可)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '※選択された家電を使わないレシピを提案します',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _cookingAppliances.map((appliance) {
                final isSelected = _missingAppliances.contains(appliance);
                return FilterChip(
                  label: Text(appliance),
                  selected: isSelected,
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _missingAppliances.add(appliance);
                      } else {
                        _missingAppliances.remove(appliance);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _areaController.text.isNotEmpty
                    ? _saveSetupAndStart
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  'この設定でAIに相談する',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
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
          maxWidth: MediaQuery.of(context).size.width * 0.8,
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

            if (!isUser && text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => _saveAiSuggestion(text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_add_outlined,
                          size: 16,
                          color: Colors.blue,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '保存',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
