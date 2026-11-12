import 'dart:convert';

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

  List _recipes = [];
  List _savedRecipes = [];
  bool _isLoadingRecipes = true;
  String _errorMessage = '';
  String _seasonLabel = '';

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

  Future _initCookingData() async {
    final now = DateTime.now();
    final season = _getSeason(now.month);
    setState(() {
      _seasonLabel = '${now.month}月${now.day}日（$season）のAIおすすめ';
      _isLoadingRecipes = true;
      _errorMessage = '';
    });

    final todayKey = _getTodayKey();

    if (_currentUserId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          if (data['savedCookingRecipeItems'] != null) {
            _savedRecipes = List.from(data['savedCookingRecipeItems']);
          }
          if (data['dailyRecipesDate'] == todayKey &&
              data['dailyRecipes'] != null) {
            final cached = List.from(data['dailyRecipes']);
            if (cached.isNotEmpty) {
              setState(() {
                _recipes = cached;
                _isLoadingRecipes = false;
              });
              return;
            }
          }
        }
      } catch (e) {}
    }

    await _generateDailyRecipes(forceRefresh: false);
  }

  Future _generateDailyRecipes({required bool forceRefresh}) async {
    setState(() {
      _isLoadingRecipes = true;
      _errorMessage = '';
    });

    final now = DateTime.now();
    final season = _getSeason(now.month);
    final todayKey = _getTodayKey();
    final currentKey = AiChatScreen.apiKey.trim();

    try {
      List missingAppliances = [];
      String userArea = '日本';

      if (_currentUserId.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          if (data['missingAppliances'] != null) {
            missingAppliances = List.from(data['missingAppliances']);
          }
          if (data['area'] != null && data['area'].toString().isNotEmpty) {
            userArea = data['area'].toString();
          }
        }
      }

      final missingText = missingAppliances.isEmpty
          ? '特になし'
          : missingAppliances.join('、');

      final model = GenerativeModel(
        model: 'gemini-3.5-flash',
        apiKey: currentKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final variationNote = forceRefresh
          ? '先ほどとは異なる新しいバリエーションのメニューにしてください。'
          : '今日の日付と季節にぴったりの日替わりメニューにしてください。';

      final prompt =
          '今日は${now.year}年${now.month}月${now.day}日（季節：$season）です。\n'
          '居住地域：$userArea\n'
          '持っていない調理家電：$missingText\n'
          '$variationNote\n'
          '持っていない調理家電を一切使わず、季節（$season）の旬の食材やその時期の気候に合った一人暮らし向けの簡単・節約自炊レシピを3つ考案してください。\n'
          '以下のJSON配列フォーマットのみで出力してください。\n'
          '[\n'
          '  {\n'
          '    "id": "ユニークな英数字ID",\n'
          '    "title": "料理名",\n'
          '    "time": "約10分",\n'
          '    "cost": "約200円",\n'
          '    "ingredients": ["材料名 分量", "調味料名 分量"],\n'
          '    "steps": ["手順1の文章", "手順2の文章"]\n'
          '  }\n'
          ']';

      final response = await model.generateContent([Content.text(prompt)]);
      final rawText = response.text ?? '[]';
      final cleanedText = rawText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final decoded = jsonDecode(cleanedText);
      if (decoded is List && decoded.isNotEmpty) {
        final generatedList = List.from(decoded);
        setState(() {
          _recipes = generatedList;
          _isLoadingRecipes = false;
        });

        if (_currentUserId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUserId)
              .set({
                'dailyRecipesDate': todayKey,
                'dailyRecipes': generatedList,
              }, SetOptions(merge: true));
        }
      } else {
        setState(() {
          _errorMessage = 'レシピのデータ形式を変換できませんでした。再読み込みしてください。';
          _isLoadingRecipes = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'AIからのレシピ取得に失敗しました。\n詳細: $e';
        _isLoadingRecipes = false;
      });
    }
  }

  bool _isRecipeSaved(Map recipe) {
    final targetTitle = recipe['title']?.toString() ?? '';
    return _savedRecipes.any((r) => r['title']?.toString() == targetTitle);
  }

  Future _toggleSaveRecipe(Map recipe) async {
    if (_currentUserId.isEmpty) return;
    final targetTitle = recipe['title']?.toString() ?? '';

    setState(() {
      final exists = _savedRecipes.any(
        (r) => r['title']?.toString() == targetTitle,
      );
      if (exists) {
        _savedRecipes.removeWhere((r) => r['title']?.toString() == targetTitle);
      } else {
        _savedRecipes.add(Map.from(recipe));
      }
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'savedCookingRecipeItems': _savedRecipes,
          }, SetOptions(merge: true));
    } catch (e) {}
  }

  Future _showAiAlternativeDialog(
    Map recipe, {
    String? targetIngredient,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  targetIngredient != null
                      ? '「$targetIngredient」の代用案を考えています...'
                      : 'AIがレシピ全体の代替案を考えています...',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    String resultText = '';
    final currentKey = AiChatScreen.apiKey.trim();

    try {
      List missingAppliances = [];
      if (_currentUserId.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (userDoc.exists && userDoc.data()?['missingAppliances'] != null) {
          missingAppliances = List.from(userDoc.data()!['missingAppliances']);
        }
      }

      final missingText = missingAppliances.isEmpty
          ? '特になし'
          : missingAppliances.join('、');

      final model = GenerativeModel(
        model: 'gemini-3.5-flash',
        apiKey: currentKey,
      );

      final String prompt;
      if (targetIngredient != null) {
        prompt =
            '「${recipe['title']}」を作る際、【$targetIngredient】が家にない場合の代用アイデアを教えてください。\n'
            '【レシピ全体の材料】${(recipe['ingredients'] as List).join('、')}\n'
            '家にある一般的な調味料や身近な食材を使った具体的な代用方法と分量の目安を、150文字程度で簡潔に提案してください。Markdown記号は使わないでください。';
      } else {
        prompt =
            '以下のレシピについて、一人暮らし向けの代替提案をしてください。\n'
            '【料理名】${recipe['title']}\n'
            '【材料】${(recipe['ingredients'] as List).join('、')}\n'
            '【作り方】${(recipe['steps'] as List).join(' ')}\n'
            '【ユーザーが持っていない調理家電】$missingText\n\n'
            '持っていない家電を使わない調理法の代替案と、材料全体の代用・アレンジ案を、200文字程度で簡潔に提案してください。Markdown記号は使わないでください。';
      }

      final response = await model.generateContent([Content.text(prompt)]);
      resultText = response.text ?? '提案を生成できませんでした。';
    } catch (e) {
      resultText = 'エラーが起きました。APIキーが設定されているか確認してね。\n詳細: $e';
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetIngredient != null
                    ? '「$targetIngredient」の代用案'
                    : 'AI 代替提案（全体）',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            resultText,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
        title: const Text('自炊レシピ'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            tooltip: 'AIでおすすめを再生成',
            onPressed: _isLoadingRecipes
                ? null
                : () => _generateDailyRecipes(forceRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'おすすめ'),
            Tab(text: '保存済み'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRecommendedTab(),
          _savedRecipes.isEmpty
              ? const Center(
                  child: Text(
                    '保存済みのレシピがありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildRecipeList(_savedRecipes, showHeader: false),
        ],
      ),
    );
  }

  Widget _buildRecommendedTab() {
    if (_isLoadingRecipes) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '$_seasonLabel をAIが考案中...',
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _generateDailyRecipes(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('もう一度AIで生成する'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildRecipeList(_recipes, showHeader: true);
  }

  Widget _buildRecipeList(List recipes, {required bool showHeader}) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 120.0,
      ),
      itemCount: showHeader ? recipes.length + 1 : recipes.length,
      itemBuilder: (context, index) {
        if (showHeader && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.wb_sunny_outlined,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _seasonLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _generateDailyRecipes(forceRefresh: true),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('別メニューにする', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          );
        }

        final recipeIndex = showHeader ? index - 1 : index;
        final recipe = Map.from(recipes[recipeIndex] as Map);
        final isSaved = _isRecipeSaved(recipe);
        final ingredients = List.from(recipe['ingredients'] ?? []);
        final steps = List.from(recipe['steps'] ?? []);

        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        recipe['title']?.toString() ?? '無題のレシピ',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.auto_awesome,
                            color: Colors.blue,
                          ),
                          tooltip: 'レシピ全体のAI代替提案',
                          onPressed: () => _showAiAlternativeDialog(recipe),
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
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      recipe['time']?.toString() ?? '',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      recipe['cost']?.toString() ?? '',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Divider(height: 24),
                const Row(
                  children: [
                    Text('【材料】', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Text(
                      '※各材料の「代用案」で個別にAIへ聞けます',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...ingredients.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '・$item',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        InkWell(
                          onTap: () => _showAiAlternativeDialog(
                            recipe,
                            targetIngredient: item.toString(),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '代用案',
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '【作り方】',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...steps.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text('${entry.key + 1}. ${entry.value}'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
