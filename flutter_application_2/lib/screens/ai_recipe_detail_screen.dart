import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_detail_screen.dart' show SnsDetailScreen;
import '../widgets/top_toast.dart' show showReactionToast, showTopToast;

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State createState() => _CookingScreenState();
}

class _CookingScreenState extends State with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  final List _recipeStock = [];
  final List _recipes = [];
  final List _communityRecipes = [];
  final List _recentTitles = [];
  final Map _servingsPerRecipe = {};
  final Map _savedDocIdByTitle = {};

  List _cachedMissingAppliances = [];
  List _cachedAllergies = [];
  List _cachedBlockedUsers = [];
  String _cachedUserArea = '日本';

  bool _isLoadingRecipes = true;
  String _errorMessage = '';
  String _seasonLabel = '';
  String _selectedMood = 'おまかせ';

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
    super.dispose();
  }

  String _getSeasonLabel(int month) {
    if (const [3, 4, 5].contains(month)) return '春';
    if (const [6, 7, 8].contains(month)) return '夏';
    if (const [9, 10, 11].contains(month)) return '秋';
    return '冬';
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

  List _filterSafeRecipes(List rawList) {
    if (_cachedAllergies.isEmpty) return List.from(rawList);
    final List safe = [];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final title = (raw['title'] ?? '').toString();
      final ingredients = raw['ingredients'] is List
          ? List.from(raw['ingredients'])
          : const [];
      final steps = (raw['steps'] ?? '').toString();
      final reason = (raw['reason'] ?? '').toString();
      final bool hasAllergen = AiChatScreen.containsAllergenInRecipe(
        title: title,
        ingredients: ingredients,
        steps: '$steps\n$reason',
        allergies: _cachedAllergies,
      );
      if (!hasAllergen) {
        safe.add(raw);
      }
    }
    return safe;
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
          if (data['allergies'] is List) {
            _cachedAllergies = List.from(data['allergies'])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (data['blockedUsers'] is List) {
            _cachedBlockedUsers = List.from(data['blockedUsers'])
                .map((e) => e.toString())
                .toList();
          }
        }
      } catch (e) {}
    }

    await _generateRecommendations(forceRefresh: true);
  }

  void _showAllergySettingsDialog() {
    final List workingAllergies = List.from(_cachedAllergies);
    final TextEditingController customCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void addCustom() {
            final raw = customCtrl.text.trim();
            if (raw.isEmpty) return;
            final parts = raw
                .split(RegExp(r'[\s 、,・/]+'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty);
            setDialogState(() {
              for (final p in parts) {
                if (!workingAllergies.contains(p)) {
                  workingAllergies.add(p);
                }
              }
              customCtrl.clear();
            });
          }

          final List customList = workingAllergies
              .where((a) => !AiChatScreen.presetAllergens.contains(a))
              .toList();

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.no_food_outlined, color: Colors.redAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'アレルギー・苦手食材の設定',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '選択した食材を含むレシピは、AI提案・みんなの人気レシピの両方から除外されます。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final rawAllergen in AiChatScreen.presetAllergens)
                          FilterChip(
                            label: Text(rawAllergen.toString()),
                            selected: workingAllergies.contains(
                              rawAllergen.toString(),
                            ),
                            selectedColor: Colors.red.shade100,
                            checkmarkColor: Colors.red.shade800,
                            onSelected: isSaving
                                ? null
                                : (selected) {
                                    final a = rawAllergen.toString();
                                    setDialogState(() {
                                      if (selected) {
                                        if (!workingAllergies.contains(a)) {
                                          workingAllergies.add(a);
                                        }
                                      } else {
                                        workingAllergies.remove(a);
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
                            controller: customCtrl,
                            decoration: const InputDecoration(
                              hintText: 'その他（例：大豆、ごま、さば）',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => addCustom(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          onPressed: isSaving ? null : addCustom,
                          child: const Text('追加'),
                        ),
                      ],
                    ),
                    if (customList.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final rawCustom in customList)
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
                              onDeleted: isSaving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        workingAllergies.remove(
                                          rawCustom.toString(),
                                        );
                                      });
                                    },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (customCtrl.text.trim().isNotEmpty) {
                          addCustom();
                        }
                        setDialogState(() => isSaving = true);
                        if (_currentUserId.isNotEmpty) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(_currentUserId)
                                .set({
                                  'allergies': workingAllergies,
                                }, SetOptions(merge: true));
                          } catch (e) {}
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (!mounted) return;
                        setState(() {
                          _cachedAllergies = List.from(workingAllergies);
                        });
                        showTopToast(
                          context,
                          workingAllergies.isEmpty
                              ? 'アレルギー除外設定を解除しました'
                              : 'アレルギー除外（${workingAllergies.join('・')}）を保存しました',
                        );
                        _generateRecommendations(forceRefresh: true);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存して再提案'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      customCtrl.dispose();
    });
  }

  Future _fetchCommunityPopularRecipes() async {
    final List tags = [];

    if (_selectedMood == '超節約(150円以下)') {
      tags.addAll(['もやし', '豆腐', '卵', 'うどん', 'ツナ缶', '豚こま', 'キャベツ']);
    } else if (_selectedMood == '10分時短') {
      tags.addAll(['卵', '豚肉', 'もやし', 'フライパン', '丼', 'うどん', '炒め']);
    } else if (_selectedMood == 'ガッツリ肉') {
      tags.addAll(['豚肉', '鶏肉', 'ひき肉', '肉巻き', 'スタミナ丼', '生姜焼き', '唐揚げ']);
    } else if (_selectedMood == '鍋・スープ') {
      tags.addAll(['鍋', '鍋料理', 'スープ', '煮込み', '味噌汁', 'ミルフィーユ鍋', '白菜']);
    } else if (_selectedMood == '麺・丼') {
      tags.addAll(['パスタ', 'うどん', '焼きそば', 'ラーメン', '親子丼', 'スタミナ丼', '漬け丼']);
    } else {
      tags.addAll(['豚肉', '鶏肉', '卵', 'キャベツ', 'もやし', 'うどん', 'パスタ', '鍋']);
    }

    try {
      final rawFound = await AiKnowledgeService.searchRelevantCommunityPosts(
        searchTags: tags,
        category: '料理',
        preferredPriceTier: _selectedMood == '超節約(150円以下)' ? 'low' : 'any',
        maxBudgetYen: _selectedMood == '超節約(150円以下)' ? 200 : -1,
        missingAppliances: _cachedMissingAppliances,
        currentUserId: _currentUserId,
        blockedUsers: _cachedBlockedUsers,
        topK: 8,
      );

      if (mounted && rawFound is List) {
        final List filtered = [];
        for (final raw in rawFound) {
          if (raw is! Map) continue;
          if (_selectedMood == '超節約(150円以下)') {
            final int cost = _parsePostCostYen(raw);
            if (cost > 300) continue;
          }
          if (_cachedAllergies.isNotEmpty) {
            final List ingList = raw['recipeIngredients'] is List
                ? List.from(raw['recipeIngredients'])
                : const [];
            final ingText = ingList
                .where((e) => e is Map)
                .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}')
                .join('\n');
            final combined =
                '${raw['title'] ?? ''}\n${raw['content'] ?? ''}\n$ingText\n${raw['recipeSteps'] ?? ''}';
            if (AiChatScreen.containsAllergen(combined, _cachedAllergies)) {
              continue;
            }
          }
          filtered.add(raw);
          if (filtered.length >= 3) break;
        }

        setState(() {
          _communityRecipes
            ..clear()
            ..addAll(filtered);
        });
      }
    } catch (e) {}
  }

  void _popThreeFromStock() {
    final List safeStock = _filterSafeRecipes(_recipeStock);
    _recipeStock
      ..clear()
      ..addAll(safeStock);

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

  Future _requestRecipesFromAi({
    required String currentKey,
    required String prompt,
  }) async {
    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
          generationConfig: GenerationConfig(temperature: 0.75),
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 25));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          final parsed = _parseRecipeListJson(res.text!);
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        }
      } catch (e) {}
    }
    return null;
  }

  Future _generateRecommendations({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final List safeStock = _filterSafeRecipes(_recipeStock);
      if (safeStock.length >= 3) {
        _recipeStock
          ..clear()
          ..addAll(safeStock);
        _popThreeFromStock();
        return;
      }
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

    final Map moodObj = _moodChips.firstWhere(
      (m) => (m as Map)['label'] == _selectedMood,
      orElse: () => _moodChips.first,
    ) as Map;
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(_cachedAllergies);
    final excludeTitlesText = _recentTitles.isEmpty
        ? 'なし'
        : _recentTitles.join('、');

    final prompt =
        'あなたは一人暮らし専門の優秀な料理家です。\n'
        '以下の条件を厳守して、実用的な自炊レシピを6品考案し、必ずJSON配列形式のみで出力してください。\n\n'
        '【条件】\n'
        '・季節: $_seasonLabel / 居住エリア気候目安: $_cachedUserArea\n'
        '・持っていない調理家電（絶対に使用禁止）: $missingText\n'
        '・【最重要・厳守】アレルギー・食べられない食材（材料・調味料・加工品含め1ミリも使用禁止）: $allergyRule\n'
        '・気分ルール: ${moodObj['rule']}（ただしアレルギー禁止条件と矛盾する場合は、必ずアレルギー禁止条件を最優先すること）\n'
        '・スーパーで安く手に入る身近な食材を使うこと。\n'
        '・直近で提案済みの除外料理名: $excludeTitlesText\n'
        '・すべて1人分の分量と目安費用にすること（分量は数値を含めること）。\n\n'
        '【出力JSON配列フォーマット（説明文なし・JSON配列のみ）】\n'
        '[\n'
        '  {\n'
        '    "title": "料理名",\n'
        '    "time": "約10分",\n'
        '    "cost": "約180円",\n'
        '    "reason": "おすすめポイント（35文字以内）",\n'
        '    "ingredients": [{"name": "豚こま肉", "amount": "100g"}, {"name": "キャベツ", "amount": "2枚"}],\n'
        '    "steps": "1. 切る\\n2. 炒める\\n3. 味付けして完成"\n'
        '  }\n'
        ']';

    final rawGenerated = await _requestRecipesFromAi(
      currentKey: currentKey,
      prompt: prompt,
    );
    List safeList = rawGenerated is List
        ? _filterSafeRecipes(rawGenerated)
        : [];

    if (safeList.isEmpty && _cachedAllergies.isNotEmpty) {
      final strictRetryPrompt =
          '【絶対厳守】アレルギー対象（$allergyRule）およびその加工品・調味料を一切含まない、安全な一人暮らし向け自炊レシピを6品考案し、JSON配列のみで出力してください。\n'
          '持っていない家電（$missingText）も使用禁止です。塩・ごま油・米・肉・魚・野菜など安全な素材を中心に組み立ててください。\n'
          'フォーマット: [{"title":"料理名","time":"約10分","cost":"約180円","reason":"ポイント","ingredients":[{"name":"材料名","amount":"分量"}],"steps":"1. 手順"}]';
      final retryGenerated = await _requestRecipesFromAi(
        currentKey: currentKey,
        prompt: strictRetryPrompt,
      );
      if (retryGenerated is List) {
        safeList = _filterSafeRecipes(retryGenerated);
      }
    }

    await communityFuture;
    if (!mounted) return;

    if (safeList.isNotEmpty) {
      _recipeStock
        ..clear()
        ..addAll(safeList);
      _popThreeFromStock();
    } else {
      setState(() {
        _isLoadingRecipes = false;
        _errorMessage = _cachedAllergies.isNotEmpty
            ? 'アレルギー除外条件に合うレシピを作成できませんでした。別の気分を選ぶか再度お試しください。'
            : 'レシピの作成に失敗しました。少し待ってから再度お試しください。';
      });
    }
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

  Future _askAiSubstitution({
    required String dishTitle,
    required List allIngredients,
    String? targetIngredient,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AIチャット画面でAPIキーを設定してください')));
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
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(_cachedAllergies);

    final prompt = targetIngredient != null
        ? '料理「$dishTitle」（材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$dishTitle」（材料：$ingNames）について、\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、さらに安く手軽に作れる代替食材やアレンジのコツを200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String reply = '代用案を取得できませんでした。';
    for (final m in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(model: m.toString(), apiKey: currentKey);
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          reply = res.text!.replaceAll('**', '').replaceAll('##', '').trim();
          break;
        }
      } catch (e) {}
    }

    if (_cachedAllergies.isNotEmpty &&
        AiChatScreen.containsAllergen(reply, _cachedAllergies)) {
      reply =
          'アレルギー対象食材（${_cachedAllergies.join('・')}）に関連する表現が含まれたため表示を控えました。AI相談画面で使える手持ち食材を指定して聞いてみてください。';
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
          child: Text(reply, style: const TextStyle(fontSize: 15, height: 1.5)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future _toggleSaveRecipeToBookmarks(Map recipe, String? existingDocId) async {
    if (_currentUserId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存するにはログインが必要です')));
      return;
    }

    final String title = (recipe['title'] ?? 'AIおすすめレシピ').toString();

    if (existingDocId != null && existingDocId.isNotEmpty) {
      setState(() {
        _savedDocIdByTitle.remove(title);
      });
      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(existingDocId)
            .update({
              'savedUsers': FieldValue.arrayRemove([_currentUserId]),
            });
        if (mounted) {
          showReactionToast(context, 'savedUsers', added: false);
        }
      } catch (e) {}
      return;
    }

    final String time = (recipe['time'] ?? '').toString();
    final String cost = (recipe['cost'] ?? '').toString();
    final String reason = (recipe['reason'] ?? '').toString();
    final String steps = (recipe['steps'] ?? '').toString();
    final List ingredients = [];
    if (recipe['ingredients'] is List) {
      for (final item in List.from(recipe['ingredients'])) {
        if (item is Map) {
          ingredients.add({
            'name': (item['name'] ?? '').toString(),
            'amount': (item['amount'] ?? '適量').toString(),
          });
        }
      }
    }

    final ingLines = ingredients
        .map((e) => '・${(e as Map)['name']} ${e['amount']}')
        .join('\n');
    final fullContent =
        '【料理名】$title\n【目安時間】$time\n【目安費用】$cost\n【材料】\n$ingLines\n【作り方】\n$steps'
        '${reason.isNotEmpty ? "\n【ポイント】\n$reason" : ""}';

    setState(() {
      _savedDocIdByTitle[title] = 'pending';
    });

    try {
      final docRef = await FirebaseFirestore.instance.collection('posts').add({
        'userId': _currentUserId,
        'userName': 'AIレシピ提案',
        'mainCategory': 'AI',
        'subCategory': 'レシピ',
        'title': title,
        'content': fullContent,
        'hasImage': false,
        'imageBase64': '',
        'imagesBase64': [],
        'isRecipePost': true,
        'recipeTime': time,
        'recipeCost': cost,
        'recipeServings': 1,
        'recipeIngredients': ingredients,
        'recipeSteps': steps,
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
        _savedDocIdByTitle[title] = docRef.id;
      });
      showReactionToast(context, 'savedUsers', added: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savedDocIdByTitle.remove(title);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
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
                'みんなの人気レシピ（タイムラインから）',
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

  Widget _buildRecipeCard({
    required Map recipe,
    required String cardKey,
    required String? savedDocId,
  }) {
    final String title = (recipe['title'] ?? 'おすすめレシピ').toString();
    final String time = (recipe['time'] ?? '').toString();
    final String rawCost = (recipe['cost'] ?? '').toString();
    final String reason = (recipe['reason'] ?? '').toString();
    final String steps = (recipe['steps'] ?? '').toString();
    final int baseServings =
        int.tryParse(recipe['servings']?.toString() ?? '1') ?? 1;
    final List ingredients = [];
    if (recipe['ingredients'] is List) {
      for (final item in List.from(recipe['ingredients'])) {
        if (item is Map) {
          ingredients.add(Map.from(item));
        }
      }
    }

    final int servings = (_servingsPerRecipe[cardKey] as int?) ?? baseServings;
    final String scaledCost = _scaleAmountString(
      rawCost,
      baseServings,
      servings,
    );
    final bool isSaved = savedDocId != null && savedDocId.isNotEmpty;

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
                OutlinedButton.icon(
                  onPressed: () => _askAiSubstitution(
                    dishTitle: title,
                    allIngredients: ingredients,
                  ),
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 14,
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
                const SizedBox(width: 4),
                IconButton(
                  tooltip: isSaved ? '保存フォルダから解除' : '保存フォルダに追加',
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: isSaved ? Colors.blue : Colors.grey,
                  ),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  onPressed: () =>
                      _toggleSaveRecipeToBookmarks(recipe, savedDocId),
                ),
              ],
            ),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
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
            if (ingredients.isNotEmpty) ...[
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
                                  _servingsPerRecipe[cardKey] = servings - 1;
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
                                  _servingsPerRecipe[cardKey] = servings + 1;
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
                      baseServings,
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
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '作り方',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(steps, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (_cachedAllergies.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '※除外設定（${_cachedAllergies.join('・')}）を反映済み。市販の調味料・加工品は必ず成分表示をご確認ください。',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade900),
              ),
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
                            '「$title」を作りたいのですが、さらに美味しくするコツやアレンジ方法を教えて！',
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
    return StreamBuilder(
      stream: _currentUserId.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('posts')
                .where('savedUsers', arrayContains: _currentUserId)
                .snapshots()
          : null,
      builder: (context, savedSnap) {
        final List savedAiRecipes = [];
        final Map liveSavedIdByTitle = Map.from(_savedDocIdByTitle);

        if (savedSnap.hasData && savedSnap.data != null) {
          final docs = (savedSnap.data as QuerySnapshot).docs;
          final List aiDocs = [];
          for (final d in docs) {
            final data = d.data() as Map;
            final bool isAiRecipe =
                data['mainCategory'] == 'AI' &&
                (data['isRecipePost'] == true || data['subCategory'] == 'レシピ');
            if (!isAiRecipe) continue;
            aiDocs.add(d);
            final t = (data['title'] ?? '').toString();
            if (t.isNotEmpty) {
              liveSavedIdByTitle[t] = d.id;
            }
          }

          aiDocs.sort((a, b) {
            final da = (a as QueryDocumentSnapshot).data() as Map;
            final db = (b as QueryDocumentSnapshot).data() as Map;
            final ta = da['createdAt'] as Timestamp?;
            final tb = db['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

          for (final rawDoc in aiDocs) {
            final doc = rawDoc as QueryDocumentSnapshot;
            final data = doc.data() as Map;
            savedAiRecipes.add({
              'docId': doc.id,
              'title': (data['title'] ?? 'AIレシピ').toString(),
              'time': (data['recipeTime'] ?? '').toString(),
              'cost': (data['recipeCost'] ?? '').toString(),
              'servings': data['recipeServings'] ?? 1,
              'ingredients': data['recipeIngredients'] is List
                  ? List.from(data['recipeIngredients'])
                  : [],
              'steps': (data['recipeSteps'] ?? '').toString(),
              'reason': '',
            });
          }
        }

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
            actions: [
              IconButton(
                tooltip: 'アレルギー・苦手食材の設定',
                icon: Icon(
                  Icons.no_food_outlined,
                  color: _cachedAllergies.isNotEmpty
                      ? Colors.redAccent
                      : Colors.black87,
                ),
                onPressed: _showAllergySettingsDialog,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: [
                const Tab(text: '今日のおすすめ'),
                Tab(text: '保存済み (${savedAiRecipes.length})'),
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
                        if (_cachedAllergies.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _showAllergySettingsDialog,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.no_food_outlined,
                                      size: 16,
                                      color: Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'アレルギー除外中: ${_cachedAllergies.join('・')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
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
                          ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '今の気分でワンタップ提案',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _isLoadingRecipes
                                        ? null
                                        : () => _generateRecommendations(
                                            forceRefresh:
                                                _recipeStock.length < 3,
                                          ),
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text(
                                      '別メニュー',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
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
                                          final isSelected =
                                              _selectedMood == label;
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
                                              selectedColor:
                                                  Colors.orange.shade100,
                                              backgroundColor:
                                                  Colors.grey.shade100,
                                              onSelected: _isLoadingRecipes
                                                  ? null
                                                  : (_) {
                                                      if (_selectedMood ==
                                                          label) {
                                                        return;
                                                      }
                                                      setState(() {
                                                        _selectedMood = label;
                                                      });
                                                      _generateRecommendations(
                                                        forceRefresh: true,
                                                      );
                                                    },
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const AiChatScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                  label: const Text(
                                    '冷蔵庫の余り物や細かい条件はAI相談へ',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
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
                                  Text('今の気分と条件に合わせてレシピを考案中...'),
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
                          for (final r in _recipes)
                            Builder(
                              builder: (_) {
                                final rMap = r as Map;
                                final t = (rMap['title'] ?? '').toString();
                                return _buildRecipeCard(
                                  recipe: rMap,
                                  cardKey: 'rec_$t',
                                  savedDocId: liveSavedIdByTitle[t]?.toString(),
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              savedAiRecipes.isEmpty
                  ? const Center(
                      child: Text(
                        'まだ保存したAIレシピはありません。\n気になるレシピの🔖を押すと保存フォルダにも追加されます！',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      itemCount: savedAiRecipes.length,
                      itemBuilder: (context, idx) {
                        final item = savedAiRecipes[idx] as Map;
                        final docId = (item['docId'] ?? '').toString();
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: _buildRecipeCard(
                              recipe: item,
                              cardKey: 'saved_$docId',
                              savedDocId: docId,
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }
}
