import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  static const String apiKey = '';

  @override
  State createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State {
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isCheckingSetup = true;
  bool _isSetupComplete = false;

  final TextEditingController _areaController = TextEditingController();
  final List _cookingAppliances = [
    '電子レンジ',
    'オーブン',
    '炊飯器',
    'トースター',
    'コンロ(2口以上)',
    'ミキサー',
    '冷蔵庫',
  ];
  final List _missingAppliances = [];
  String _userArea = '';
  String _userName = 'あなた';

  final List _quickPrompts = [
    {
      'label': '🍳 150円以下のスピード飯',
      'prompt': '150円以下で10分以内に作れる、洗い物が少ない節約レシピを教えて！',
    },
    {
      'label': '🥬 冷蔵庫の余り物で1品',
      'prompt': '一人暮らしの冷蔵庫に余りがちな食材（卵やもやし、キャベツなど）を使った簡単おかずを教えて！',
    },
    {'label': '🍱 冷凍できる作り置き', 'prompt': '休日にまとめて作れて、平日が楽になる節約作り置きレシピを教えて！'},
    {
      'label': '💡 今月の光熱費を削る裏技',
      'prompt': '今の季節にすぐ実践できる、電気代・ガス代・水道代の効果的な節約術を教えて！',
    },
    {
      'label': '🧹 100均グッズで時短掃除',
      'prompt': 'キッチンやお風呂の汚れを、家にあるものや100均アイテムで簡単に落とす掃除術を教えて！',
    },
  ];

  GenerativeModel? _model;
  ChatSession? _chatSession;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List _messages = [];
  final Set _savedMessageIndexes = {};
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _checkInitialSetup();
  }

  String _getSeason(int month) {
    if (const [3, 4, 5].contains(month)) return '春';
    if (const [6, 7, 8].contains(month)) return '夏';
    if (const [9, 10, 11].contains(month)) return '秋';
    return '冬';
  }

  Future _checkInitialSetup() async {
    if (_currentUserId.isEmpty) {
      setState(() => _isCheckingSetup = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data['userName'] != null &&
            data['userName'].toString().trim().isNotEmpty) {
          _userName = data['userName'].toString().trim();
        }
        if (data['aiSetupComplete'] == true) {
          _userArea = data['area']?.toString() ?? '';
          _areaController.text = _userArea;
          _missingAppliances.clear();
          _missingAppliances.addAll(List.from(data['missingAppliances'] ?? []));
          _initAiModel();
          setState(() {
            _isSetupComplete = true;
            _isCheckingSetup = false;
          });
          return;
        }
      }
      setState(() {
        _isCheckingSetup = false;
      });
    } catch (e) {
      setState(() => _isCheckingSetup = false);
    }
  }

  Future _saveSetupAndStart() async {
    if (_currentUserId.isEmpty || _areaController.text.trim().isEmpty) return;

    setState(() => _isCheckingSetup = true);
    _userArea = _areaController.text.trim();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'aiSetupComplete': true,
            'area': _userArea,
            'missingAppliances': _missingAppliances,
          }, SetOptions(merge: true));
    } catch (e) {}

    _messages.clear();
    _savedMessageIndexes.clear();
    _initAiModel();

    setState(() {
      _isSetupComplete = true;
      _isCheckingSetup = false;
    });
  }

  void _initAiModel() {
    final now = DateTime.now();
    final season = _getSeason(now.month);
    final missingApplianceText = _missingAppliances.isEmpty
        ? '特にありません'
        : _missingAppliances.join('、');

    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: AiChatScreen.apiKey.trim(),
      systemInstruction: Content.system(
        'あなたは一人暮らしをサポートするプロの節約・自炊・生活アドバイザーです。\n'
        'ユーザー名：$_userName\n'
        '現在の日付：${now.year}年${now.month}月${now.day}日（季節：$season）\n'
        '居住地域：$_userArea\n'
        '持っていない調理家電：【$missingApplianceText】\n\n'
        '【厳守ルール】\n'
        '1. 持っていない調理家電を「一切使わない」方法だけを提案してください。\n'
        '2. 居住地域（$_userArea）や現在の季節（$season）に合った旬の食材や気候対策を取り入れてください。\n'
        '3. 質問内容に応じて必ず以下の見出しフォーマットで回答してください。\n'
        '①料理・レシピの相談の場合：\n'
        '【料理名】\n'
        '【目安時間・費用】\n'
        '【材料】\n'
        '【作り方】\n'
        '【節約・代用ポイント】\n\n'
        '②掃除・収納・光熱費・その他の生活相談の場合：\n'
        '【タイトル】\n'
        '【用意するもの】\n'
        '【実践ステップ】\n'
        '【節約効果・コツ】\n\n'
        'スマホ画面でパッと読めるよう、全体を250〜300文字程度で簡潔にまとめ、Markdown記号（*や#など）は一切使わないでください。',
      ),
    );
    _chatSession = _model!.startChat();
    _messages.add({
      'isUser': false,
      'text':
          '$_userNameさん、こんにちは！\n持っていない家電（$missingApplianceText）を使わない自炊レシピや、$_userAreaの${_getSeason(now.month)}に合わせた節約術を提案するよ。\n下のボタンを選ぶか、冷蔵庫の写真を送ってみてね！',
      'image': null,
    });
  }

  void _resetChat() {
    setState(() {
      _messages.clear();
      _savedMessageIndexes.clear();
      _selectedImage = null;
      _initAiModel();
    });
  }

  Future _showImageSourceSheet() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '食材や場所の写真を追加',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('カメラで撮影する'),
                subtitle: const Text('冷蔵庫の中身や食材をその場で撮影'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('アルバムから選択する'),
                subtitle: const Text('保存済みの写真から選ぶ'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() => _selectedImage = File(pickedFile.path));
      }
    } catch (e) {}
  }

  Future _sendMessage({String? presetText}) async {
    if (_chatSession == null || _isLoading) return;

    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    FocusScope.of(context).unfocus();
    final imageToSend = _selectedImage;

    setState(() {
      _messages.add({
        'isUser': true,
        'text': text.isEmpty ? '（写真を送信しました）' : text,
        'image': imageToSend,
      });
      _isLoading = true;
      _selectedImage = null;
    });
    if (presetText == null) {
      _textController.clear();
    }
    _scrollToBottom();

    try {
      final parts = <Part>[];
      if (text.isNotEmpty) {
        parts.add(TextPart(text));
      } else if (imageToSend != null) {
        parts.add(TextPart('この写真に写っている食材や状況を見て、最適なレシピまたは解決アドバイスを提案してください。'));
      }

      if (imageToSend != null) {
        final bytes = await imageToSend.readAsBytes();
        parts.add(DataPart('image/jpeg', bytes));
      }

      final response = await _chatSession!.sendMessage(Content.multi(parts));

      setState(() {
        _messages.add({
          'isUser': false,
          'text': response.text ?? 'ごめんね、うまく答えられなかったみたい。もう一度試してみてね。',
          'image': null,
        });
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'isUser': false,
          'text': 'AI通信エラーが発生しました。\n詳細: $e',
          'image': null,
        });
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future _saveAiSuggestion(String suggestionText, int index) async {
    if (_currentUserId.isEmpty || _savedMessageIndexes.contains(index)) return;

    final bool isRecipe = suggestionText.contains('【料理名】');
    final String subCat = isRecipe ? 'レシピ' : '節約術';
    final String postTitle = isRecipe ? 'AI提案レシピ' : 'AI生活アドバイス';

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'content': suggestionText,
        'userName': postTitle,
        'hasImage': false,
        'mainCategory': 'AI',
        'subCategory': subCat,
        'savedUsers': [_currentUserId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _savedMessageIndexes.add(index);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存フォルダの「AI（$subCat）」に保存しました！'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {}
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

    final missingSummary = _missingAppliances.isEmpty
        ? '制限家電なし'
        : '不使用: ${_missingAppliances.join('・')}';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI節約・自炊アドバイザー',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              '📍$_userArea ｜ $missingSummary',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            tooltip: '会話をリセット',
            onPressed: _resetChat,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.black87),
            tooltip: '地域・家電の設定変更',
            onPressed: () {
              setState(() {
                _areaController.text = _userArea;
                _isSetupComplete = false;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQuickPromptBar(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 12.0,
                bottom: 24.0,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index] as Map;
                return _buildMessageBubble(
                  index: index,
                  text: message['text']?.toString() ?? '',
                  isUser: message['isUser'] == true,
                  imageFile: message['image'] as File?,
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AIが最適なプランを考えています...',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildQuickPromptBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Row(
          children: _quickPrompts.map((item) {
            final mapItem = item as Map;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ActionChip(
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
                label: Text(
                  mapItem['label'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
                onPressed: _isLoading
                    ? null
                    : () => _sendMessage(
                        presetText: mapItem['prompt'].toString(),
                      ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIアシスタント初期設定'),
        elevation: 0,
        leading: _userArea.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _isSetupComplete = true),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'お住まいの地域と持っていない家電を登録すると、あなたの部屋で作れるレシピや節約術だけをAIが提案します。',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'お住まいの地域',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '例: 長野県、山梨県、東京都 など',
                prefixIcon: const Icon(Icons.location_on_outlined),
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
              '※選択した家電を一切使わない調理法や代替案を提案します',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _cookingAppliances.map((appliance) {
                final appName = appliance.toString();
                final isSelected = _missingAppliances.contains(appName);
                return FilterChip(
                  label: Text(appName),
                  selected: isSelected,
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _missingAppliances.add(appName);
                      } else {
                        _missingAppliances.remove(appName);
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
                onPressed: _areaController.text.trim().isNotEmpty
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
    required int index,
    required String text,
    required bool isUser,
    File? imageFile,
  }) {
    final bool isSaved = _savedMessageIndexes.contains(index);
    final bool isInitialGreeting = index == 0 && !isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.shade100,
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.blue,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageFile != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          imageFile,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: isUser ? Colors.white : Colors.black87,
                      ),
                    ),
                  if (!isUser && !isInitialGreeting && text.isNotEmpty) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: isSaved
                              ? null
                              : () => _saveAiSuggestion(text, index),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSaved
                                  ? Colors.green.shade50
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSaved
                                    ? Colors.green.shade200
                                    : Colors.blue.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSaved
                                      ? Icons.check_circle
                                      : Icons.bookmark_add_outlined,
                                  size: 16,
                                  color: isSaved ? Colors.green : Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isSaved ? '保存済み' : '保存フォルダに追加',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSaved ? Colors.green : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.only(
        left: 12.0,
        right: 12.0,
        top: 8.0,
        bottom: 95.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedImage != null)
            Stack(
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8, left: 8),
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200, width: 2),
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
                    icon: const Icon(Icons.cancel, color: Colors.black87),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ),
              ],
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Colors.blue,
                ),
                tooltip: 'カメラまたは写真を追加',
                onPressed: _showImageSourceSheet,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '食材や悩みを入力（例: もやしと卵で1品）',
                    hintStyle: const TextStyle(fontSize: 14),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blue,
                radius: 22,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _isLoading ? null : () => _sendMessage(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
