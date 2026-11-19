import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_detail_screen.dart' show SnsDetailScreen;

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State createState() => _CookingScreenState();
}

class _CookingScreenState extends State with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  final TextEditingController _customIngredientController =
      TextEditingController();

  final List _recipeStock = [];
  final List _recipes = [];
  final List _communityRecipes = [];
  List _savedRecipes = [];
  final List _recentTitles = [];
  final Map _servingsPerRecipe = {};

  final List _selectedFridgeIngredients = [];
  bool _isReuse3DayMode = false;

  List _cachedMissingAppliances = [];
  List _cachedBlockedUsers = [];
  String _cachedUserArea = '日本';

  bool _isLoadingRecipes = true;
  String _errorMessage = '';
  String _seasonLabel = '';
  String _selectedMood = 'おまかせ';

  final List _fridgePresetChips = [
    '卵',
    '豚肉',
    '鶏むね肉',
    'キャベツ',
    'もやし',
    '豆腐',
    'ツナ缶',
    '玉ねぎ',
    'うどん',
    'きのこ',
  ];

  final List _moodChips = [
    {
      'emoji': '🎲',
      'label': 'おまかせ',
      'rule': '3品それぞれ異なるメイン食材と調理法を組み合わせたバラエティ豊かな献立にすること。',
    },
    {
      'emoji': '💰',
      'label': '超節約(150円以下)',
      'rule': '1人分150円以下で作れるコスパ最強の節約レシピにすること。',
    },
    {
      'emoji': '⚡',
      'label': '10分時短',
      'rule': '調理時間10分以内・洗い物最小限でサッと作れるスピードレシピにすること。',
    },
    {
      'emoji': '🍖',
      'label': 'ガッツリ肉',
      'rule': '鶏肉・豚肉・ひき肉などを主役にしたご飯が進むおかずにすること。',
    },
    {
      'emoji': '🍲',
      'label': '鍋・スープ',
      'rule': '鍋やフライパン1つで煮込んで作れる温かい汁物・鍋料理にすること。',
    },
    {
      'emoji': '🍜',
      'label': '麺・丼',
      'rule': 'うどん・パスタ・焼きそば・丼など1品で完結するメニューにすること。',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _seasonLabel = _getSeasonLabel(DateTime.now().month);
    _loadUserProfileAndInitialRecipes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customIngredientController.dispose();
    super.dispose();
  }

  String _getSeasonLabel(int month) {
    if (const [3, 4, 5].contains(month)) return '春';
    if (const [6, 7, 8].contains(month)) return '夏';
    if (const [9, 10, 11].contains(month)) return '秋';
    return '冬';
  }

  List _collectAllSelectedIngredients() {
    final Set combined = Set.from(_selectedFridgeIngredients);
    final rawInput = _customIngredientController.text.trim();
    if (rawInput.isNotEmpty) {
      final split = rawInput
          .split(RegExp(r'[\s 、,・/]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      combined.addAll(split);
    }
    return combined.toList();
  }

  Future _loadUserProfileAndInitialRecipes() async {
    if (_currentUserId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          _cachedUserArea = (data['area'] ?? '日本').toString();
          if (data['missingAppliances'] is List) {
            _cachedMissingAppliances = List.from(data['missingAppliances'])
                .map((e) => e.toString())
                .toList();
          }
          if (data['blockedUsers'] is List) {
            _cachedBlockedUsers = List.from(data['blockedUsers'])
                .map((e) => e.toString())
                .toList();
          }
          if (data['savedCookingRecipes'] is List) {
            final List loaded = [];
            for (final item in List.from(data['savedCookingRecipes'])) {
              if (item is Map) {
                loaded.add(Map.from(item));
              }
            }
            _savedRecipes = loaded;
          }
        }
      } catch (e) {}
    }

    await _generateRecommendations(forceRefresh: true);
  }

  Future _fetchCommunityPopularRecipes() async {
    final ingredients = _collectAllSelectedIngredients();
    final List tags = [...ingredients, '料理', '自炊'];

    if (_selectedMood == '超節約(150円以下)') {
      tags.addAll(['節約', '低予算', '100円以下', 'コスパ']);
    } else if (_selectedMood == '10分時短') {
      tags.addAll(['時短', '簡単', '洗い物少ない']);
    } else if (_selectedMood == 'ガッツリ肉') {
      tags.addAll(['豚肉', '鶏肉', '肉類', '肉巻き']);
    } else if (_selectedMood == '鍋・スープ') {
      tags.addAll(['鍋', '鍋料理', 'スープ', '煮込み']);
    } else if (_selectedMood == '麺・丼') {
      tags.addAll(['麺類', 'パスタ', 'うどん', '丼']);
    }

    try {
      final rawFound = await AiKnowledgeService.searchRelevantCommunityPosts(
        searchTags: tags.take(28).toList(),
        category: '料理',
        preferredPriceTier: _selectedMood == '超節約(150円以下)' ? 'low' : 'any',
        maxBudgetYen: _selectedMood == '超節約(150円以下)' ? 200 : -1,
        missingAppliances: _cachedMissingAppliances,
        currentUserId: _currentUserId,
        blockedUsers: _cachedBlockedUsers,
        topK: 3,
      );

      if (mounted && rawFound is List) {
        setState(() {
          _communityRecipes
            ..clear()
            ..addAll(rawFound);
        });
      }
    } catch (e) {}
  }

  void _popThreeFromStock() {
    final List nextThree = [];
    while (_recipeStock.isNotEmpty && nextThree.length < 3) {
      final item = _recipeStock.removeAt(0) as Map;
      nextThree.add(item);
      final title = (item['title'] ?? '').toString();
      if (title.isNotEmpty) {
        _recentTitles.add(title);
      }
    }
    if (_recentTitles.length > 24) {
      _recentTitles.removeRange(0, _recentTitles.length - 24);
    }
    setState(() {
      _recipes
        ..clear()
        ..addAll(nextThree);
      _isLoadingRecipes = false;
      _errorMessage = '';
    });
  }

  List? _parseRecipeListJson(String rawText) {
    final fence = String.fromCharCodes([96, 96, 96]);
    final cleaned = rawText
        .replaceAll('${fence}json', '')
        .replaceAll(fence, '')
        .trim();
    final startIdx = cleaned.indexOf('[');
    final endIdx = cleaned.lastIndexOf(']');
    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) return null;
    try {
      final decoded = jsonDecode(cleaned.substring(startIdx, endIdx + 1));
      if (decoded is List) {
        final List result = [];
        for (final item in decoded) {
          if (item is Map) {
            result.add(Map.from(item));
          }
        }
        return result;
      }
    } catch (e) {}
    return null;
  }

  Future _generateRecommendations({bool forceRefresh = false}) async {
    if (!forceRefresh && _recipeStock.length >= 3) {
      _popThreeFromStock();
      return;
    }

    setState(() {
      _isLoadingRecipes = true;
      _errorMessage = '';
      if (forceRefresh) {
        _recipeStock.clear();
      }
    });

    final communityFuture = _fetchCommunityPopularRecipes();

    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      await communityFuture;
      if (mounted) {
        setState(() {
          _isLoadingRecipes = false;
          _errorMessage = 'ai_chat_screen.dart にAPIキーを設定してください。';
        });
      }
      return;
    }

    final ingredients = _collectAllSelectedIngredients();
    final Map moodObj = _moodChips.firstWhere(
      (m) => (m as Map)['label'] == _selectedMood,
      orElse: () => _moodChips.first,
    ) as Map;
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');
    final excludeTitlesText = _recentTitles.isEmpty
        ? 'なし'
        : _recentTitles.join('、');

    final int generateCount = _isReuse3DayMode ? 3 : 6;
    final String ingredientInstruction = ingredients.isEmpty
        ? '特段の食材指定なし（スーパーで安く手に入る$_seasonLabelの食材を使うこと）。'
        : _isReuse3DayMode
        ? '【最重要】指定食材「${ingredients.join('、')}」を3日間飽きずに使い切る「1日目・2日目・3日目」の3品を作成すること。3品すべてで味付け（和・洋・中など）と調理法を変えること。'
        : '【最重要】冷蔵庫にある指定食材「${ingredients.join('、')}」を必ずメインで使って作れるレシピにすること。追加食材は常備調味料や安価な食材1〜2品までに抑えること。';

    final prompt =
        'あなたは一人暮らし専門の優秀な料理家です。\n'
        '以下の条件を厳守して、実用的な自炊レシピを$generateCount品考案し、必ずJSON配列形式のみで出力してください。\n\n'
        '【条件】\n'
        '・季節: $_seasonLabel / 居住エリア気候目安: $_cachedUserArea\n'
        '・持っていない調理家電（絶対に使用禁止）: $missingText\n'
        '・気分ルール: ${moodObj['rule']}\n'
        '・食材条件: $ingredientInstruction\n'
        '・直近で提案済みの除外料理名: $excludeTitlesText\n'
        '・すべて1人分の分量と目安費用にすること。\n\n'
        '【出力JSON配列フォーマット（説明文なし・JSON配列のみ）】\n'
        '[\n'
        '  {\n'
        '    "title": "料理名（3日使い回し時は先頭に【1日目】等を付ける）",\n'
        '    "time": "約10分",\n'
        '    "cost": "約180円",\n'
        '    "reason": "おすすめポイント（35文字以内）",\n'
        '    "ingredients": [{"name": "豚こま肉", "amount": "100g"}, {"name": "キャベツ", "amount": "2枚"}],\n'
        '    "steps": "1. 切る\\n2. 炒める\\n3. 味付けして完成"\n'
        '  }\n'
        ']';

    List? generatedList;
    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
          generationConfig: GenerationConfig(temperature: 0.7),
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 25));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          final parsed = _parseRecipeListJson(res.text!);
          if (parsed != null && parsed.isNotEmpty) {
            generatedList = parsed;
            break;
          }
        }
      } catch (e) {}
    }

    await communityFuture;
    if (!mounted) return;

    if (generatedList != null && generatedList.isNotEmpty) {
      _recipeStock
        ..clear()
        ..addAll(generatedList);
      _popThreeFromStock();
    } else {
      setState(() {
        _isLoadingRecipes = false;
        _errorMessage = 'レシピの作成に失敗しました。少し待ってから再度お試しください。';
      });
    }
  }

  String _formatScaledNumber(double val) {
    if ((val - val.round()).abs() < 0.05) {
      return val.round().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _scaleAmountString(String rawAmount, int targetServings) {
    if (targetServings <= 1) return rawAmount;
    final double ratio = targetServings.toDouble();

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

    return '$rawAmount（×$targetServings）';
  }

  Future _askAiSubstitution(
    String dishTitle,
    String targetIngredient,
    List allIngredients,
  ) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AIが代用案を考えています...')),
          ],
        ),
      ),
    );

    final ingNames = allIngredients
        .where((e) => e is Map)
        .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}')
        .join('、');
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');

    final prompt =
        '料理「$dishTitle」（材料：$ingNames）で「$targetIngredient」がありません。\n'
        '持っていない家電【$missingText】を使わず、身近な食材や調味料での代用案と分量を150文字以内で簡潔に教えてください。Markdown記号は使わないでください。';

    String reply = '代用案を取得できませんでした。';
    for (final m in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(model: m.toString(), apiKey: currentKey);
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 18));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          reply = res.text!.replaceAll('**', '').replaceAll('##', '').trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「$targetIngredient」の代用案'),
        content: Text(reply, style: const TextStyle(height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future _toggleSaveRecipe(Map recipe) async {
    final title = (recipe['title'] ?? '').toString();
    final existsIdx = _savedRecipes.indexWhere(
      (r) => r is Map && (r['title'] ?? '') == title,
    );

    setState(() {
      if (existsIdx != -1) {
        _savedRecipes.removeAt(existsIdx);
      } else {
        _savedRecipes.insert(0, Map.from(recipe));
      }
    });

    if (_currentUserId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .set({
              'savedCookingRecipes': _savedRecipes,
            }, SetOptions(merge: true));
      } catch (e) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existsIdx != -1 ? '保存から削除しました' : '「$title」を保存しました！'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildCommunitySection() {
    if (_communityRecipes.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 6),
              Text(
                'みんなの実体験人気レシピ（TLから厳選）',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final rawPost in _communityRecipes)
            Builder(
              builder: (_) {
                final post = rawPost as Map;
                final docId = (post['docId'] ?? '').toString();
                final userName = (post['userName'] ?? '名無し').toString();
                final title = (post['title'] ?? '').toString();
                final content = (post['content'] ?? '').toString();
                final cost = (post['recipeCost'] ?? '').toString();
                final helpfuls = AiKnowledgeService.readIntField(
                  post['helpfuls'],
                );
                final saves = AiKnowledgeService.readIntField(post['saves']);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.blue.shade100),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      title.isNotEmpty ? title : content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Text(
                            '$userName さん',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (cost.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              cost,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          const Spacer(),
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 14,
                            color: Colors.orange,
                          ),
                          Text(
                            ' $helpfuls',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.bookmark_border,
                            size: 14,
                            color: Colors.blue,
                          ),
                          Text(' $saves', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (docId.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SnsDetailScreen(postId: docId),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRecipeCard(Map recipe) {
    final String title = (recipe['title'] ?? 'おすすめレシピ').toString();
    final String time = (recipe['time'] ?? '').toString();
    final String rawCost = (recipe['cost'] ?? '').toString();
    final String reason = (recipe['reason'] ?? '').toString();
    final String steps = (recipe['steps'] ?? '').toString();
    final List ingredients = [];
    if (recipe['ingredients'] is List) {
      for (final item in List.from(recipe['ingredients'])) {
        if (item is Map) {
          ingredients.add(Map.from(item));
        }
      }
    }

    final int servings = (_servingsPerRecipe[title] as int?) ?? 1;
    final String scaledCost = _scaleAmountString(rawCost, servings);
    final bool isSaved = _savedRecipes.any(
      (r) => r is Map && (r['title'] ?? '') == title,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: isSaved ? Colors.blue : Colors.grey,
                  ),
                  onPressed: () => _toggleSaveRecipe(recipe),
                ),
              ],
            ),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  reason,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (time.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Text(time, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                if (scaledCost.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$scaledCost（$servings人分）',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '材料（$servings人分）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      onPressed: servings > 1
                          ? () {
                              setState(() {
                                _servingsPerRecipe[title] = servings - 1;
                              });
                            }
                          : null,
                    ),
                    Text(
                      '$servings人分',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      onPressed: servings < 6
                          ? () {
                              setState(() {
                                _servingsPerRecipe[title] = servings + 1;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final rawIng in ingredients)
              Builder(
                builder: (_) {
                  final ing = rawIng as Map;
                  final name = (ing['name'] ?? '').toString();
                  final amt = _scaleAmountString(
                    (ing['amount'] ?? '').toString(),
                    servings,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '・$name : $amt',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _askAiSubstitution(title, name, ingredients),
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
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '作り方',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(steps, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AiChatScreen(
                        initialPrompt:
                            '「$title」を作りたいのですが、さらに美味しくするコツや余った食材の活用法を教えて！',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text(
                  'このレシピをAIに相談',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text(
          '自炊レシピ提案',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          tabs: [
            const Tab(text: '今日のおすすめ'),
            Tab(text: '保存したレシピ (${_savedRecipes.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🥬 冷蔵庫にある食材を指定（複数OK）',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final rawIng in _fridgePresetChips)
                                FilterChip(
                                  label: Text(
                                    rawIng.toString(),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected: _selectedFridgeIngredients.contains(
                                    rawIng.toString(),
                                  ),
                                  selectedColor: Colors.orange.shade200,
                                  backgroundColor: Colors.white,
                                  onSelected: (val) {
                                    final ing = rawIng.toString();
                                    setState(() {
                                      if (val) {
                                        _selectedFridgeIngredients.add(ing);
                                      } else {
                                        _selectedFridgeIngredients.remove(ing);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _customIngredientController,
                            decoration: const InputDecoration(
                              hintText: 'その他の食材（例：春キャベツ、納豆、サバ缶）',
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text(
                              '🔁 選んだ食材を3日間で使い切る献立モード',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            value: _isReuse3DayMode,
                            onChanged: (val) {
                              setState(() {
                                _isReuse3DayMode = val;
                              });
                            },
                          ),
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final rawM in _moodChips)
                                  Builder(
                                    builder: (_) {
                                      final m = rawM as Map;
                                      final label = (m['label'] ?? '')
                                          .toString();
                                      final emoji = (m['emoji'] ?? '')
                                          .toString();
                                      final isSelected = _selectedMood == label;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6.0,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            '$emoji $label',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor: Colors.blue.shade100,
                                          backgroundColor: Colors.white,
                                          onSelected: (_) {
                                            setState(() {
                                              _selectedMood = label;
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoadingRecipes
                                      ? null
                                      : () => _generateRecommendations(
                                          forceRefresh: true,
                                        ),
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'この条件でレシピを提案する',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              if (_recipeStock.length >= 3) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: _isLoadingRecipes
                                      ? null
                                      : () => _generateRecommendations(
                                          forceRefresh: false,
                                        ),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('別メニュー'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildCommunitySection(),
                    if (_isLoadingRecipes)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('食材と家電に合わせて最適なレシピを考案中...'),
                            ],
                          ),
                        ),
                      )
                    else if (_errorMessage.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      )
                    else
                      for (final r in _recipes) _buildRecipeCard(r as Map),
                  ],
                ),
              ),
            ),
          ),
          _savedRecipes.isEmpty
              ? const Center(
                  child: Text(
                    'まだ保存したレシピはありません。\n気になるレシピの🔖を押して保存しよう！',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  itemCount: _savedRecipes.length,
                  itemBuilder: (context, idx) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: _buildRecipeCard(_savedRecipes[idx] as Map),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
