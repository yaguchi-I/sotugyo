import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'sns_detail_screen.dart' show SnsDetailScreen;
import '../widgets/top_toast.dart' show showReactionToast;

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;
  final Map? referencedPost;

  const AiChatScreen({super.key, this.initialPrompt, this.referencedPost});

  static const String apiKey =
      '';

  static const List fallbackModels = [
    'gemini-3.5-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash-lite',
    'gemini-2.5-flash',
    'gemini-3.5-flash',
  ];

  static const List presetAllergens = [
    '卵',
    '乳',
    '小麦',
    'えび',
    'かに',
    'そば',
    '落花生',
    'くるみ',
  ];

  static const Map allergenKeywordMap = {
    '卵': [
      '卵',
      'たまご',
      'タマゴ',
      '玉子',
      '卵黄',
      '卵白',
      'マヨネーズ',
      'オムライス',
      'オムレツ',
      '親子丼',
      '茶碗蒸し',
      'カルボナーラ',
      'タルタル',
      'プリン',
      'かに玉',
      '天津飯',
    ],
    '乳': [
      '牛乳',
      'ミルク',
      'チーズ',
      'バター',
      '生クリーム',
      'ヨーグルト',
      'ホワイトソース',
      'グラタン',
      'クリームシチュー',
      'クリームパスタ',
      '粉チーズ',
      'ピザ用チーズ',
      'スライスチーズ',
      'クリームチーズ',
      'コンデンスミルク',
      '練乳',
      'スキムミルク',
      'マーガリン',
      '乳製品',
    ],
    '小麦': [
      '小麦',
      '薄力粉',
      '強力粉',
      '中力粉',
      'パン粉',
      '食パン',
      'パン',
      'パスタ',
      'スパゲッティ',
      'マカロニ',
      'ペンネ',
      'うどん',
      'ラーメン',
      '中華麺',
      '焼きそば',
      'そうめん',
      'ひやむぎ',
      '天ぷら粉',
      'お好み焼き粉',
      'ホットケーキ',
      '餃子の皮',
      'ワンタン',
      'カレールー',
      'シチュールー',
      '醤油',
      'しょうゆ',
      'めんつゆ',
      'オイスターソース',
      'ウスターソース',
      '中濃ソース',
      'お好みソース',
      '麩',
    ],
    'えび': ['えび', 'エビ', '海老', 'シュリンプ', '桜えび', '干しえび', 'エビチリ', 'エビマヨ', 'むきえび'],
    'かに': ['かに', 'カニ', '蟹', 'カニカマ', 'かにかま', 'かに玉'],
    'そば': ['そば', 'ソバ', '蕎麦'],
    '落花生': ['落花生', 'ピーナッツ', 'ピーナツ', 'らっかせい', 'ジーマーミ'],
    'くるみ': ['くるみ', 'クルミ', '胡桃', 'ウォールナッツ', 'ミックスナッツ'],
  };

  static List findMatchedAllergens(String text, List allergies) {
    if (allergies.isEmpty || text.trim().isEmpty) return [];
    final List matched = [];
    final List lines = text.split('\n');

    for (final rawAllergen in allergies) {
      final allergen = rawAllergen.toString().trim();
      if (allergen.isEmpty) continue;
      final List keywords = allergenKeywordMap[allergen] is List
          ? List.from(allergenKeywordMap[allergen])
          : [allergen];

      bool hit = false;
      for (final rawLine in lines) {
        String line = rawLine.toString().toLowerCase();
        if (line.trim().isEmpty) continue;

        if (allergen == '小麦' &&
            (line.contains('小麦不使用') ||
                line.contains('グルテンフリー') ||
                line.contains('米粉'))) {
          continue;
        }
        if (allergen == '卵' &&
            (line.contains('卵不使用') || line.contains('卵なし'))) {
          continue;
        }
        if (allergen == '乳' &&
            (line.contains('乳不使用') ||
                line.contains('豆乳') && !line.contains('牛乳'))) {
          continue;
        }
        if (allergen == 'そば') {
          line = line
              .replaceAll('焼きそば', '')
              .replaceAll('やきそば', '')
              .replaceAll('中華そば', '')
              .replaceAll('油そば', '')
              .replaceAll('まぜそば', '')
              .replaceAll('沖縄そば', '')
              .replaceAll('かた焼きそば', '');
        }
        if (allergen == '乳') {
          line = line
              .replaceAll('豆乳', '')
              .replaceAll('ココナッツミルク', '')
              .replaceAll('アーモンドミルク', '')
              .replaceAll('オーツミルク', '');
        }

        for (final rawKw in keywords) {
          final kw = rawKw.toString().toLowerCase().trim();
          if (kw.isNotEmpty && line.contains(kw)) {
            hit = true;
            break;
          }
        }
        if (hit) break;
      }

      if (hit && !matched.contains(allergen)) {
        matched.add(allergen);
      }
    }
    return matched;
  }

  static bool containsAllergen(String text, List allergies) {
    return findMatchedAllergens(text, allergies).isNotEmpty;
  }

  static bool containsAllergenInRecipe({
    required String title,
    required List ingredients,
    required String steps,
    required List allergies,
  }) {
    if (allergies.isEmpty) return false;
    final buffer = StringBuffer();
    buffer.writeln(title);
    for (final rawIng in ingredients) {
      if (rawIng is Map) {
        buffer.writeln('${rawIng['name'] ?? ''}${rawIng['amount'] ?? ''}');
      } else {
        buffer.writeln(rawIng.toString());
      }
    }
    buffer.writeln(steps);
    return containsAllergen(buffer.toString(), allergies);
  }

  static String buildAllergyPromptRule(List allergies) {
    if (allergies.isEmpty) return '特になし';
    final List details = [];
    for (final raw in allergies) {
      final a = raw.toString().trim();
      if (a.isEmpty) continue;
      if (a == '卵') {
        details.add('卵（マヨネーズ・卵黄・卵白など卵由来加工品も含め厳禁）');
      } else if (a == '乳') {
        details.add('乳製品（牛乳・チーズ・バター・生クリーム・ヨーグルト・ホワイトソースも含め厳禁）');
      } else if (a == '小麦') {
        details.add(
          '小麦（小麦粉・パン・パン粉・パスタ・うどん・ラーメン・中華麺・カレールー・通常の醤油やめんつゆも含め厳禁。塩・ごま油・酢・小麦不使用調味料などで代用すること）',
        );
      } else if (a == 'えび') {
        details.add('えび（桜えび・干しえび等も含め厳禁）');
      } else if (a == 'かに') {
        details.add('かに（カニカマ等も含め厳禁）');
      } else if (a == 'そば') {
        details.add('そば（そば粉・蕎麦全般厳禁）');
      } else if (a == '落花生') {
        details.add('落花生・ピーナッツ全般厳禁');
      } else if (a == 'くるみ') {
        details.add('くるみ・ミックスナッツ類厳禁');
      } else {
        details.add('$a（関連加工品も含め厳禁）');
      }
    }
    return details.join('、');
  }

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
  final TextEditingController _customAllergyController =
      TextEditingController();
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
  final List _allergies = [];
  final List _blockedUsers = [];
  String _userArea = '';
  String _userName = 'あなた';
  String _activeModelName = AiChatScreen.fallbackModels.first.toString();

  final List _quickPrompts = [
    {'label': '🍲 鍋で作れる安い料理', 'prompt': '鍋で作れるあまり高くないおすすめの料理レシピを教えて！'},
    {
      'label': '🍳 150円以下のスピード飯',
      'prompt': '150円以下で10分以内に作れる、洗い物が少ない節約レシピを教えて！',
    },
    {'label': '🥬 余り物で1品作りたい', 'prompt': '冷蔵庫に余りがちな野菜とお肉で作れる、簡単なおかずレシピを教えて！'},
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
  final Map _savedDocIdByIndex = {};
  final Map _servingsByIndex = {};
  String _currentSessionId = '';
  bool _isLoading = false;
  String _loadingStatus = 'AIが回答を考えています...';
  Uint8List? _selectedImageBytes;

  static const Set _genericSearchWords = {
    '料理',
    'レシピ',
    '自炊',
    '簡単',
    '時短',
    '節約',
    '安い',
    '低予算',
    'コスパ',
    'おすすめ',
    '作り方',
    '食べ物',
    'ご飯',
    'ごはん',
    'おかず',
    '1品',
    '一品',
    '一人暮らし',
    '投稿',
    'みんな',
    '教えて',
    'スピード飯',
    '余り物',
    '洗い物',
    '掃除',
    '収納',
    '生活',
    'その他',
    'すべて',
  };

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

  String _formatScaledNumber(double val) {
    if ((val - val.round()).abs() < 0.05) {
      return val.round().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _scaleAmountString(
    String rawAmount,
    int baseServings,
    int targetServings,
  ) {
    if (baseServings <= 0 || baseServings == targetServings) {
      return rawAmount;
    }
    final double ratio = targetServings / baseServings;

    final fractionRegex = RegExp(r'(\d+)\s*/\s*(\d+)');
    if (fractionRegex.hasMatch(rawAmount)) {
      return rawAmount.replaceAllMapped(fractionRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '1') ?? 1;
        final den = double.tryParse(match.group(2) ?? '1') ?? 1;
        if (den == 0) return match.group(0) ?? '';
        return _formatScaledNumber((num / den) * ratio);
      });
    }

    final decimalRegex = RegExp(r'(\d+(?:\.\d+)?)');
    if (decimalRegex.hasMatch(rawAmount)) {
      return rawAmount.replaceAllMapped(decimalRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '0') ?? 0;
        return _formatScaledNumber(num * ratio);
      });
    }

    return '$rawAmount（×${_formatScaledNumber(ratio)}）';
  }

  void _addCustomAllergy() {
    final raw = _customAllergyController.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(RegExp(r'[\s 、,・/]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    setState(() {
      for (final p in parts) {
        if (!_allergies.contains(p)) {
          _allergies.add(p);
        }
      }
      _customAllergyController.clear();
    });
  }

  int _parsePostCostYen(Map post) {
    final est = AiKnowledgeService.readIntField(post['estimatedCost']);
    if (est > 0) return est;
    final raw = (post['recipeCost'] ?? '').toString().replaceAll(',', '');
    final match = RegExp(r'(\d+)').firstMatch(raw);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  int _inferMaxBudgetYen(String userQuery, Map? plan) {
    if (plan != null) {
      final plannedMax = int.tryParse('${plan['maxBudgetYen'] ?? -1}') ?? -1;
      if (plannedMax > 0) return plannedMax;
    }
    final normalized = userQuery.replaceAll(',', '');
    final explicitMatch = RegExp(r'(\d+)\s*円\s*(?:以下|以内|まで|くらい|程度)')
        .firstMatch(normalized);
    if (explicitMatch != null) {
      final parsed = int.tryParse(explicitMatch.group(1) ?? '0') ?? 0;
      if (parsed > 0) return parsed;
    }
    if (userQuery.contains('節約') ||
        userQuery.contains('安い') ||
        userQuery.contains('高くない') ||
        userQuery.contains('コスパ') ||
        userQuery.contains('激安') ||
        userQuery.contains('低予算')) {
      return 500;
    }
    return -1;
  }

  bool _isCandidateRelevant({
    required Map post,
    required String userQuery,
    required List searchTags,
    required int maxBudgetYen,
    required String preferredPriceTier,
    required String explicitDocId,
  }) {
    final docId = (post['docId'] ?? '').toString();
    if (docId.isEmpty) return false;
    if (explicitDocId.isNotEmpty && docId == explicitDocId) return true;

    if (_allergies.isNotEmpty) {
      final ingText = _toMapList(post['recipeIngredients'])
          .map((e) => '${(e as Map)['name'] ?? ''}${e['amount'] ?? ''}')
          .join('\n');
      final postAllergyTarget =
          '${post['title'] ?? ''}\n${post['content'] ?? ''}\n$ingText\n${post['recipeSteps'] ?? ''}';
      if (AiChatScreen.containsAllergen(postAllergyTarget, _allergies)) {
        return false;
      }
    }

    final int postCost = _parsePostCostYen(post);
    if (maxBudgetYen > 0 && postCost > 0) {
      final int allowedUpper = (maxBudgetYen * 1.3).round();
      if (postCost > allowedUpper) return false;
    }
    if (preferredPriceTier == 'low' && postCost >= 600) {
      return false;
    }

    final ingNames = _toMapList(post['recipeIngredients'])
        .map((e) => ((e as Map)['name'] ?? '').toString())
        .join(' ');
    final searchableText =
        '${post['title'] ?? ''}${post['content'] ?? ''} ${post['subCategory'] ?? ''}$ingNames'
            .toLowerCase();

    final List specificTags = [];
    for (final rawTag in searchTags) {
      final tag = rawTag.toString().trim();
      if (tag.length >= 2 && !_genericSearchWords.contains(tag)) {
        specificTags.add(tag.toLowerCase());
      }
    }

    if (specificTags.isNotEmpty) {
      final bool matchedAny = specificTags.any(
        (tag) => searchableText.contains(tag.toString()),
      );
      if (!matchedAny) return false;
    } else if (maxBudgetYen > 0 && postCost <= 0) {
      final String tier = (post['priceTier'] ?? 'none').toString();
      if (tier != 'low') return false;
    }

    return true;
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final season = _getSeason(now.month);
    final missingText = _missingAppliances.isEmpty
        ? '特になし'
        : _missingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(_allergies);
    final areaText = _userArea.isEmpty ? '日本' : _userArea;

    return 'あなたは一人暮らしの頼れる相談相手であり、料理・家事・節約の実践知識が豊富なAIパートナーです。\n'
        '相手：$_userNameさん / 時期：${now.year}年${now.month}月（$season） / 地域：$areaText / 持っていない家電：$missingText\n'
        'アレルギー・食べられない食材（絶対厳禁）：$allergyRule\n\n'
        '【最優先安全ルール（アレルギー厳禁）】\n'
        '・アレルギー・食べられない食材（$allergyRule）は、レシピの材料・調味料・アレンジ提案・代替案のいずれにも絶対に含めないこと。\n'
        '・もしユーザーがうっかりアレルギー食材を含む相談をした場合でも、その食材は使わず安全な代替食材だけで構成したレシピを提案すること。\n\n'
        '【話し方と基本ルール】\n'
        '・教科書の音読のような硬い解説や、「今回はレシピの相談ではないため〜」といったシステム説明は絶対に書かないこと。\n'
        '・「ぜひ試してみてくださいね！」のような毎回同じ定型締めは避け、相談に合った自然な一言で締めること。\n'
        '・持っていない家電（$missingText）を使う提案は絶対にしないこと。\n'
        '・Markdown記号（** や ## や ```）は一切使わないこと。\n\n'
        '【料理・食材・レシピ相談のときの必須フォーマット】\n'
        '・ユーザーが料理・献立・食材の使い道・レシピの話をしているときは、最初に親しみやすい1〜2文の導入を添えたうえで、必ず1人分のレシピを次の正確な見出し形式で出力すること（アプリがこの見出しを解析して人数計算・代用案ボタン付きレシピカードを表示するため）：\n'
        '【料理名】具体的な料理名\n'
        '【目安時間】約10分\n'
        '【目安費用】約180円\n'
        '【材料】\n'
        '・材料名 分量（例：・豚こま肉 100g のように材料名と分量を半角スペースで区切る。数値を含めること）\n'
        '・調味料名 分量\n'
        '【作り方】\n'
        '1. 手順1\n'
        '2. 手順2\n'
        '【ポイント】\n'
        '美味しく作るコツやアレンジの一言\n\n'
        '【料理以外の相談（掃除・収納・光熱費・雑談など）のとき】\n'
        '・上のレシピ見出しは使わず、自然な会話文や簡潔な箇条書きで答えること。\n\n'
        '【アプリ内投稿の厳格な扱い方】\n'
        '・メッセージ末尾に「参考候補（アプリ内投稿）」が添えられることがあるが、相談の予算・食材・ジャンル・目的に明確に一致する投稿だけを採用すること。\n'
        '・条件と合わない投稿（例：節約相談に対する高額な料理、材料や料理名が全く別の投稿、アレルギー食材を含む投稿）は完全に無視すること。\n'
        '・回答本文の中で実際に「〇〇さんの『△△』」のように投稿者名や投稿名に触れて紹介した場合に限り、回答のいちばん最後の行だけに [REF:docId] を出力すること（最大2件）。\n'
        '・回答本文の中で一度も紹介していない投稿の [REF:] は絶対に出力しないこと。該当がなければ [REF:] 行自体を書かないこと。';
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
      generationConfig: GenerationConfig(temperature: 0.7),
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
        final List savedAllergies = data['allergies'] is List
            ? List.from(data['allergies'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
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
          _allergies
            ..clear()
            ..addAll(savedAllergies);
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
                    'こんにちは、$_userNameさん！冷蔵庫の余り物や今日のご飯、掃除や節約の相談まで何でも気軽に聞いてくださいね。',
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
      _savedDocIdByIndex.clear();
      _servingsByIndex.clear();
      _messages
        ..clear()
        ..add({
          'role': 'ai',
          'text': '新しい相談ですね！余っている食材や作りたい料理、暮らしの疑問などそのまま聞いてください。',
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
                                                    _savedDocIdByIndex.clear();
                                                    _servingsByIndex.clear();
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

    if (_customAllergyController.text.trim().isNotEmpty) {
      _addCustomAllergy();
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
              'allergies': _allergies,
              'isAiSetupDone': true,
            }, SetOptions(merge: true));
      } catch (e) {}
    }

    if (!mounted) return;

    final allergyNote = _allergies.isEmpty
        ? ''
        : '（${_allergies.join('・')}を除外します）';

    setState(() {
      _isSetupComplete = true;
      _isCheckingSetup = false;
      if (_messages.isEmpty) {
        _messages.add({
          'role': 'ai',
          'text':
              '設定ありがとうございます！$_userAreaの環境や家電に合わせてお答えしますね$allergyNote。何でも聞いてください。',
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
    buffer.writeln('\n---');
    buffer.writeln(
      '参考候補（アプリ内投稿・条件に明確に一致し本文で紹介する場合のみ使用。無関係なら完全に無視し[REF:]も書かないこと）：',
    );
    for (int i = 0; i < posts.length; i++) {
      final p = posts[i] as Map;
      final docId = (p['docId'] ?? '').toString();
      final userName = (p['userName'] ?? '名無し').toString();
      final title = (p['title'] ?? '').toString();
      final content = (p['content'] ?? '').toString();
      final cost = (p['recipeCost'] ?? '').toString();
      final helpfuls = p['helpfuls'] ?? 0;
      final saves = p['saves'] ?? 0;
      final ingItems = _toMapList(p['recipeIngredients']);
      final ings = ingItems
          .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}'.trim())
          .join('、');
      buffer.writeln(
        '${i + 1}. [docId:$docId] $userName / ${p['mainCategory']} / 保存$saves・参考$helpfuls ${cost.isNotEmpty ? "($cost)" : ""}',
      );
      if (title.isNotEmpty) buffer.writeln('   タイトル: $title');
      if (content.isNotEmpty) buffer.writeln('   本文: $content');
      if (ings.isNotEmpty) buffer.writeln('   材料: $ings');
      final steps = (p['recipeSteps'] ?? '').toString();
      if (steps.isNotEmpty) buffer.writeln('   手順: $steps');
    }
    return buffer.toString();
  }

  bool _isMentionedInReply(String cleanReply, Map post) {
    final lowerReply = cleanReply.toLowerCase();
    final userName = (post['userName'] ?? '').toString().trim();
    final title = (post['title'] ?? '').toString().trim();

    if (userName.length >= 2 &&
        userName != '名無し' &&
        userName != 'ユーザー' &&
        lowerReply.contains(userName.toLowerCase())) {
      return true;
    }
    if (title.length >= 2 && lowerReply.contains(title.toLowerCase())) {
      return true;
    }
    return false;
  }

  Map _extractReferenceTag(
    String rawReply,
    List candidatePosts, {
    String explicitDocId = '',
  }) {
    final regex = RegExp(r'\[REF:([^\]]*)\]');
    final match = regex.firstMatch(rawReply);

    final fence = String.fromCharCodes([96, 96, 96]);
    final cleanText = rawReply
        .replaceAll(regex, '')
        .replaceAll(fence, '')
        .replaceAll('**', '')
        .replaceAll('##', '')
        .trim();

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
            final bool isExplicit =
                explicitDocId.isNotEmpty && id == explicitDocId;
            if (isExplicit || _isMentionedInReply(cleanText, p)) {
              selectedRefs.add(p);
            }
          }
        }
      }
    }

    if (selectedRefs.isEmpty && explicitDocId.isNotEmpty) {
      for (final rawP in candidatePosts) {
        final p = rawP as Map;
        if (p['docId'] == explicitDocId) {
          selectedRefs.add(p);
          break;
        }
      }
    }

    return {
      'cleanText': cleanText,
      'referencedPosts': selectedRefs.take(2).toList(),
    };
  }

  Future _generateReplyWithFallback({
    required String prompt,
    Uint8List? imageBytes,
    required String rawText,
  }) async {
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
              ? 'この画像を見て、食材ならおすすめレシピを【料理名】【目安時間】【目安費用】【材料】【作り方】【ポイント】の形式で、汚れや日用品なら実践的な対処法を自然な言葉で教えてください。'
              : prompt;
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
              .sendMessage(Content.text(prompt))
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

    return {'reply': aiReply, 'error': lastError};
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
          'text': 'APIキーがまだ設定されていません。\nai_chat_screen.dart の19行目にある apiKey にキーを貼り付けて保存してください。',
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
      _loadingStatus = '🔍 相談内容を整理しています...';
    });
    _scrollToBottom();

    final String explicitDocId = explicitContextPost != null
        ? (explicitContextPost['docId'] ?? '').toString()
        : '';
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
              _loadingStatus = '📚 関連するみんなの投稿を確認しています...';
            });
          }

          final List planTags = rawPlan['searchTags'] is List
              ? List.from(rawPlan['searchTags'])
              : const [];
          final String preferredPriceTier =
              (rawPlan['preferredPriceTier'] ?? 'any').toString();
          final int maxBudgetYen = _inferMaxBudgetYen(rawText, rawPlan);

          final rawFound =
              await AiKnowledgeService.searchRelevantCommunityPosts(
                searchTags: planTags,
                category: (rawPlan['category'] ?? 'すべて').toString(),
                preferredPriceTier: preferredPriceTier,
                maxBudgetYen: maxBudgetYen,
                missingAppliances: _missingAppliances,
                currentUserId: _currentUserId,
                blockedUsers: _blockedUsers,
                topK: 4,
              );

          if (rawFound is List) {
            for (final item in rawFound) {
              if (item is Map &&
                  !retrievedPosts.any(
                    (e) => (e as Map)['docId'] == item['docId'],
                  ) &&
                  _isCandidateRelevant(
                    post: item,
                    userQuery: rawText,
                    searchTags: planTags,
                    maxBudgetYen: maxBudgetYen,
                    preferredPriceTier: preferredPriceTier,
                    explicitDocId: explicitDocId,
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
        _loadingStatus = '✨ 回答を考えています...';
      });
    }

    final String communityContext = _formatCommunityPostsForPrompt(
      retrievedPosts,
    );
    final String allergyReminder = _allergies.isEmpty
        ? ''
        : '\n（※重要：アレルギー設定により【${AiChatScreen.buildAllergyPromptRule(_allergies)}】は絶対に使用禁止です）';
    final String finalPrompt = '$rawText$allergyReminder$communityContext';

    Map genResult = await _generateReplyWithFallback(
      prompt: finalPrompt,
      imageBytes: imageBytes,
      rawText: rawText,
    );

    String? aiReply = genResult['reply'] as String?;
    Object? lastError = genResult['error'];

    if (aiReply != null && _allergies.isNotEmpty) {
      final parsedCheck = _parseAiSuggestion(aiReply);
      if (parsedCheck['isRecipe'] == true &&
          AiChatScreen.containsAllergenInRecipe(
            title: (parsedCheck['title'] ?? '').toString(),
            ingredients: parsedCheck['ingredients'] is List
                ? List.from(parsedCheck['ingredients'])
                : const [],
            steps: (parsedCheck['steps'] ?? '').toString(),
            allergies: _allergies,
          )) {
        if (mounted) {
          setState(() {
            _loadingStatus = '🛡️ アレルギー食材を除外してレシピを再作成しています...';
          });
        }
        final retryPrompt =
            '直前の提案にアレルギー対象食材（${AiChatScreen.buildAllergyPromptRule(_allergies)}）が含まれていました。'
            'それらおよび関連加工品・調味料を一切使わず、安全な食材だけで先ほどの相談（$rawText）に合う別レシピを【料理名】【目安時間】【目安費用】【材料】【作り方】【ポイント】の形式で作り直してください。';
        final retryRes = await _generateReplyWithFallback(
          prompt: retryPrompt,
          rawText: retryPrompt,
        );
        if (retryRes['reply'] is String) {
          aiReply = retryRes['reply'] as String;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (aiReply != null) {
        final extracted = _extractReferenceTag(
          aiReply,
          retrievedPosts,
          explicitDocId: explicitDocId,
        );
        String finalText = (extracted['cleanText'] ?? '').toString();
        final parsedFinal = _parseAiSuggestion(finalText);
        if (_allergies.isNotEmpty &&
            parsedFinal['isRecipe'] == true &&
            AiChatScreen.containsAllergenInRecipe(
              title: (parsedFinal['title'] ?? '').toString(),
              ingredients: parsedFinal['ingredients'] is List
                  ? List.from(parsedFinal['ingredients'])
                  : const [],
              steps: (parsedFinal['steps'] ?? '').toString(),
              allergies: _allergies,
            )) {
          finalText =
              '設定中のアレルギー食材（${_allergies.join('・')}）を含むレシピが生成されたため表示をブロックしました。使いたい安全な食材を指定してもう一度聞いてみてください。';
        }
        _messages.add({
          'role': 'ai',
          'text': finalText,
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
        (text.contains('【材料') || text.contains('【作り方') || text.contains('【手順'));

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
        'intro': text,
        'outro': '',
        'title': summaryTitle,
        'subCategory': '節約術',
        'time': '',
        'cost': '',
        'ingredients': [],
        'steps': '',
      };
    }

    String title = 'AI提案レシピ';
    String time = '';
    String cost = '';
    final List introLines = [];
    final List outroLines = [];
    final List ingredientsData = [];
    final List stepsLines = [];

    final lines = text.split('\n');
    String section = 'intro';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        if (section == 'intro' && introLines.isNotEmpty) {
          introLines.add('');
        } else if (section == 'outro' && outroLines.isNotEmpty) {
          outroLines.add('');
        }
        continue;
      }

      if (line.startsWith('【料理名】')) {
        section = 'title';
        final val = line.replaceFirst('【料理名】', '').trim();
        if (val.isNotEmpty) title = val;
        continue;
      }
      if (line.startsWith('【目安時間・費用】')) {
        section = 'meta';
        final val = line.replaceFirst('【目安時間・費用】', '').trim();
        final parts = val.split(RegExp(r'[/／・]'));
        if (parts.isNotEmpty) time = parts[0].trim();
        if (parts.length > 1) cost = parts[1].trim();
        continue;
      }
      if (line.startsWith('【目安時間】')) {
        section = 'time';
        final val = line.replaceFirst('【目安時間】', '').trim();
        if (val.isNotEmpty) time = val;
        continue;
      }
      if (line.startsWith('【目安費用】')) {
        section = 'cost';
        final val = line.replaceFirst('【目安費用】', '').trim();
        if (val.isNotEmpty) cost = val;
        continue;
      }
      if (line.startsWith('【材料')) {
        section = 'ing';
        continue;
      }
      if (line.startsWith('【作り方') || line.startsWith('【手順')) {
        section = 'step';
        continue;
      }
      if (line.startsWith('【ポイント') ||
          line.startsWith('【コツ') ||
          line.startsWith('【ひとこと') ||
          line.startsWith('【アレンジ')) {
        section = 'outro';
        final after = line.replaceFirst(RegExp(r'^【[^】]*】'), '').trim();
        if (after.isNotEmpty) outroLines.add(after);
        continue;
      }

      if (section == 'intro') {
        introLines.add(line);
      } else if (section == 'title') {
        title = line;
        section = 'meta';
      } else if (section == 'time') {
        time = line;
        section = 'meta';
      } else if (section == 'cost') {
        cost = line;
        section = 'meta';
      } else if (section == 'ing') {
        final clean = line.replaceFirst(RegExp(r'^[・\-*•]\s*'), '').trim();
        if (clean.isEmpty) continue;
        String name = clean;
        String amount = '適量';
        if (clean.contains('：') || clean.contains(':')) {
          final sp = clean.split(RegExp(r'[:：]'));
          name = sp.first.trim();
          final rest = sp.sublist(1).join(':').trim();
          if (rest.isNotEmpty) amount = rest;
        } else {
          final sp = clean.split(RegExp(r'[\s ]+'));
          if (sp.length >= 2) {
            amount = sp.last.trim();
            name = sp.sublist(0, sp.length - 1).join(' ').trim();
          }
        }
        if (name.isNotEmpty) {
          ingredientsData.add({'name': name, 'amount': amount});
        }
      } else if (section == 'step') {
        stepsLines.add(line);
      } else if (section == 'outro') {
        outroLines.add(line);
      }
    }

    return {
      'isRecipe': ingredientsData.isNotEmpty || stepsLines.isNotEmpty,
      'intro': introLines.join('\n').trim(),
      'outro': outroLines.join('\n').trim(),
      'title': title,
      'subCategory': 'レシピ',
      'time': time.isNotEmpty ? time : '約10分',
      'cost': cost.isNotEmpty ? cost : '約200円',
      'ingredients': ingredientsData,
      'steps': stepsLines.join('\n'),
    };
  }

  Future _askAiSubstitution({
    required String dishTitle,
    required List allIngredients,
    String? targetIngredient,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('APIキーを設定してください')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AIが代用・アレンジ案を考えています...')),
          ],
        ),
      ),
    );

    final ingNames = allIngredients
        .where((e) => e is Map)
        .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}'.trim())
        .join('、');
    final missingText = _missingAppliances.isEmpty
        ? '特になし'
        : _missingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(_allergies);

    final prompt = targetIngredient != null
        ? '料理「$dishTitle」（材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$dishTitle」（材料：$ingNames）について、\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、さらに安く手軽に作れる代替食材やアレンジのコツを200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String replyText = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelName in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelName.toString(),
          apiKey: currentKey,
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          replyText = res.text!
              .replaceAll('**', '')
              .replaceAll('##', '')
              .trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetIngredient != null
                    ? '「$targetIngredient」の代用案'
                    : '「$dishTitle」のAI代替提案',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            replyText,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future _toggleSaveAiSuggestion(int index, String suggestionText) async {
    if (_currentUserId.isEmpty) return;

    final existingDocId = _savedDocIdByIndex[index]?.toString() ?? '';
    if (existingDocId.isNotEmpty) {
      setState(() {
        _savedDocIdByIndex.remove(index);
      });
      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(existingDocId)
            .delete();
        if (mounted) {
          showReactionToast(context, 'savedUsers', added: false);
        }
      } catch (e) {}
      return;
    }

    final parsed = _parseAiSuggestion(suggestionText);
    final bool isRecipe = parsed['isRecipe'] == true;
    final String title = parsed['title'].toString();
    final String subCategory = parsed['subCategory'].toString();

    setState(() {
      _savedDocIdByIndex[index] = 'pending';
    });

    try {
      final docRef = await FirebaseFirestore.instance.collection('posts').add({
        'userId': _currentUserId,
        'userName': 'AIアドバイザー',
        'mainCategory': 'AI',
        'subCategory': subCategory,
        'title': title,
        'content': suggestionText,
        'hasImage': false,
        'imageBase64': '',
        'imagesBase64': [],
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

      if (!mounted) return;
      setState(() {
        _savedDocIdByIndex[index] = docRef.id;
      });
      showReactionToast(context, 'savedUsers', added: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savedDocIdByIndex.remove(index);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    }
  }

  Widget _buildInlineRecipeCard(int messageIndex, Map parsed) {
    final String title = (parsed['title'] ?? 'AI提案レシピ').toString();
    final String recipeTime = (parsed['time'] ?? '').toString();
    final String rawCost = (parsed['cost'] ?? '').toString();
    final List ingredients = parsed['ingredients'] is List
        ? List.from(parsed['ingredients'])
        : [];
    final String steps = (parsed['steps'] ?? '').toString();

    final int currentServings = (_servingsByIndex[messageIndex] as int?) ?? 1;
    final String scaledCost = _scaleAmountString(rawCost, 1, currentServings);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.restaurant_menu, size: 18, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _askAiSubstitution(
                  dishTitle: title,
                  allIngredients: ingredients,
                ),
                icon: const Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: Colors.orange,
                ),
                label: const Text(
                  'AI代替提案',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (recipeTime.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 15, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text(recipeTime, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              if (scaledCost.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 15,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$scaledCost（$currentServings人分）',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (ingredients.isNotEmpty) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '材料（$currentServings人分）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      onPressed: currentServings > 1
                          ? () {
                              setState(() {
                                _servingsByIndex[messageIndex] =
                                    currentServings - 1;
                              });
                            }
                          : null,
                    ),
                    Text(
                      '$currentServings人分',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      onPressed: currentServings < 6
                          ? () {
                              setState(() {
                                _servingsByIndex[messageIndex] =
                                    currentServings + 1;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final rawIng in ingredients)
              Builder(
                builder: (_) {
                  final ingMap = rawIng as Map;
                  final name = (ingMap['name'] ?? '').toString();
                  final rawAmt = (ingMap['amount'] ?? '').toString();
                  final scaledAmt = _scaleAmountString(
                    rawAmt,
                    1,
                    currentServings,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '・$name : $scaledAmt',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _askAiSubstitution(
                            dishTitle: title,
                            allIngredients: ingredients,
                            targetIngredient: name,
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'AI代用案',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '作り方',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(steps, style: const TextStyle(fontSize: 13, height: 1.45)),
          ],
          if (_allergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '※除外設定（${_allergies.join('・')}）を反映済み。市販の調味料・加工品は必ず成分表示をご確認ください。',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade900),
            ),
          ],
        ],
      ),
    );
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
    _customAllergyController.dispose();
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
            tooltip: '地域・家電・アレルギー設定',
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
          if (_allergies.isNotEmpty)
            InkWell(
              onTap: () {
                setState(() {
                  _isSetupComplete = false;
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(
                      Icons.no_food_outlined,
                      size: 15,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'アレルギー除外中: ${_allergies.join('・')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                    Text(
                      '変更',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                final bool isSaved = _savedDocIdByIndex.containsKey(index);
                final Map parsed = !isUser
                    ? _parseAiSuggestion(text)
                    : {'isRecipe': false};
                final bool isRecipeMsg = !isUser && parsed['isRecipe'] == true;
                final String introText = (parsed['intro'] ?? '').toString();
                final String outroText = (parsed['outro'] ?? '').toString();

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.88,
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
                        if (isRecipeMsg) ...[
                          if (introText.isNotEmpty)
                            Text(
                              introText,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          _buildInlineRecipeCard(index, parsed),
                          if (outroText.isNotEmpty)
                            Text(
                              outroText,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                        ] else
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
                            '📌 関連するみんなの投稿',
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
                              onPressed: () =>
                                  _toggleSaveAiSuggestion(index, text),
                              icon: Icon(
                                isSaved
                                    ? Icons.bookmark
                                    : Icons.bookmark_add_outlined,
                                size: 17,
                                color: Colors.blue,
                              ),
                              label: Text(
                                isSaved
                                    ? '保存フォルダに保存済み（解除）'
                                    : (isRecipeMsg
                                          ? 'このレシピを保存フォルダへ'
                                          : '保存フォルダに追加'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
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
                        hintText: '余り物・レシピ・掃除・節約など何でも相談...',
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
    final List customAllergies = _allergies
        .where((a) => !AiChatScreen.presetAllergens.contains(a))
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text('AIサポートの設定'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'あなたの環境に合わせて安全に提案するため、設定してください！',
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
            const SizedBox(height: 24),
            const Text(
              '3. アレルギー・食べられない食材（任意・複数選択可）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '選択・追加した食材を含むレシピは、AI相談でもレシピ提案でも自動で除外されます。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rawAllergen in AiChatScreen.presetAllergens)
                  FilterChip(
                    label: Text(rawAllergen.toString()),
                    selected: _allergies.contains(rawAllergen.toString()),
                    selectedColor: Colors.red.shade100,
                    checkmarkColor: Colors.red.shade800,
                    onSelected: (selected) {
                      final allergen = rawAllergen.toString();
                      setState(() {
                        if (selected) {
                          if (!_allergies.contains(allergen)) {
                            _allergies.add(allergen);
                          }
                        } else {
                          _allergies.remove(allergen);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customAllergyController,
                    decoration: const InputDecoration(
                      hintText: 'その他のアレルギー・苦手食材（例：大豆、ごま、さば）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addCustomAllergy(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addCustomAllergy,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            if (customAllergies.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final rawCustom in customAllergies)
                    InputChip(
                      label: Text(
                        rawCustom.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                        ),
                      ),
                      backgroundColor: Colors.red.shade50,
                      deleteIconColor: Colors.red.shade700,
                      onDeleted: () {
                        setState(() {
                          _allergies.remove(rawCustom.toString());
                        });
                      },
                    ),
                ],
              ),
            ],
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
