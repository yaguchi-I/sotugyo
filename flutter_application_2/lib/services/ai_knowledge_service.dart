import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../screens/ai_chat_screen.dart';

class AiKnowledgeService {
  static const List _genericStopTags = [
    '料理',
    '自炊',
    'レシピ',
    '節約',
    '低予算',
    'コスパ',
    'コスパ良し',
    '安い',
    '時短',
    '簡単',
    '一人暮らし',
    'おすすめ',
    '掃除',
    '収納',
    'その他',
    '指定なし',
    '美味しい',
    'おいしい',
    '便利',
    '100均',
    'メインおかず',
    'おかず',
    'ご飯',
    'ごはん',
  ];

  static double calculateValueScore({
    required int likes,
    required int helpfuls,
    required int saves,
    required int replies,
    required int impressions,
  }) {
    final safeLikes = likes < 0 ? 0 : likes;
    final safeHelpfuls = helpfuls < 0 ? 0 : helpfuls;
    final safeSaves = saves < 0 ? 0 : saves;
    final safeReplies = replies < 0 ? 0 : replies;
    final safeImpressions = impressions < 0 ? 0 : impressions;

    final int totalReactions =
        safeLikes + safeHelpfuls + safeSaves + safeReplies;
    final int effectiveViews = max(safeImpressions, totalReactions);

    final double weighted =
        (safeSaves * 5 + safeHelpfuls * 4 + safeReplies * 2 + safeLikes)
            .toDouble();

    final double rateScore = min(
      (weighted / (effectiveViews + 20.0)) * 10.0,
      50.0,
    );
    final double volumeScore = min(log(1.0 + weighted) * 5.0, 50.0);
    final double total = min(rateScore + volumeScore, 100.0);

    return double.parse(total.toStringAsFixed(2));
  }

  static int readIntField(dynamic rawValue, [int fallback = 0]) {
    if (rawValue is num) {
      final v = rawValue.toInt();
      return v < 0 ? 0 : v;
    }
    if (rawValue != null) {
      final parsed = int.tryParse(rawValue.toString().trim());
      if (parsed != null) {
        return parsed < 0 ? 0 : parsed;
      }
    }
    return fallback < 0 ? 0 : fallback;
  }

