import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart';

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State createState() => _CookingScreenState();
}

class _CookingScreenState extends State with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  List _recipeStock = [];
  final List _recipes = [];
  List _savedRecipes = [];
  final List _recentTitles = [];
  final List _recentIngredients = [];
  final Map _servingsPerRecipe = {};

  List _cachedMissingAppliances = [];
  String _cachedUserArea = '日本';

  bool _isLoadingRecipes = true;
  String _errorMessage = '';
  String _seasonLabel = '';
  String _selectedMood = 'おまかせ';

  final List _moodChips = [
    {
      'emoji': '🎲',
      'label': 'おまかせ',
      'rule': '3品それぞれ異なるメイン食材（肉・魚介・卵や豆腐など）と異なる調理法を組み合わせたバラエティ豊かな献立にすること。',
    },
    {
      'emoji': '🍖',
      'label': 'ガッツリ肉',
      'rule': '鶏肉・豚肉・ひき肉・ウインナー・ベーコンなどの肉類を主役にし、3品それぞれ違う種類の肉を使ってご飯が進むおかずにすること。',
    },
    {
      'emoji': '🐟',
      'label': '魚・缶詰',
      'rule': 'ツナ缶・サバ缶・鮭・ちくわ・カニカマ・しらす等の魚介や加工品を使い、3品それぞれ違う魚介食材で手軽に作れるおかずにすること。',
    },
    {
      'emoji': '🍜',
      'label': '麺・丼もの',
      'rule': 'うどん・パスタ・中華麺・焼きそば・そうめん、または1皿で完結する丼もの・混ぜご飯から3品すべて異なる主食メニューにすること。',
    },
    {
      'emoji': '🥬',
      'label': '野菜・ヘルシー',
      'rule': '旬の野菜・豆腐・厚揚げ・納豆・卵・春雨・海藻などを主役にし、3品それぞれ異なるメイン野菜を使ったヘルシーなおかずにすること。',
    },
    {
      'emoji': '⚡',
      'label': '5分スピード',
      'rule': '包丁をほとんど使わず、調理時間5分以内・3ステップ以内で即完成する超時短メニュー3品にすること。',
    },
  ];

  final List _basicSeasonings = [
    '醤油',
    'しょうゆ',
    '塩',
    'こしょう',
    '胡椒',
    '塩こしょう',
    '砂糖',
    '酒',
    '料理酒',
    'みりん',
    '水',
    'お湯',
    'ごま油',
    'サラダ油',
    'オリーブオイル',
    'マヨネーズ',
    '片栗粉',
    'めんつゆ',
    '鶏ガラスープの素',
    'コンソメ',
    '和風だしの素',
    '味噌',
    'みそ',
    '酢',
    'バター',
    'にんにく',
    '生姜',
    'しょうが',
    '白ごま',
    'いりごま',
    '黒こしょう',
    'ケチャップ',
    'ソース',
    'ポン酢',
    'オイスターソース',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initCookingData();
  }

  String _getSeason(int month) {
    if (const [3, 4, 5].contains(month)) return '春';
    if (const [6, 7, 8].contains(month)) return '夏';
    if (const [9, 10, 11].contains(month)) return '秋';
    return '冬';
  }

  String _getTodayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  String _formatScaledNumber(double val) {
    if ((val - val.round()).abs() < 0.05) {
      return val.round().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _scaleTextWithRatio(String rawText, int targetServings) {
    if (targetServings <= 1) return rawText;
    final double ratio = targetServings.toDouble();

    final fractionRegex = RegExp(r'(\d+)\s*/\s*(\d+)');
    if (fractionRegex.hasMatch(rawText)) {
      return rawText.replaceAllMapped(fractionRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '1') ?? 1;
        final den = double.tryParse(match.group(2) ?? '1') ?? 1;
        if (den == 0) return match.group(0) ?? '';
        return _formatScaledNumber((num / den) * ratio);
      });
    }

    final decimalRegex = RegExp(r'(\d+(?:\.\d+)?)');
    if (decimalRegex.hasMatch(rawText)) {
      return rawText.replaceAllMapped(decimalRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '0') ?? 0;
        return _formatScaledNumber(num * ratio);
      });
    }

    return '$rawText（×$targetServings）';
  }

  void _recordHistoryFromRecipes(List recipeList) {
    for (final item in recipeList) {
      final mapItem = item as Map;
      final title = mapItem['title']?.toString().trim() ?? '';
      if (title.isNotEmpty && !_recentTitles.contains(title)) {
        _recentTitles.add(title);
      }

      final List ingList = List.from(mapItem['ingredients'] ?? []);
      for (final rawIng in ingList) {
        final cleanName = rawIng
            .toString()
            .split(RegExp(r'[\s :：0-9０-９（(]'))
            .first
            .trim();
        if (cleanName.length >= 2 &&
            !_basicSeasonings.contains(cleanName) &&
            !_recentIngredients.contains(cleanName)) {
          _recentIngredients.add(cleanName);
        }
      }
    }

    if (_recentTitles.length > 40) {
      _recentTitles.removeRange(0, _recentTitles.length - 40);
    }
    if (_recentIngredients.length > 25) {
      _recentIngredients.removeRange(0, _recentIngredients.length - 25);
    }
  }

  Future _initCookingData() async {
    final now = DateTime.now();
    final season = _getSeason(now.month);
    if (mounted) {
      setState(() {
        _seasonLabel = '${now.month}月${now.day}日（$season）のAIおすすめ';
        _isLoadingRecipes = true;
        _errorMessage = '';
      });
    }

    final todayKey = _getTodayKey();

    if (_currentUserId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (!mounted) return;
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['missingAppliances'] != null) {
            _cachedMissingAppliances = List.from(data['missingAppliances']);
          }
          if (data['area'] != null &&
              data['area'].toString().trim().isNotEmpty) {
            _cachedUserArea = data['area'].toString().trim();
          }
          if (data['savedCookingRecipeItems'] != null) {
            _savedRecipes = List.from(data['savedCookingRecipeItems']);
          }
          if (data['dailyRecipesDate'] == todayKey &&
              data['dailyRecipes'] != null) {
            final loaded = List.from(data['dailyRecipes']);
            if (loaded.isNotEmpty) {
              _recordHistoryFromRecipes(loaded);
              setState(() {
                _recipes.clear();
                _recipes.addAll(loaded.take(3));
                if (loaded.length > 3) {
                  _recipeStock = loaded.skip(3).toList();
                }
                _isLoadingRecipes = false;
              });
              return;
            }
          }
        }
      } catch (e) {}
    }

    await _fetchAndStockRecipes(forceRefresh: false);
  }

  String _extractJsonArray(String raw) {
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }
    return cleaned;
  }

  void _onPressNextMenu() {
    if (_recipeStock.length >= 3) {
      final nextThree = _recipeStock.take(3).toList();
      _recipeStock.removeRange(0, 3);
      _recordHistoryFromRecipes(nextThree);

      setState(() {
        _recipes.clear();
        _recipes.addAll(nextThree);
      });

      if (_recipeStock.length < 3) {
        _fetchAndStockRecipes(forceRefresh: true);
      }
    } else {
      _fetchAndStockRecipes(forceRefresh: true);
    }
  }

  Future _fetchAndStockRecipes({required bool forceRefresh}) async {
    if (_recipes.isNotEmpty) {
      _recordHistoryFromRecipes(_recipes);
    }
    if (_recipeStock.isNotEmpty) {
      _recordHistoryFromRecipes(_recipeStock);
    }

    if (mounted && _recipes.isEmpty) {
      setState(() {
        _isLoadingRecipes = true;
        _errorMessage = '';
      });
    }

    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      if (mounted) {
        setState(() {
          _isLoadingRecipes = false;
          _errorMessage = 'AIチャット画面（ai_chat_screen.dart）にAPIキーを設定してください。';
        });
      }
      return;
    }

    final now = DateTime.now();
    final todayKey = _getTodayKey();
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');

    final selectedMoodObj = _moodChips.firstWhere(
      (m) => (m as Map)['label'] == _selectedMood,
      orElse: () => _moodChips.first,
    ) as Map;
    final moodRule = selectedMoodObj['rule'].toString();

    final bannedTitlesText = _recentTitles.isEmpty
        ? 'なし'
        : _recentTitles.join('、');
    final bannedIngsText = _recentIngredients.isEmpty
        ? 'なし'
        : _recentIngredients.join('、');

    final prompt =
        '一人暮らしの自炊レシピを合計9品（3品×3セット分）考案し、JSON配列のみで出力してください。\n'
        '【絶対条件】\n'
        '1. 使用禁止の調理家電：【$missingText】（これらを使う調理工程は一切含めないこと）\n'
        '2. 選択ジャンル：【$_selectedMood】→ $moodRule\n'
        '3. 特定地域の名産品や郷土料理への偏りは一切禁止。全国どこのスーパーでも安く買える一般的な食材で作ること。\n'
        '4. 直近に表示した以下の食材と料理は【使用禁止】とし、全く別の主材料・別の野菜で考案すること：\n'
        '   ・使用禁止の食材：【$bannedIngsText】\n'
        '   ・出力禁止の料理名：【$bannedTitlesText】\n'
        '5. 9品すべて異なる料理名、異なる主材料にすること。\n'
        '6. 分量はすべて「1人分」を基準に具体的な数値（g、個、大さじ、小さじ等）で書くこと。\n\n'
        '以下のJSON配列フォーマットのみで9品分を出力してください（前後の説明文やMarkdown記号は不要）：\n'
        '[\n'
        '  {\n'
        '    "id": "r_${now.millisecondsSinceEpoch}_1",\n'
        '    "title": "料理名",\n'
        '    "time": "約10分",\n'
        '    "cost": "約180円",\n'
        '    "ingredients": ["材料名 分量", "調味料名 分量"],\n'
        '    "steps": ["手順1", "手順2", "手順3"]\n'
        '  }\n'
        ']';

    List? parsedList;
    Object? lastErr;

    final List liteModels = [
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash-lite',
      'gemini-3.5-flash',
    ];

    for (final modelItem in liteModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
        );
        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 25));
        final rawText = response.text ?? '';
        if (rawText.trim().isNotEmpty) {
          final jsonStr = _extractJsonArray(rawText);
          final decoded = jsonDecode(jsonStr);
          if (decoded is List && decoded.isNotEmpty) {
            parsedList = decoded;
            break;
          }
        }
      } catch (e) {
        lastErr = e;
      }
    }

    if (!mounted) return;

    if (parsedList != null && parsedList.isNotEmpty) {
      _recordHistoryFromRecipes(parsedList);

      setState(() {
        if (_recipes.isEmpty) {
          _recipes.addAll(parsedList!.take(3));
          if (parsedList!.length > 3) {
            _recipeStock = parsedList!.skip(3).toList();
          }
        } else {
          _recipeStock.addAll(parsedList!);
        }
        _isLoadingRecipes = false;
        _errorMessage = '';
      });

      if (_currentUserId.isNotEmpty) {
        FirebaseFirestore.instance.collection('users').doc(_currentUserId).set({
          'dailyRecipesDate': todayKey,
          'dailyRecipes': [..._recipes, ..._recipeStock],
        }, SetOptions(merge: true));
      }
    } else {
      if (_recipes.isEmpty) {
        setState(() {
          _isLoadingRecipes = false;
          _errorMessage = 'レシピの取得に失敗しました。もう一度お試しください。\n($lastErr)';
        });
      }
    }
  }

  bool _isRecipeSaved(String title) {
    return _savedRecipes.any((item) => (item as Map)['title'] == title);
  }

  Future _toggleSaveRecipe(Map recipe) async {
    if (_currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final title = recipe['title']?.toString() ?? '';
    final alreadySaved = _isRecipeSaved(title);

    setState(() {
      if (alreadySaved) {
        _savedRecipes.removeWhere((item) => (item as Map)['title'] == title);
      } else {
        _savedRecipes.add(recipe);
      }
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'savedCookingRecipeItems': _savedRecipes,
          }, SetOptions(merge: true));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            alreadySaved ? '「$title」の保存を解除しました' : '「$title」を保存したレシピに追加しました！',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {}
  }

  Future _askAiSubstitution({
    required Map recipe,
    String? targetIngredient,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AIが代用・アレンジ案を考えています...')),
          ],
        ),
      ),
    );

    final title = recipe['title']?.toString() ?? '料理';
    final List ingList = List.from(recipe['ingredients'] ?? []);
    final List stepList = List.from(recipe['steps'] ?? []);
    final missingText = _cachedMissingAppliances.isEmpty
        ? '特になし'
        : _cachedMissingAppliances.join('、');

    final prompt = targetIngredient != null
        ? '料理「$title」（材料：${ingList.join('、')}）を作る際、「$targetIngredient」が家にありません。\n'
              '一人暮らしの家によくある身近な食材や調味料で代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$title」（材料：${ingList.join('、')} / 手順：${stepList.join('→')}）について、\n'
              '持っていない調理家電【$missingText】を使わず、さらに安く手軽に作れる代替食材やアレンジのコツを200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String replyText = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelItem in [
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash-lite',
    ]) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 15));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          replyText = res.text!.trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetIngredient != null
                    ? '「$targetIngredient」の代用案'
                    : '「$title」のAI代替提案',
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          '自炊レシピ',
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
        children: [_buildDailyTab(), _buildSavedTab()],
      ),
    );
  }

  Widget _buildDailyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.wb_sunny_outlined,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _seasonLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _isLoadingRecipes ? null : _onPressNextMenu,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text(
                  '別メニューにする',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: Row(
            children: _moodChips.map((chipItem) {
              final mapItem = chipItem as Map;
              final emoji = mapItem['emoji'].toString();
              final label = mapItem['label'].toString();
              final isSelected = _selectedMood == label;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _isLoadingRecipes
                      ? null
                      : () {
                          setState(() {
                            _selectedMood = label;
                            _recipeStock.clear();
                            _recipes.clear();
                          });
                          _fetchAndStockRecipes(forceRefresh: true);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orange.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.orange.shade400
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(
                            Icons.check,
                            size: 15,
                            color: Colors.orange.shade900,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.orange.shade900
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: _isLoadingRecipes
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        '「$_selectedMood」の新メニューを考案中...',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
              : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _fetchAndStockRecipes(forceRefresh: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('再試行する'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: 110,
                  ),
                  itemCount: _recipes.length,
                  itemBuilder: (context, index) {
                    final recipe = Map.from(_recipes[index] as Map);
                    return _buildRecipeCard(recipe);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSavedTab() {
    if (_savedRecipes.isEmpty) {
      return const Center(
        child: Text(
          '保存したレシピはまだありません。\n気に入ったレシピのブックマークを押して保存しよう！',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 110),
      itemCount: _savedRecipes.length,
      itemBuilder: (context, index) {
        final recipe = Map.from(_savedRecipes[index] as Map);
        return _buildRecipeCard(recipe);
      },
    );
  }

  Widget _buildRecipeCard(Map recipe) {
    final String title = recipe['title']?.toString() ?? 'おすすめレシピ';
    final String time = recipe['time']?.toString() ?? '約10分';
    final String rawCost = recipe['cost']?.toString() ?? '約200円';
    final List ingredients = List.from(recipe['ingredients'] ?? []);
    final List steps = List.from(recipe['steps'] ?? []);

    final int currentServings = (_servingsPerRecipe[title] as int?) ?? 1;
    final String scaledCost = _scaleTextWithRatio(rawCost, currentServings);
    final bool isSaved = _isRecipeSaved(title);

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _askAiSubstitution(recipe: recipe),
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: Colors.orange,
                  ),
                  label: const Text(
                    'AI 代替提案',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: isSaved ? Colors.blue : Colors.black54,
                  ),
                  onPressed: () => _toggleSaveRecipe(recipe),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(time),
                  ],
                ),
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
                      '$scaledCost（$currentServings人分）',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '【材料】（$currentServings人分）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: currentServings > 1
                            ? () {
                                setState(() {
                                  _servingsPerRecipe[title] =
                                      currentServings - 1;
                                });
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          '$currentServings人分',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: currentServings < 6
                            ? () {
                                setState(() {
                                  _servingsPerRecipe[title] =
                                      currentServings + 1;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...ingredients.map((ing) {
              final rawIng = ing.toString();
              final scaledIng = _scaleTextWithRatio(rawIng, currentServings);
              final ingNameOnly = rawIng.split(RegExp(r'[\s :：]')).first;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scaledIng,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _askAiSubstitution(
                        recipe: recipe,
                        targetIngredient: ingNameOnly,
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 15),
                      label: const Text('代用案', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            const Text(
              '【作り方】',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...List.generate(steps.length, (idx) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${idx + 1}. ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        steps[idx].toString(),
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
