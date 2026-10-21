import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/receipt_data.dart';
import '../services/gemini_service.dart';

/// AI相談室：レシートを撮影・選択 → OCR → その内容でAIに相談できる画面
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, this.onReceiptSaved});

  /// 「家計簿に登録」を押したときに呼ばれる（家計簿・DB担当とつなぐ口）
  final void Function(ReceiptData receipt)? onReceiptSaved;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

enum _Sender { user, ai }

class _ChatMessage {
  final _Sender sender;
  final String? text;
  final Uint8List? image;
  final ReceiptData? receipt;

  const _ChatMessage({required this.sender, this.text, this.image, this.receipt});
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _gemini = GeminiService.instance;
  final _picker = ImagePicker();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      sender: _Sender.ai,
      text: 'レシートを撮影するか、画像を選んでね。内容を読み取って、節約やレシピの相談にのるよ。\n'
          'もちろん、画像なしで普通に質問してもOK！',
    ),
  ];

  ChatSession? _chat;
  ReceiptData? _currentReceipt;
  bool _isLoading = false;

  static const _quickQuestions = [
    'どこを節約できる？',
    'この食材で作れるレシピは？',
    'もっと安く買う方法は？',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ───────── 画像 → OCR ─────────

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 1600, // 送信サイズを抑える
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final mimeType = file.mimeType ?? _guessMimeType(file.name);

    _addMessage(_ChatMessage(sender: _Sender.user, image: bytes, text: 'このレシートを読み取って'));
    setState(() => _isLoading = true);

    try {
      final receipt = await _gemini.analyzeReceipt(bytes, mimeType);

      if (!receipt.isReceipt) {
        _addMessage(const _ChatMessage(
          sender: _Sender.ai,
          text: 'レシートが見つからなかったみたい。明るい場所で、レシート全体が写るように撮り直してみてね。',
        ));
        return;
      }

      _currentReceipt = receipt;
      _chat = _gemini.startConsultation(
        receipt: receipt,
        imageBytes: bytes,
        mimeType: mimeType,
      );
      _addMessage(_ChatMessage(sender: _Sender.ai, receipt: receipt));
      _addMessage(const _ChatMessage(
        sender: _Sender.ai,
        text: '読み取れたよ！内容が違っていたら教えてね。このレシートについて気になることを聞いてみて。',
      ));
    } catch (e) {
      _addMessage(_ChatMessage(sender: _Sender.ai, text: '読み取りでエラーが起きました: $e'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────── 相談チャット ─────────

  Future<void> _sendText([String? preset]) async {
    final text = (preset ?? _textController.text).trim();
    if (text.isEmpty || _isLoading) return;

    _textController.clear();
    _addMessage(_ChatMessage(sender: _Sender.user, text: text));
    setState(() => _isLoading = true);

    _chat ??= _gemini.startConsultation();

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      _addMessage(_ChatMessage(
        sender: _Sender.ai,
        text: response.text ?? '（回答が空でした）',
      ));
    } catch (e) {
      _addMessage(_ChatMessage(sender: _Sender.ai, text: 'エラーが起きました: $e'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetChat() {
    setState(() {
      _chat = null;
      _currentReceipt = null;
      _messages
        ..clear()
        ..add(const _ChatMessage(
          sender: _Sender.ai,
          text: '新しい相談を始めよう。レシートを送るか、質問を入力してね。',
        ));
    });
  }

  void _saveReceipt(ReceiptData receipt) {
    if (widget.onReceiptSaved != null) {
      widget.onReceiptSaved!(receipt);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('家計簿に登録しました')),
      );
    } else {
      // 家計簿・DBとつなぐまでの仮動作
      debugPrint('【家計簿登録データ】${receipt.toMap()}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('家計簿連携は準備中です（データはコンソールに出力）')),
      );
    }
  }

  // ───────── 共通処理 ─────────

  void _addMessage(_ChatMessage message) {
    if (!mounted) return;
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI相談室'),
        actions: [
          IconButton(
            tooltip: '新しい相談',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _resetChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) return const _TypingBubble();
                return _buildMessage(_messages[index]);
              },
            ),
          ),
          if (_currentReceipt != null && !_isLoading) _buildQuickQuestions(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage message) {
    final isUser = message.sender == _Sender.user;
    final colors = Theme.of(context).colorScheme;

    Widget content;
    if (message.receipt != null) {
      content = _ReceiptCard(
        receipt: message.receipt!,
        onSave: () => _saveReceipt(message.receipt!),
      );
    } else {
      content = Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(message.image!, height: 180, fit: BoxFit.cover),
                ),
              ),
            if (message.text != null)
              SelectableText(message.text!, style: const TextStyle(fontSize: 15)),
          ],
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: content),
    );
  }

  Widget _buildQuickQuestions() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickQuestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          label: Text(_quickQuestions[index]),
          onPressed: () => _sendText(_quickQuestions[index]),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        // メイン画面下部の丸ボタン（SNS / SA）と重ならないように余白をとる
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
        child: Row(
          children: [
            IconButton(
              tooltip: 'カメラで撮る',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
            ),
            IconButton(
              tooltip: '画像を選ぶ',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !_isLoading,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'AIに相談する',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            IconButton(
              tooltip: '送信',
              icon: const Icon(Icons.send),
              onPressed: _isLoading ? null : _sendText,
            ),
          ],
        ),
      ),
    );
  }
}

/// 読み取り結果を表示するカード
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt, required this.onSave});

  final ReceiptData receipt;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final d = receipt.date;
    final dateText = d == null
        ? '日付不明'
        : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.8,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      receipt.store ?? '店名不明',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (receipt.category != null) Chip(label: Text(receipt.category!)),
                ],
              ),
              Text(dateText, style: TextStyle(color: Colors.grey.shade700)),
              const Divider(),
              for (final item in receipt.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(item.name)),
                      Text('${item.price}円'),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text('合計', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text(
                    '${receipt.totalOrSum}円',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('家計簿に登録'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AIが考え中のときの表示
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('考え中...'),
          ],
        ),
      ),
    );
  }
}