  static int parseEstimatedCost(String rawCostText) {
    final normalized = rawCostText
        .replaceAll(',', '')
        .replaceAll('，', '')
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9');
    final match = RegExp(r'(\d+)').firstMatch(normalized);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '-1') ?? -1;
    }
    return -1;
  }

  static String inferPriceTierFromCost(int cost) {
    if (cost < 0) return 'none';
    if (cost <= 300) return 'low';
    if (cost <= 700) return 'medium';
    return 'high';
  }

  static List buildImmediateFallbackTags({
    required String mainCategory,
    required String subCategory,
    required String title,
    required String content,
    required List ingredients,
    required int estimatedCost,
  }) {
    final Set tags = Set();

    if (mainCategory.isNotEmpty && mainCategory != '指定なし') {
      tags.add(mainCategory);
    }
    if (subCategory.isNotEmpty && subCategory != '指定なし') {
      tags.add(subCategory);
    }
    if (title.trim().isNotEmpty) {
      tags.add(title.trim());
    }

    for (final ing in ingredients) {
      if (ing is Map) {
        final name = (ing['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          tags.add(name);
        }
      }
    }

    final combined = '$title $content';
    final tokens = combined
        .split(RegExp(r'[\s 、。・,./!！?？\n「」『』()（）]+'))
        .map((e) => e.trim())
        .where((e) => e.length >= 2 && e.length <= 14);
    for (final token in tokens) {
      tags.add(token);
      if (tags.length >= 16) break;
    }

    if (estimatedCost >= 0 && estimatedCost <= 300) {
      tags.addAll(['節約', '低予算', 'コスパ']);
    }

    return tags.take(20).toList();
  }

  static Map? _extractJsonObject(String rawText) {
    final fence = String.fromCharCodes([96, 96, 96]);
    final cleaned = rawText
        .replaceAll('${fence}json', '')
        .replaceAll(fence, '')
        .trim();
    final startIdx = cleaned.indexOf('{');
    final endIdx = cleaned.lastIndexOf('}');
    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) {
      return null;
    }
    try {
      final decoded = jsonDecode(cleaned.substring(startIdx, endIdx + 1));
      if (decoded is Map) {
        return Map.from(decoded);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future _generateWithFallback({
    required String prompt,
    List images = const [],
    double temperature = 0.0,
    int timeoutSeconds = 20,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      return null;
    }

    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
          generationConfig: GenerationConfig(temperature: temperature),
        );

        final response = await model
            .generateContent([
              Content.multi([
                TextPart(prompt),
                for (final img in images.take(2))
                  DataPart('image/jpeg', img as Uint8List),
              ]),
            ])
            .timeout(Duration(seconds: timeoutSeconds));

        if (response.text != null && response.text!.trim().isNotEmpty) {
          return response.text!.trim();
        }
      } catch (e) {}
    }
    return null;
  }

  static Future analyzePostForDatabase({
    required String mainCategory,
    required String subCategory,
    required String title,
    required String content,
    required bool isRecipePost,
    required String recipeCostText,
    required String recipeTimeText,
    required List ingredients,
    required String recipeSteps,
    List images = const [],
  }) async {
    final parsedCost = parseEstimatedCost(recipeCostText);
    final fallbackTags = buildImmediateFallbackTags(
      mainCategory: mainCategory,
      subCategory: subCategory,
      title: title,
      content: content,
      ingredients: ingredients,
      estimatedCost: parsedCost,
    );
    final fallbackTier = inferPriceTierFromCost(parsedCost);

    final ingText = ingredients
        .where((e) => e is Map)
        .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .join('、');

    final prompt =
        'あなたは一人暮らし向けSNSのデータベース索引エンジンです。\n'
        '以下の投稿（通常のつぶやきも含む）を解析し、ユーザーがAI相談で検索したときに「暗黙の条件（書いていない調理法の応用、おおよその価格帯、具体的な悩み）」でもヒットするように、必ずJSON形式のみで出力してください。\n\n'
        '【投稿データ】\n'
        'カテゴリ: $mainCategory / $subCategory\n'
        'レシピ形式: $isRecipePost\n'
        'タイトル: $title\n'
        '本文: $content\n'
        '目安費用: $recipeCostText / 調理時間: $recipeTimeText\n'
        '材料: $ingText\n'
        '手順: $recipeSteps\n\n'
        '【推論ルール】\n'
        '1. aiTags: 12〜20個の具体的な日本語キーワード配列。「一人暮らし」「おすすめ」「便利」のような曖昧な語は入れず、具体的な食材・料理名・調理法・器具・場所・汚れの種類を中心に展開する。\n'
        '   例: 「春キャベツの肉巻きが美味しかった」→ ["春キャベツ", "キャベツ", "豚肉", "肉巻き", "旬", "鍋", "鍋料理", "煮込み", "蒸し料理", "フライパン", "節約", "低予算"]\n'
        '   例: 「重曹とクエン酸でシンクのぬめり消えた」→ ["重曹", "クエン酸", "シンク", "キッチン", "排水口", "ぬめり", "臭い対策", "つけ置き"]\n'
        '2. priceTier: "low"（〜300円前後・節約向け）, "medium"（300〜700円）, "high"（700円以上）, "none"（費用無関係）のいずれか。\n'
        '3. estimatedCost: 1人分または1回分の推定金額（整数・円）。全く推定できない場合のみ -1。\n'
        '4. usedAppliances: この内容を実行するのに必須の調理家電のみ次から選択 ["電子レンジ", "オーブン", "炊飯器", "トースター", "コンロ(2口以上)", "ミキサー", "冷蔵庫"]。必須でなければ空配列 []。\n'
        '5. summaryForAi: この投稿の要点を80文字以内で1行要約する。\n\n'
        '【出力JSONフォーマット（説明文なし・JSONのみ）】\n'
        '{"aiTags": ["..."], "priceTier": "low", "estimatedCost": 200, "usedAppliances": [], "summaryForAi": "..."}';

    final rawReply = await _generateWithFallback(
      prompt: prompt,
      images: images,
      temperature: 0.0,
      timeoutSeconds: 20,
    );

    if (rawReply == null) {
      return {
        'aiTags': fallbackTags,
        'priceTier': fallbackTier,
        'estimatedCost': parsedCost,
        'usedAppliances': [],
        'summaryForAi': title.isNotEmpty ? title : content,
      };
    }

    final parsed = _extractJsonObject(rawReply.toString());
    if (parsed == null) {
      return {
        'aiTags': fallbackTags,
        'priceTier': fallbackTier,
        'estimatedCost': parsedCost,
        'usedAppliances': [],
        'summaryForAi': title.isNotEmpty ? title : content,
      };
    }

    final Set mergedTags = Set();
    if (parsed['aiTags'] is List) {
      for (final item in List.from(parsed['aiTags'])) {
        final t = item.toString().trim();
        if (t.isNotEmpty && t.length <= 16) {
          mergedTags.add(t);
        }
      }
    }
    for (final ft in fallbackTags) {
      if (mergedTags.length >= 24) break;
      mergedTags.add(ft.toString());
    }

    String priceTier = (parsed['priceTier'] ?? fallbackTier).toString().trim();
    if (!const ['low', 'medium', 'high', 'none'].contains(priceTier)) {
      priceTier = fallbackTier;
    }

    int finalCost = parsedCost;
    if (finalCost < 0 && parsed['estimatedCost'] != null) {
      final aiCost = int.tryParse(parsed['estimatedCost'].toString()) ?? -1;
      if (aiCost >= 0) {
        finalCost = aiCost;
      }
    }

    const List allowedAppliances = [
      '電子レンジ',
      'オーブン',
      '炊飯器',
      'トースター',
      'コンロ(2口以上)',
      'ミキサー',
      '冷蔵庫',
    ];
    final List usedAppliances = [];
    if (parsed['usedAppliances'] is List) {
      for (final item in List.from(parsed['usedAppliances'])) {
        final s = item.toString().trim();
        if (allowedAppliances.contains(s) && !usedAppliances.contains(s)) {
          usedAppliances.add(s);
        }
      }
    }

    final summaryForAi = (parsed['summaryForAi'] ?? '').toString().trim();

    return {
      'aiTags': mergedTags.take(24).toList(),
      'priceTier': priceTier,
      'estimatedCost': finalCost,
      'usedAppliances': usedAppliances,
      'summaryForAi': summaryForAi.isNotEmpty
          ? summaryForAi
          : (title.isNotEmpty ? title : content),
    };
  }

  static Future enrichPostMetadataInBackground({
    required String docId,
    required String mainCategory,
    required String subCategory,
    required String title,
    required String content,
    required bool isRecipePost,
    required String recipeCostText,
    required String recipeTimeText,
    required List ingredients,
    required String recipeSteps,
    List images = const [],
  }) async {
    try {
      final meta = await analyzePostForDatabase(
        mainCategory: mainCategory,
        subCategory: subCategory,
        title: title,
        content: content,
        isRecipePost: isRecipePost,
        recipeCostText: recipeCostText,
        recipeTimeText: recipeTimeText,
        ingredients: ingredients,
        recipeSteps: recipeSteps,
        images: images,
      );

      await FirebaseFirestore.instance.collection('posts').doc(docId).update({
        'aiTags': meta['aiTags'],
        'priceTier': meta['priceTier'],
        'estimatedCost': meta['estimatedCost'],
        'usedAppliances': meta['usedAppliances'],
        'summaryForAi': meta['summaryForAi'],
        'isAiIndexed': true,
      });
    } catch (e) {}
  }

  static Future extractSearchPlan({
    required String userQuery,
    List missingAppliances = const [],
  }) async {
    final prompt =
        'あなたは一人暮らし向けSNSの検索プランナーです。\n'
        'ユーザーの相談文から、SNS内の投稿を検索するための条件をJSON形式のみで出力してください。\n\n'
        'ユーザーの相談: $userQuery\n'
        '持っていない家電: ${missingAppliances.isEmpty ? "なし" : missingAppliances.join("、")}\n\n'
        '【出力ルール】\n'
        '1. needsSearch: 挨拶・雑談・一般知識の質問なら false。料理・食材・掃除・収納・生活の工夫を探すと役立つ場合のみ true。\n'
        '2. category: 明確に絞れるなら "料理", "掃除", "収納" のいずれか。複数ジャンルにまたがるなら "すべて"。\n'
        '3. searchTags: 具体的な名詞（食材・料理名・調理器具・場所・汚れの種類・収納アイテム）を8〜18個。絶対に「料理」「自炊」「節約」「おすすめ」「一人暮らし」「簡単」「便利」などの抽象的すぎる語は含めないこと。\n'
        '   例: 「鍋でつくれるあまり高くない料理」→ ["鍋", "鍋料理", "煮込み", "キャベツ", "春キャベツ", "豚肉", "肉巻き", "ミルフィーユ鍋", "もやし", "豆腐", "うどん", "スープ"]\n'
        '   例: 「刺身が余った」→ ["刺身", "漬け丼", "海鮮丼", "魚", "ヅケ", "なめろう", "カルパッチョ"]\n'
        '4. preferredPriceTier: 安さ・節約を求めているなら "low"、指定なければ "any"。\n'
        '5. maxBudgetYen: 具体的な金額上限（例: 200円以下→200）があれば整数、なければ -1。\n\n'
        '【出力JSONフォーマット（説明文なし・JSONのみ）】\n'
        '{"needsSearch": true, "category": "料理", "searchTags": ["..."], "preferredPriceTier": "low", "maxBudgetYen": -1}';

    final rawReply = await _generateWithFallback(
      prompt: prompt,
      temperature: 0.0,
      timeoutSeconds: 12,
    );

    final List localTokens = userQuery
        .split(RegExp(r'[\s 、。・,./!！?？\n]+'))
        .map((e) => e.trim())
        .where(
          (e) =>
              e.length >= 2 && e.length <= 14 && !_genericStopTags.contains(e),
        )
        .toList();

    if (rawReply == null) {
      return {
        'needsSearch': localTokens.isNotEmpty,
        'category': 'すべて',
        'searchTags': localTokens.take(18).toList(),
        'preferredPriceTier': 'any',
        'maxBudgetYen': -1,
      };
    }

    final parsed = _extractJsonObject(rawReply.toString());
    if (parsed == null) {
      return {
        'needsSearch': localTokens.isNotEmpty,
        'category': 'すべて',
        'searchTags': localTokens.take(18).toList(),
        'preferredPriceTier': 'any',
        'maxBudgetYen': -1,
      };
    }

    final Set tags = Set();
    if (parsed['searchTags'] is List) {
      for (final item in List.from(parsed['searchTags'])) {
        final s = item.toString().trim();
        if (s.isNotEmpty && !_genericStopTags.contains(s)) {
          tags.add(s);
        }
      }
    }
    for (final lt in localTokens) {
      if (tags.length >= 20) break;
      tags.add(lt.toString());
    }

    return {
      'needsSearch': parsed['needsSearch'] == true && tags.isNotEmpty,
      'category': (parsed['category'] ?? 'すべて').toString(),
      'searchTags': tags.take(20).toList(),
      'preferredPriceTier': (parsed['preferredPriceTier'] ?? 'any').toString(),
      'maxBudgetYen': int.tryParse('${parsed['maxBudgetYen'] ?? -1}') ?? -1,
    };
  }

  static Map _toLightweightPost(String docId, Map raw) {
    final likedUsers = raw['likedUsers'] is List
        ? List.from(raw['likedUsers'])
        : const [];
    final helpfulUsers = raw['helpfulUsers'] is List
        ? List.from(raw['helpfulUsers'])
        : const [];
    final savedUsers = raw['savedUsers'] is List
        ? List.from(raw['savedUsers'])
        : const [];

    final likes = max(readIntField(raw['likes']), likedUsers.length);
    final helpfuls = max(readIntField(raw['helpfuls']), helpfulUsers.length);
    final saves = max(readIntField(raw['saves']), savedUsers.length);
    final replies = readIntField(raw['replies']);
    final impressions = readIntField(raw['impressions']);

    final computedScore = calculateValueScore(
      likes: likes,
      helpfuls: helpfuls,
      saves: saves,
      replies: replies,
      impressions: impressions,
    );

    return {
      'docId': docId,
      'userId': (raw['userId'] ?? '').toString(),
      'userName': (raw['userName'] ?? '名無し').toString(),
      'mainCategory': (raw['mainCategory'] ?? '指定なし').toString(),
      'subCategory': (raw['subCategory'] ?? '指定なし').toString(),
      'title': (raw['title'] ?? '').toString(),
      'content': (raw['content'] ?? '').toString(),
      'summaryForAi': (raw['summaryForAi'] ?? '').toString(),
      'isRecipePost': raw['isRecipePost'] == true,
      'recipeCost': (raw['recipeCost'] ?? '').toString(),
      'recipeTime': (raw['recipeTime'] ?? '').toString(),
      'recipeServings': readIntField(raw['recipeServings'], 1),
      'recipeIngredients': raw['recipeIngredients'] is List
          ? List.from(raw['recipeIngredients'])
          : const [],
      'recipeSteps': (raw['recipeSteps'] ?? '').toString(),
      'aiTags': raw['aiTags'] is List
          ? List.from(raw['aiTags']).map((e) => e.toString()).toList()
          : [],
      'priceTier': (raw['priceTier'] ?? 'none').toString(),
      'estimatedCost': raw['estimatedCost'] is num
          ? (raw['estimatedCost'] as num).toInt()
          : parseEstimatedCost((raw['recipeCost'] ?? '').toString()),
      'usedAppliances': raw['usedAppliances'] is List
          ? List.from(raw['usedAppliances']).map((e) => e.toString()).toList()
          : [],
      'likes': likes,
      'helpfuls': helpfuls,
      'saves': saves,
      'replies': replies,
      'impressions': impressions,
      'valueScore': computedScore,
    };
  }

  static Future searchRelevantCommunityPosts({
    required List searchTags,
    required String category,
    required String preferredPriceTier,
    required int maxBudgetYen,
    required List missingAppliances,
    required String currentUserId,
    List blockedUsers = const [],
    int topK = 4,
  }) async {
    final postsRef = FirebaseFirestore.instance.collection('posts');
    final Map candidateMap = {};
    final List specificQueryTags = searchTags
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && !_genericStopTags.contains(e))
        .take(25)
        .toList();

    if (specificQueryTags.isEmpty) {
      return [];
    }

    Future fetchHighValueDocs() async {
      try {
        final snap = await postsRef
            .where('aiTags', arrayContainsAny: specificQueryTags)
            .orderBy('valueScore', descending: true)
            .limit(20)
            .get();
        return snap.docs;
      } catch (e) {
        try {
          final snap = await postsRef
              .where('aiTags', arrayContainsAny: specificQueryTags)
              .limit(30)
              .get();
          return snap.docs;
        } catch (e2) {
          return [];
        }
      }
    }

    Future fetchRecentTaggedDocs() async {
      try {
        final snap = await postsRef
            .where('aiTags', arrayContainsAny: specificQueryTags)
            .orderBy('createdAt', descending: true)
            .limit(8)
            .get();
        return snap.docs;
      } catch (e) {
        return [];
      }
    }

    final results = await Future.wait([
      fetchHighValueDocs(),
      fetchRecentTaggedDocs(),
    ]);

    for (final docList in results) {
      if (docList is List) {
        for (final doc in docList) {
          final qDoc = doc as QueryDocumentSnapshot;
          final raw = Map.from(qDoc.data() as Map);
          if (_isExcludedPost(raw, currentUserId, blockedUsers)) continue;
          candidateMap[qDoc.id] = _toLightweightPost(qDoc.id, raw);
        }
      }
    }

    if (candidateMap.isEmpty) {
      try {
        final recentSnap = await postsRef
            .orderBy('createdAt', descending: true)
            .limit(40)
            .get();
        for (final doc in recentSnap.docs) {
          final raw = Map.from(doc.data() as Map);
          if (_isExcludedPost(raw, currentUserId, blockedUsers)) continue;
          candidateMap[doc.id] = _toLightweightPost(doc.id, raw);
        }
      } catch (e) {}
    }

    final List scoredList = [];
    for (final item in candidateMap.values) {
      final post = item as Map;
      final String postMainCat = (post['mainCategory'] ?? '指定なし').toString();

      if (category != 'すべて' &&
          postMainCat != '指定なし' &&
          postMainCat != 'その他' &&
          postMainCat != category) {
        continue;
      }

      final List usedApps = List.from(post['usedAppliances'] ?? const []);
      final bool hasMissingAppliance = usedApps.any(
        (app) => missingAppliances.contains(app.toString()),
      );
      if (hasMissingAppliance) continue;

      final List postTags = List.from(post['aiTags'] ?? const []);
      final String bodyText =
          '${post['title']} ${post['content']} ${post['recipeSteps']}';

      int exactSpecificHits = 0;
      int bodyTextHits = 0;

      for (final qTagObj in specificQueryTags) {
        final qTag = qTagObj.toString();
        if (postTags.contains(qTag)) {
          exactSpecificHits += 1;
        }
        if (bodyText.contains(qTag)) {
          bodyTextHits += 1;
        }
      }

      if (exactSpecificHits == 0 && bodyTextHits == 0) continue;

      final double normalizedValue = min(
        (post['valueScore'] as num).toDouble(),
        100.0,
      );

      double rankScore =
          (exactSpecificHits * 25.0) +
          (bodyTextHits * 35.0) +
          (normalizedValue * 0.25);

      if (category != 'すべて' && postMainCat == category) {
        rankScore += 12.0;
      }

      final String pTier = (post['priceTier'] ?? 'none').toString();
      if (preferredPriceTier == 'low' && pTier == 'low') {
        rankScore += 10.0;
      } else if (preferredPriceTier == 'low' && pTier == 'high') {
        rankScore -= 25.0;
      }

      final int estCost = post['estimatedCost'] is num
          ? (post['estimatedCost'] as num).toInt()
          : -1;
      if (maxBudgetYen > 0 && estCost > 0) {
        if (estCost <= maxBudgetYen) {
          rankScore += 12.0;
        } else {
          rankScore -= 25.0;
        }
      }

      if (rankScore < 30.0) continue;

      post['rankScore'] = rankScore;
      scoredList.add(post);
    }

    scoredList.sort(
      (a, b) => ((b as Map)['rankScore'] as num).compareTo(
        (a as Map)['rankScore'] as num,
      ),
    );

    return scoredList.take(topK).toList();
  }

  static bool _isExcludedPost(
    Map raw,
    String currentUserId,
    List blockedUsers,
  ) {
    if (raw['mainCategory'] == 'AI') return true;
    final hidden = raw['hiddenUsers'] is List
        ? List.from(raw['hiddenUsers'])
        : const [];
    if (currentUserId.isNotEmpty && hidden.contains(currentUserId)) {
      return true;
    }
    final reported = raw['reportedUsers'] is List
        ? List.from(raw['reportedUsers'])
        : const [];
    if (reported.length >= 3 ||
        (currentUserId.isNotEmpty && reported.contains(currentUserId))) {
      return true;
    }
    final postUid = (raw['userId'] ?? '').toString();
    final postUName = (raw['userName'] ?? '').toString();
    if ((postUid.isNotEmpty && blockedUsers.contains(postUid)) ||
        (postUName.isNotEmpty && blockedUsers.contains(postUName))) {
      return true;
    }
    return false;
  }

  static Future backfillAllExistingPosts({
    void Function(int current, int total)? onProgress,
  }) async {
    final snap = await FirebaseFirestore.instance.collection('posts').get();
    final targetDocs = snap.docs.where((d) {
      final data = d.data();
      if (data['mainCategory'] == 'AI') return false;
      final bool alreadyIndexed = data['isAiIndexed'] == true;
      final double score = data['valueScore'] is num
          ? (data['valueScore'] as num).toDouble()
          : -1.0;
      if (alreadyIndexed && score >= 0.0 && score <= 100.0) {
        return false;
      }
      return true;
    }).toList();

    int updatedCount = 0;
    for (int i = 0; i < targetDocs.length; i++) {
      final doc = targetDocs[i];
      final data = doc.data();
      if (onProgress != null) {
        onProgress(i + 1, targetDocs.length);
      }

      final likedUsers = data['likedUsers'] is List
          ? List.from(data['likedUsers'])
          : const [];
      final helpfulUsers = data['helpfulUsers'] is List
          ? List.from(data['helpfulUsers'])
          : const [];
      final savedUsers = data['savedUsers'] is List
          ? List.from(data['savedUsers'])
          : const [];

      final likes = max(readIntField(data['likes']), likedUsers.length);
      final helpfuls = max(readIntField(data['helpfuls']), helpfulUsers.length);
      final saves = max(readIntField(data['saves']), savedUsers.length);
      final replies = readIntField(data['replies']);
      final impressions = readIntField(data['impressions']);

      final valueScore = calculateValueScore(
        likes: likes,
        helpfuls: helpfuls,
        saves: saves,
        replies: replies,
        impressions: impressions,
      );

      if (data['isAiIndexed'] == true) {
        await doc.reference.update({
          'likes': likes,
          'helpfuls': helpfuls,
          'saves': saves,
          'replies': replies,
          'impressions': impressions,
          'valueScore': valueScore,
        });
        updatedCount++;
        continue;
      }

      final List ingredients = [];
      if (data['recipeIngredients'] is List) {
        for (final item in List.from(data['recipeIngredients'])) {
          if (item is Map) {
            ingredients.add(Map.from(item));
          }
        }
      }

      final meta = await analyzePostForDatabase(
        mainCategory: (data['mainCategory'] ?? '指定なし').toString(),
        subCategory: (data['subCategory'] ?? '指定なし').toString(),
        title: (data['title'] ?? '').toString(),
        content: (data['content'] ?? '').toString(),
        isRecipePost: data['isRecipePost'] == true,
        recipeCostText: (data['recipeCost'] ?? '').toString(),
        recipeTimeText: (data['recipeTime'] ?? '').toString(),
        ingredients: ingredients,
        recipeSteps: (data['recipeSteps'] ?? '').toString(),
      );

      await doc.reference.update({
        'likes': likes,
        'helpfuls': helpfuls,
        'saves': saves,
        'replies': replies,
        'impressions': impressions,
        'valueScore': valueScore,
        'aiTags': meta['aiTags'],
        'priceTier': meta['priceTier'],
        'estimatedCost': meta['estimatedCost'],
        'usedAppliances': meta['usedAppliances'],
        'summaryForAi': meta['summaryForAi'],
        'isAiIndexed': true,
      });

      updatedCount++;
    }

    return updatedCount;
  }
}
