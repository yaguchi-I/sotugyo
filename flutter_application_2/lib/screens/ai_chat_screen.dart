import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/ai_knowledge_service.dart';
import 'sns_detail_screen.dart';

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;
  final Map? referencedPost;

  const AiChatScreen({super.key, this.initialPrompt, this.referencedPost});

  static const String apiKey = '';

  static const List fallbackModels = [
    'gemini-3.5-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash-lite',
    'gemini-2.5-flash',
    'gemini-3.5-flash',
  ];

  @override
  State createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State {
  String? get _initialPrompt => (widget as AiChatScreen).initialPrompt;
  Map? get _referencedPost => (widget as AiChatScreen).referencedPost;

  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isCheckingSetup = true;
  bool _isSetupComplete = false;
  bool _hasTriggeredInitialPrompt = false;

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
  final List _blockedUsers = [];
  String _userArea = '';
  String _userName = 'あなた';
  String _activeModelName = AiChatScreen.fallbackModels.first.toString();

  final List _quickPrompts = [
    {
      'label': '🍲 鍋で作れる安い料理',
      'prompt': '鍋で作れるあまり高くないおすすめの料理はある？みんなの投稿も参考にして教えて！',
    },
    {
      'label': '🍳 150円以下のスピード飯',
      'prompt': '150円以下で10分以内に作れる、洗い物が少ない節約レシピを教えて！',
    },
    {'label': '🥬 冷蔵庫の余り物で1品', 'prompt': '一人暮らしの冷蔵庫に余りがちな食材を使った簡単おかずのレシピを教えて！'},
    {'label': '💡 光熱費を削る裏技', 'prompt': '今の季節にすぐ実践できる、電気代・ガス代・水道代の効果的な節約術を教えて！'},
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
  final List _chatHistorySessions = [];
  final Set _savedMessageIndexes = Set();
  String _currentSessionId = '';
  bool _isLoading = false;
  String _loadingStatus = 'AIが回答を考えています...';
  Uint8List? _selectedImageBytes;

  @override
  void initState() {
    super.initState();
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _checkInitialSetup();
  }

  List _toMapList(dynamic rawList) {
    final List result = [];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          result.add(Map.from(item));
        }
      }
    }
    return result;
  }

  String _getSeason(int month) {
    if (const [3, 4, 5].contains(month)) return '春';
    if (const [6, 7, 8].contains(month)) return '夏';
    if (const [9, 10, 11].contains(month)) return '秋';
    return '冬';
  }

  String _formatNowTime() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$m/$d $hh:$mm';
  }

  bool _isCookingQuery(String text) {
    const List cookingKeywords = [
      'レシピ',
      '料理',
      '作り方',
      '献立',
      'おかず',
      'ご飯',
      'ごはん',
      'スピード飯',
      '作り置き',
      '食材',
      '弁当',
      '朝食',
      '昼食',
      '夕食',
      '夕飯',
      '夜ご飯',
      '自炊',
      'メニュー',
      '炒め',
      '煮物',
      'パスタ',
      'うどん',
      '丼',
      'スープ',
      '味噌汁',
      'おつまみ',
      '鍋',
      'キャベツ',
      '豚肉',
      '鶏肉',
    ];
    const List nonCookingKeywords = [
      '掃除',
      '洗濯',
      '光熱費',
      '電気代',
      'ガス代',
      '水道代',
      '家賃',
      '収納',
      'ゴミ',
      'カビ',
      '排水口',
      'トイレ',
      'お風呂',
      'エアコン',
      '引っ越し',
      '防犯',
      '虫',
      'ゴキブリ',
      '貯金',
      '通信費',
    ];

    for (final nk in nonCookingKeywords) {
      if (text.contains(nk.toString())) return false;
    }
    for (final ck in cookingKeywords) {
      if (text.contains(ck.toString())) return true;
    }
    return false;
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final season = _getSeason(now.month);
    final missingText = _missingAppliances.isEmpty
        ? '特になし'
        : _missingAppliances.join('、');
    final areaText = _userArea.isEmpty ? '日本' : _userArea;

    return 'あなたは一人暮らし向けSNSアプリ専属の超優秀なAIライフアドバイザーです。\n'
        'ユーザー名：$_userName\n'
        '現在：${now.year}年${now.month}月${now.day}日（季節：$season）\n'
        '居住地域：$areaText\n'
        '持っていない調理家電：$missingText\n\n'
        '【コミュニティ連携の最優先ルール】\n'
        '・プロンプト内に「【アプリ内のみんなの実体験投稿】」が渡された場合、その中から相談に最も役立つ投稿を積極的に引用し、「アプリ内では〇〇さんの『△△』という投稿も好評ですよ！」のように自然に紹介してください。\n'
        '・通常のつぶやき投稿（例：春キャベツの肉巻きが美味しかった等）であっても、ユーザーの条件（例：鍋で作る）に合わせて「鍋でロールキャベツ風に煮込むと美味しいですよ」のように具体的にアレンジ提案してください。\n'
        '・参考にした投稿がある場合は、回答のいちばん最後の行だけに [REF:docId1,docId2] の形式で該当のdocIdをカンマ区切りで出力してください（最大3件）。参考にした投稿がなければ [REF:] は書かないでください。\n\n'
        '【回答フォーマットのルール】\n'
        '1. 掃除・洗濯・光熱費節約・収納・生活の悩み・雑談など「料理のレシピ以外」の質問の場合：\n'
        '   ・レシピ形式（【料理名】【材料】【作り方】）は絶対に使わず、読みやすい自然な文章や箇条書きで答えてください。\n'
        '2. ユーザーが明確に「料理のレシピ・献立・食べ物の作り方」を求めた場合のみ：\n'
        '   ・持っていない調理家電（$missingText）を一切使わないレシピを考案し、以下の見出しを使って1人分の分量で回答してください。\n'
        '   【料理名】〇〇\n'
        '   【目安時間・費用】約〇分 / 約〇円\n'
        '   【材料】\n'
        '   ・材料名 分量\n'
        '   【作り方】\n'
        '   1. 手順1\n'
        '   2. 手順2\n'
        '3. 共通事項：Markdownの強調記号（**や##）は使わず、プレーンテキストで読みやすく出力してください。';
  }

  void _initAiSession([String? modelName]) {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      return;
    }
    final targetModel = modelName ?? _activeModelName;
    _activeModelName = targetModel;

    _model = GenerativeModel(
      model: targetModel,
      apiKey: currentKey,
      systemInstruction: Content.system(_buildSystemPrompt()),
    );
    _chatSession = _model!.startChat(
      history: [
        for (final rawMsg in _messages)
          if (rawMsg is Map &&
              (rawMsg['text']?.toString() ?? '').isNotEmpty &&
              rawMsg['role']?.toString() == 'user')
            Content.text(rawMsg['text'].toString())
          else if (rawMsg is Map &&
              (rawMsg['text']?.toString() ?? '').isNotEmpty &&
              rawMsg['role']?.toString() == 'ai')
            Content.model([TextPart(rawMsg['text'].toString())]),
      ],
    );
  }

  List _serializeMessages(List sourceMessages) {
    final List result = [];
    for (final rawMsg in sourceMessages) {
      if (rawMsg is! Map) continue;
      final List refs = [];
      for (final rawRef in _toMapList(rawMsg['referencedPosts'])) {
        final r = rawRef as Map;
        refs.add({
          'docId': (r['docId'] ?? '').toString(),
          'userName': (r['userName'] ?? '名無し').toString(),
          'title': (r['title'] ?? '').toString(),
          'content': (r['content'] ?? '').toString(),
          'recipeCost': (r['recipeCost'] ?? '').toString(),
          'helpfuls': AiKnowledgeService.readIntField(r['helpfuls']),
          'saves': AiKnowledgeService.readIntField(r['saves']),
          'likes': AiKnowledgeService.readIntField(r['likes']),
          'mainCategory': (r['mainCategory'] ?? '').toString(),
        });
      }
      result.add({
        'role': rawMsg['role']?.toString() ?? 'ai',
        'text': rawMsg['text']?.toString() ?? '',
        'time': rawMsg['time']?.toString() ?? '',
        'referencedPosts': refs,
      });
    }
    return result;
  }

  Future _persistChatLogs() async {
    if (_currentUserId.isEmpty) return;

    final serializedCurrent = _serializeMessages(_messages);
    final userMessages = serializedCurrent
        .where((m) => m is Map && m['role'] == 'user')
        .toList();

    if (userMessages.isNotEmpty) {
      final firstUserText =
          (userMessages.first as Map)['text']?.toString() ?? 'AI相談';
      final sessionTitle = firstUserText.length > 20
          ? '${firstUserText.substring(0, 20)}...'
          : firstUserText;

      final Map sessionData = {
        'id': _currentSessionId,
        'title': sessionTitle,
        'updatedAt': _formatNowTime(),
        'messages': serializedCurrent,
      };

      final existingIdx = _chatHistorySessions.indexWhere(
        (s) => s is Map && s['id'] == _currentSessionId,
      );
      if (existingIdx != -1) {
        _chatHistorySessions[existingIdx] = sessionData;
      } else {
        _chatHistorySessions.insert(0, sessionData);
      }

      if (_chatHistorySessions.length > 30) {
        _chatHistorySessions.removeRange(30, _chatHistorySessions.length);
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'currentSessionId': _currentSessionId,
            'currentChatMessages': serializedCurrent,
            'chatHistoryLogs': _chatHistorySessions,
          }, SetOptions(merge: true));
    } catch (e) {}
  }

  Future _checkInitialSetup() async {
    if (_currentUserId.isEmpty) {
      setState(() {
        _isCheckingSetup = false;
        _isSetupComplete = true;
      });
      _initAiSession();
      _maybeRunInitialPrompt();
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();

      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final bool setupDone = data['isAiSetupDone'] == true;
        final String savedArea = data['area']?.toString() ?? '';
        final String savedName =
            (data['userName']?.toString().isNotEmpty == true
                    ? data['userName']
                    : data['name'])
                ?.toString() ??
            'あなた';
        final List savedMissing = data['missingAppliances'] is List
            ? List.from(data['missingAppliances'])
                  .map((e) => e.toString())
                  .toList()
            : [];
        final List savedBlocked = data['blockedUsers'] is List
            ? List.from(data['blockedUsers']).map((e) => e.toString()).toList()
            : [];
        final List loadedSessions = _toMapList(data['chatHistoryLogs']);
        final List loadedCurrentMsgs = _toMapList(data['currentChatMessages']);
        final String savedSessionId =
            data['currentSessionId']?.toString() ?? '';

        setState(() {
          _userName = savedName.isNotEmpty ? savedName : 'あなた';
          _userArea = savedArea;
          _areaController.text = savedArea;
          _missingAppliances
            ..clear()
            ..addAll(savedMissing);
          _blockedUsers
            ..clear()
            ..addAll(savedBlocked);
          _chatHistorySessions
            ..clear()
            ..addAll(loadedSessions);
          if (_initialPrompt == null && savedSessionId.isNotEmpty) {
            _currentSessionId = savedSessionId;
          }
          if (_initialPrompt == null && loadedCurrentMsgs.isNotEmpty) {
            _messages
              ..clear()
              ..addAll(loadedCurrentMsgs);
          }
          _isSetupComplete = setupDone;
          _isCheckingSetup = false;
        });

        if (setupDone) {
          if (_messages.isEmpty) {
            setState(() {
              _messages.add({
                'role': 'ai',
                'text':
                    'こんにちは、$_userNameさん！\nみんなの投稿（レシピや節約・掃除の知恵）も検索しながら、あなたの環境に合わせて提案します。何でも気軽に相談してくださいね！',
                'time': _formatNowTime(),
                'referencedPosts': [],
              });
            });
          }
          _initAiSession();
          _maybeRunInitialPrompt();
        }
      } else {
        setState(() {
          _isCheckingSetup = false;
          _isSetupComplete = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingSetup = false;
        _isSetupComplete = true;
      });
      _initAiSession();
      _maybeRunInitialPrompt();
    }
  }

  void _maybeRunInitialPrompt() {
    if (_hasTriggeredInitialPrompt) return;
    final initial = _initialPrompt?.trim() ?? '';
    if (initial.isNotEmpty) {
      _hasTriggeredInitialPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(initial, _referencedPost);
        }
      });
    }
  }

  void _startNewChatSession() {
    setState(() {
      _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      _savedMessageIndexes.clear();
      _messages
        ..clear()
        ..add({
          'role': 'ai',
          'text': '新しい相談スレッドを開始しました！\n料理・掃除・節約・暮らしの疑問など、みんなの投稿も探しながらお答えします。',
          'time': _formatNowTime(),
          'referencedPosts': [],
        });
    });
    _initAiSession();
    _persistChatLogs();
  }

  Future _deleteHistorySession(String sessionId) async {
    setState(() {
      _chatHistorySessions.removeWhere((s) => s is Map && s['id'] == sessionId);
    });
    if (_currentSessionId == sessionId) {
      _startNewChatSession();
    } else {
      await _persistChatLogs();
    }
  }

  void _showChatLogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.history, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'AI相談ログ履歴',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _startNewChatSession();
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('新しい相談'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _chatHistorySessions.isEmpty
                          ? const Center(
                              child: Text(
                                'まだ保存された相談ログはありません。\nAIに質問すると自動でここに履歴が残ります。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.all(12),
                              itemCount: _chatHistorySessions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final session =
                                    _chatHistorySessions[idx] as Map;
                                final String sId =
                                    session['id']?.toString() ?? '';
                                final String sTitle =
                                    session['title']?.toString() ?? '相談ログ';
                                final String sTime =
                                    session['updatedAt']?.toString() ?? '';
                                final List sMsgs = _toMapList(
                                  session['messages'],
                                );
                                final bool isCurrent = sId == _currentSessionId;

                                return Card(
                                  elevation: isCurrent ? 2 : 1,
                                  color: isCurrent
                                      ? Colors.blue.shade50
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isCurrent
                                          ? Colors.blue.shade300
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: ExpansionTile(
                                    leading: Icon(
                                      isCurrent
                                          ? Icons.chat_bubble
                                          : Icons.chat_bubble_outline,
                                      color: isCurrent
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    title: Text(
                                      sTitle,
                                      style: TextStyle(
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '最終更新: $sTime （全${sMsgs.length}件のやり取り）',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'このログを削除',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        await _deleteHistorySession(sId);
                                        setSheetState(() {});
                                      },
                                    ),
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          12,
                                        ),
                                        color: Colors.grey.shade50,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final rawM in sMsgs)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4.0,
                                                    ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      (rawM as Map)['role'] ==
                                                              'user'
                                                          ? 'あなた: '
                                                          : 'AI: ',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color:
                                                            rawM['role'] ==
                                                                'user'
                                                            ? Colors
                                                                  .blue
                                                                  .shade800
                                                            : Colors.teal,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        rawM['text']
                                                                ?.toString() ??
                                                            '',
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    if ((rawM['time']
                                                                ?.toString() ??
                                                            '')
                                                        .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 6,
                                                            ),
                                                        child: Text(
                                                          rawM['time']
                                                              .toString(),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: ElevatedButton.icon(
                                                onPressed: () {
                                                  setState(() {
                                                    _currentSessionId = sId;
                                                    _savedMessageIndexes
                                                        .clear();
                                                    _messages
                                                      ..clear()
                                                      ..addAll(sMsgs);
                                                  });
                                                  _initAiSession();
                                                  Navigator.pop(sheetContext);
                                                  _scrollToBottom();
                                                },
                                                icon: const Icon(
                                                  Icons.restore,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  'この相談ログを開いて続きを話す',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future _saveSetupAndStart() async {
    final inputArea = _areaController.text.trim();
    if (inputArea.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('お住まいの都道府県や地域を入力してください')));
      return;
    }

    setState(() {
      _isCheckingSetup = true;
      _userArea = inputArea;
    });

    if (_currentUserId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .set({
              'area': _userArea,
              'missingAppliances': _missingAppliances,
              'isAiSetupDone': true,
            }, SetOptions(merge: true));
      } catch (e) {}
    }

    if (!mounted) return;

    setState(() {
      _isSetupComplete = true;
      _isCheckingSetup = false;
      if (_messages.isEmpty) {
        _messages.add({
          'role': 'ai',
          'text':
              '設定ありがとうございます！\n地域（$_userArea）や家電状況、さらにアプリ内のみんなの実体験投稿も検索しながらサポートしますね！',
          'time': _formatNowTime(),
          'referencedPosts': [],
        });
      }
    });
    _initAiSession();
    _persistChatLogs();
    _maybeRunInitialPrompt();
  }

  Future _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        if (mounted) {
          setState(() {
            _selectedImageBytes = bytes;
          });
        }
      }
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

  String _formatCommunityPostsForPrompt(List posts) {
    if (posts.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('\n【アプリ内のみんなの実体験投稿（優先度順）】');
    for (int i = 0; i < posts.length; i++) {
      final p = posts[i] as Map;
      final docId = (p['docId'] ?? '').toString();
      final userName = (p['userName'] ?? '名無し').toString();
      final title = (p['title'] ?? '').toString();
      final content = (p['content'] ?? '').toString();
      final cost = (p['recipeCost'] ?? '').toString();
      final priceTier = (p['priceTier'] ?? 'none').toString();
      final helpfuls = p['helpfuls'] ?? 0;
      final saves = p['saves'] ?? 0;
      final likes = p['likes'] ?? 0;
      final ingItems = _toMapList(p['recipeIngredients']);
      final ings = ingItems
          .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}'.trim())
          .join('、');
      buffer.writeln(
        '${i + 1}. [docId:$docId] 投稿者:$userName / カテゴリ:${p['mainCategory']}(${p['subCategory']}) / 評価:保存$saves・参考になった$helpfuls・いいね$likes / 価格帯:$priceTier ${cost.isNotEmpty ? "($cost)" : ""}',
      );
      if (title.isNotEmpty) buffer.writeln('   タイトル: $title');
      if (content.isNotEmpty) buffer.writeln('   本文: $content');
      if (ings.isNotEmpty) buffer.writeln('   材料: $ings');
      final steps = (p['recipeSteps'] ?? '').toString();
      if (steps.isNotEmpty) buffer.writeln('   手順: $steps');
    }
    return buffer.toString();
  }

  Map _extractReferenceTag(String rawReply, List candidatePosts) {
    final regex = RegExp(r'\[REF:([^\]]*)\]');
    final match = regex.firstMatch(rawReply);
    final List selectedRefs = [];

    if (match != null) {
      final idString = match.group(1) ?? '';
      final ids = idString
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final id in ids) {
        for (final rawP in candidatePosts) {
          final p = rawP as Map;
          if (p['docId'] == id &&
              !selectedRefs.any((r) => (r as Map)['docId'] == id)) {
            selectedRefs.add(p);
          }
        }
      }
    }

    final cleanText = rawReply
        .replaceAll(regex, '')
        .replaceAll('**', '')
        .replaceAll('##', '')
        .trim();

    if (selectedRefs.isEmpty && candidatePosts.isNotEmpty) {
      for (final rawP in candidatePosts.take(2)) {
        final p = rawP as Map;
        final double rScore = (p['rankScore'] is num)
            ? (p['rankScore'] as num).toDouble()
            : 0.0;
        if (rScore >= 25.0) {
          selectedRefs.add(p);
        }
      }
    }

    return {
      'cleanText': cleanText,
      'referencedPosts': selectedRefs.take(3).toList(),
    };
  }

  Future _sendMessage([String? presetText, Map? explicitContextPost]) async {
    final rawText = presetText ?? _textController.text.trim();
    final Uint8List? imageBytes = _selectedImageBytes;

    if (rawText.isEmpty && imageBytes == null) return;
    if (_isLoading) return;

    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': 'APIキーがまだ設定されていません。\nai_chat_screen.dart の20行目にある apiKey にキーを貼り付けて保存してください。',
          'time': _formatNowTime(),
          'referencedPosts': [],
        });
      });
      _scrollToBottom();
      return;
    }

    final sentTime = _formatNowTime();

    setState(() {
      _messages.add({
        'role': 'user',
        'text': rawText.isEmpty ? '（画像を送信しました）' : rawText,
        'imageBytes': imageBytes,
        'time': sentTime,
        'referencedPosts': [],
      });
      if (presetText == null) {
        _textController.clear();
      }
      _selectedImageBytes = null;
      _isLoading = true;
      _loadingStatus = '🔍 相談内容を解析中...';
    });
    _scrollToBottom();

    final List retrievedPosts = [];
    if (explicitContextPost != null) {
      retrievedPosts.add(explicitContextPost);
    }

    if (rawText.isNotEmpty) {
      try {
        final rawPlan = await AiKnowledgeService.extractSearchPlan(
          userQuery: rawText,
          missingAppliances: _missingAppliances,
        );

        if (rawPlan is Map && rawPlan['needsSearch'] == true) {
          if (mounted) {
            setState(() {
              _loadingStatus = '📚 みんなの投稿から参考になる実体験を検索中...';
            });
          }

          final rawFound =
              await AiKnowledgeService.searchRelevantCommunityPosts(
                searchTags: rawPlan['searchTags'] is List
                    ? List.from(rawPlan['searchTags'])
                    : const [],
                category: (rawPlan['category'] ?? 'すべて').toString(),
                preferredPriceTier: (rawPlan['preferredPriceTier'] ?? 'any')
                    .toString(),
                maxBudgetYen:
                    int.tryParse('${rawPlan['maxBudgetYen'] ?? -1}') ?? -1,
                missingAppliances: _missingAppliances,
                currentUserId: _currentUserId,
                blockedUsers: _blockedUsers,
                topK: 5,
              );

          if (rawFound is List) {
            for (final item in rawFound) {
              if (item is Map &&
                  !retrievedPosts.any(
                    (e) => (e as Map)['docId'] == item['docId'],
                  )) {
                retrievedPosts.add(item);
              }
            }
          }
        }
      } catch (e) {}
    }

    if (mounted) {
      setState(() {
        _loadingStatus = retrievedPosts.isNotEmpty
            ? '✨ 見つかった${retrievedPosts.length}件の投稿とあなたの環境を元に回答を作成中...'
            : '✨ あなたの環境に合わせて回答を作成中...';
      });
    }

    final bool wantsRecipe = _isCookingQuery(rawText);
    final String communityContext = _formatCommunityPostsForPrompt(
      retrievedPosts,
    );

    final String wrappedPrompt = wantsRecipe
        ? '$rawText\n$communityContext\n（※料理・レシピの相談なので、【料理名】【目安時間・費用】【材料】【作り方】の形式で1人分の分量を具体的に回答してください。持っていない家電は使わないでください。アプリ内投稿が役立つ場合は自然に紹介し、最後に [REF:docId] を付けてください。）'
        : '$rawText\n$communityContext\n（※これは料理のレシピ相談ではありません。【料理名】や【材料】【作り方】などのレシピ用フォーマットは絶対に使わず、相談内容に合った自然な文章やアドバイス形式で回答してください。アプリ内投稿が役立つ場合は自然に紹介し、最後に [REF:docId] を付けてください。）';

    String? aiReply;
    Object? lastError;

    for (final candidateItem in AiChatScreen.fallbackModels) {
      final candidateModel = candidateItem.toString();
      try {
        if (_chatSession == null || _activeModelName != candidateModel) {
          _initAiSession(candidateModel);
        }

        GenerateContentResponse response;
        if (imageBytes != null) {
          final promptText = rawText.isEmpty
              ? 'この画像を見て、もし食材なら作れるレシピを、もし汚れや日用品なら掃除や活用のアドバイスを自然に教えてください。'
              : wrappedPrompt;
          response = await _model!
              .generateContent([
                Content.multi([
                  TextPart(promptText),
                  DataPart('image/jpeg', imageBytes),
                ]),
              ])
              .timeout(const Duration(seconds: 25));
        } else {
          response = await _chatSession!
              .sendMessage(Content.text(wrappedPrompt))
              .timeout(const Duration(seconds: 25));
        }

        if (response.text != null && response.text!.trim().isNotEmpty) {
          aiReply = response.text!.trim();
          break;
        }
      } catch (e) {
        lastError = e;
        _chatSession = null;
      }
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (aiReply != null) {
        final extracted = _extractReferenceTag(aiReply, retrievedPosts);
        _messages.add({
          'role': 'ai',
          'text': (extracted['cleanText'] ?? '').toString(),
          'time': _formatNowTime(),
          'referencedPosts': extracted['referencedPosts'],
        });
      } else {
        _messages.add({
          'role': 'ai',
          'text': '通信が混み合っているか回数制限に達しました。少し待ってからもう一度お試しください。\n($lastError)',
          'time': _formatNowTime(),
          'referencedPosts': [],
        });
      }
    });
    _scrollToBottom();
    await _persistChatLogs();
  }

  Map _parseAiSuggestion(String text) {
    final bool isActualRecipe =
        text.contains('【料理名】') &&
        text.contains('【材料】') &&
        text.contains('【作り方】');

    if (!isActualRecipe) {
      String summaryTitle = 'AIからの生活アドバイス';
      final List lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final String firstLine = lines.first
            .toString()
            .replaceAll(RegExp(r'[【】「」]'), '')
            .trim();
        if (firstLine.isNotEmpty) {
          summaryTitle = firstLine.length > 22
              ? '${firstLine.substring(0, 22)}...'
              : firstLine;
        }
      }
      return {
        'isRecipe': false,
        'title': summaryTitle,
        'subCategory': '節約術',
        'time': '',
        'cost': '',
        'ingredients': [],
        'steps': '',
      };
    }

    String title = 'AI提案レシピ';
    String time = '約10分';
    String cost = '約200円';
    final List ingredientsData = [];
    final List stepsLines = [];

    final titleMatch = RegExp(r'【料理名】\s*(.+)').firstMatch(text);
    if (titleMatch != null && titleMatch.group(1) != null) {
      title = titleMatch.group(1)!.trim();
    }

    final timeCostMatch = RegExp(r'【目安時間・費用】\s*(.+)').firstMatch(text);
    if (timeCostMatch != null && timeCostMatch.group(1) != null) {
      final tc = timeCostMatch.group(1)!.trim();
      final parts = tc.split(RegExp(r'[/／・]'));
      if (parts.isNotEmpty) time = parts[0].trim();
      if (parts.length > 1) cost = parts[1].trim();
    }

    final lines = text.split('\n');
    String currentSection = '';
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('【材料')) {
        currentSection = 'ing';
        continue;
      } else if (line.contains('【作り方') || line.contains('【手順')) {
        currentSection = 'step';
        continue;
      } else if (line.startsWith('【')) {
        currentSection = '';
        continue;
      }

      if (currentSection == 'ing') {
        final clean = line.replaceFirst(RegExp(r'^[・\-*•]\s*'), '').trim();
        if (clean.isNotEmpty) {
          final sp = clean.split(RegExp(r'[\s :：]+'));
          final name = sp.first;
          final amount = sp.length > 1 ? sp.sublist(1).join(' ') : '適量';
          ingredientsData.add({'name': name, 'amount': amount});
        }
      } else if (currentSection == 'step') {
        stepsLines.add(line);
      }
    }

    return {
      'isRecipe': true,
      'title': title,
      'subCategory': 'レシピ',
      'time': time,
      'cost': cost,
      'ingredients': ingredientsData,
      'steps': stepsLines.join('\n'),
    };
  }

  Future _saveAiSuggestion(int index, String suggestionText) async {
    if (_currentUserId.isEmpty) return;
    if (_savedMessageIndexes.contains(index)) return;

    final messenger = ScaffoldMessenger.of(context);
    final parsed = _parseAiSuggestion(suggestionText);
    final bool isRecipe = parsed['isRecipe'] == true;
    final String title = parsed['title'].toString();
    final String subCategory = parsed['subCategory'].toString();

    setState(() {
      _savedMessageIndexes.add(index);
    });

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'userId': _currentUserId,
        'userName': 'AIアドバイザー',
        'mainCategory': 'AI',
        'subCategory': subCategory,
        'title': title,
        'content': suggestionText,
        'imageUrl': '',
        'isRecipePost': isRecipe,
        'recipeTime': parsed['time'],
        'recipeCost': parsed['cost'],
        'recipeServings': 1,
        'recipeIngredients': parsed['ingredients'],
        'recipeSteps': parsed['steps'],
        'replies': 0,
        'likes': 0,
        'helpfuls': 0,
        'saves': 1,
        'impressions': 0,
        'valueScore': 0.0,
        'likedUsers': [],
        'helpfulUsers': [],
        'savedUsers': [_currentUserId],
        'hiddenUsers': [],
        'reportedUsers': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isRecipe
                ? 'レシピ「$title」を保存フォルダに追加しました！'
                : 'アドバイス「$title」を保存フォルダに追加しました！',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _savedMessageIndexes.remove(index);
      });
      messenger.showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    }
  }

  Widget _buildReferencedPostCard(Map post) {
    final String docId = (post['docId'] ?? '').toString();
    if (docId.isEmpty) return const SizedBox.shrink();

    final String userName = (post['userName'] ?? '名無し').toString();
    final String title = (post['title'] ?? '').toString();
    final String content = (post['content'] ?? '').toString();
    final String cost = (post['recipeCost'] ?? '').toString();
    final int helpfuls = AiKnowledgeService.readIntField(post['helpfuls']);
    final int saves = AiKnowledgeService.readIntField(post['saves']);
    final String previewText = title.isNotEmpty ? title : content;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SnsDetailScreen(postId: docId)),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 18,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$userName さんの投稿',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      if (cost.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          cost,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        size: 13,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$helpfuls',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.bookmark_border,
                        size: 13,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$saves',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '詳細を見る ›',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      return _buildSetupView();
    }

    final bool canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        title: const Text(
          'AI 暮らしの相談室',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: '過去の相談ログ履歴',
            icon: const Icon(Icons.history),
            onPressed: _showChatLogSheet,
          ),
          IconButton(
            tooltip: '新しい相談をはじめる',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _startNewChatSession,
          ),
          IconButton(
            tooltip: '地域・家電の設定を変更',
            icon: const Icon(Icons.tune),
            onPressed: () {
              setState(() {
                _isSetupComplete = false;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.blue.shade50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final rawItem in _quickPrompts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        backgroundColor: Colors.white,
                        label: Text(
                          ((rawItem as Map)['label'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _isLoading
                            ? null
                            : () => _sendMessage(
                                (rawItem['prompt'] ?? '').toString(),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _loadingStatus,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final msg = _messages[index] as Map;
                final isUser = msg['role'] == 'user';
                final text = msg['text']?.toString() ?? '';
                final timeStr = msg['time']?.toString() ?? '';
                final Uint8List? imageBytes = msg['imageBytes'] is Uint8List
                    ? msg['imageBytes'] as Uint8List
                    : null;
                final List referencedPosts = _toMapList(msg['referencedPosts']);
                final bool isSaved = _savedMessageIndexes.contains(index);

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.86,
                    ),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue.shade600 : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  imageBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        Text(
                          text,
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        if (!isUser && referencedPosts.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            '📌 参考になったみんなの投稿',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          for (final refPost in referencedPosts)
                            _buildReferencedPostCard(refPost as Map),
                        ],
                        if (timeStr.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isUser
                                      ? Colors.white70
                                      : Colors.black45,
                                ),
                              ),
                            ),
                          ),
                        if (!isUser && index > 0) ...[
                          const Divider(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: isSaved
                                  ? null
                                  : () => _saveAiSuggestion(index, text),
                              icon: Icon(
                                isSaved
                                    ? Icons.bookmark_added
                                    : Icons.bookmark_add_outlined,
                                size: 16,
                                color: isSaved ? Colors.grey : Colors.blue,
                              ),
                              label: Text(
                                isSaved ? '保存済み' : '保存フォルダに追加',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSaved ? Colors.grey : Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedImageBytes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      _selectedImageBytes!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('画像を添付中', style: TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _selectedImageBytes = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(8, 8, 8, canPop ? 12 : 96),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.blue,
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.blue,
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: '料理・掃除・節約など何でも相談...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: _isLoading ? null : () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupView() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text('AIサポートの初期設定'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'あなたの環境に合わせたアドバイスをするために、2つだけ教えてください！',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text(
              '1. お住まいの地域（都道府県など）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(
                hintText: '例：長野県、東京都など',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '2. 家に「ない」調理家電（複数選択可）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'チェックした家電を使わないレシピや生活術を提案します。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rawApp in _cookingAppliances)
                  FilterChip(
                    label: Text(rawApp.toString()),
                    selected: _missingAppliances.contains(rawApp.toString()),
                    selectedColor: Colors.orange.shade100,
                    onSelected: (selected) {
                      final app = rawApp.toString();
                      setState(() {
                        if (selected) {
                          _missingAppliances.add(app);
                        } else {
                          _missingAppliances.remove(app);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveSetupAndStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'この設定でAI相談をはじめる',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
