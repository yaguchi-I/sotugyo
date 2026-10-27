import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _categories = [
    'すべて',
    '野菜',
    '肉類',
    '魚介',
    '麺類',
    'パン類',
    'その他',
  ];
  String _selectedCategory = 'すべて';

  final List<Map<String, dynamic>> _recipes = [
    {
      'id': '1',
      'title': 'もやしの絶品ナムル',
      'category': '野菜',
      'imageUrl': null,
      'isSaved': false,
      'ingredients': [
        {'name': 'もやし', 'amount': '1袋', 'isSeasoning': false},
        {'name': '豚肉', 'amount': '100g', 'isSeasoning': false},
        {'name': 'ごま油', 'amount': '大さじ1', 'isSeasoning': true},
        {'name': '鶏ガラスープの素', 'amount': '小さじ1', 'isSeasoning': true},
        {'name': 'にんにくチューブ', 'amount': '2cm', 'isSeasoning': true},
      ],
      'steps': [
        'もやしを水洗いして水気を切り、耐熱ボウルに入れてレンジで3分加熱する。',
        '豚肉を一口大に切り、フライパンで炒める。',
        'もやしの水気を再度しっかり絞り、炒めた豚肉と合わせる。',
        'ごま油、鶏ガラスープの素、にんにくを加えてよく和える。',
      ],
    },
    {
      'id': '2',
      'title': '昔ながらの醤油ラーメン',
      'category': '麺類',
      'imageUrl': null,
      'isSaved': true,
      'ingredients': [
        {'name': '中華麺', 'amount': '1玉', 'isSeasoning': false},
        {'name': '醤油', 'amount': '大さじ2', 'isSeasoning': true},
        {'name': 'みりん', 'amount': '大さじ1', 'isSeasoning': true},
      ],
      'steps': [
        '鍋にお湯を沸かし、中華麺を規定の時間茹でる。',
        '器に醤油、みりんを入れて熱湯で割る。',
        '茹で上がった麺を湯切りして器に入れる。',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String> _getAiSubstitute(String ingredientName) async {
    const apiKey = 'AQ.Ab8RN6Jn2XETWXDUPF1FGrXmKebuBvhnGUhCNInEZglzJVPVSw';
    final model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(
        'あなたはプロの料理研究家です。'
        '指定された調味料がない場合の代替案と、その分量の目安を提案してください。'
        '回答は日本語で、スマホで読みやすいよう短く簡潔にしてください。'
        'Markdownの記号は使わず、プレーンテキストで書いてください。',
      ),
    );

    final chatSession = model.startChat();
    final prompt = '「$ingredientName」の代わりになる調味料と分量を教えてください。';

    try {
      final response = await chatSession.sendMessage(Content.text(prompt));
      return response.text ?? '代替案が見つかりませんでした。';
    } catch (e) {
      if (e.toString().contains('503') ||
          e.toString().contains('high demand')) {
        return '現在AIのサーバーが大変混み合っています。\n少し待ってからもう一度お試しください。';
      }
      return 'エラーが起きました。APIキーが設定されているか確認してね。\n詳細: $e';
    }
  }

  void _showAiSubstituteDialog(String ingredientName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.blue),
              SizedBox(width: 8),
              Text('AI 代替提案'),
            ],
          ),
          content: FutureBuilder<String>(
            future: _getAiSubstitute(ingredientName),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return SingleChildScrollView(child: Text(snapshot.data ?? ''));
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  void _toggleSave(int index) {
    setState(() {
      _recipes[index]['isSaved'] = !_recipes[index]['isSaved'];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_recipes[index]['isSaved'] ? '保存しました' : '保存を解除しました'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('料理サポート'),
        elevation: 0,
        backgroundColor: Colors.transparent,
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
        children: [_buildRecipeContent(0), _buildSavedContent()],
      ),
    );
  }

  Widget _buildRecipeContent(int index) {
    final recipe = _recipes[index];
    final ingredients = recipe['ingredients'] as List<Map<String, dynamic>>;
    final steps = recipe['steps'] as List<String>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  recipe['title'],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(
                      recipe['isSaved']
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: recipe['isSaved'] ? Colors.blue : null,
                    ),
                    onPressed: () => _toggleSave(index),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.restaurant, size: 60, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '材料',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          ...ingredients.map(
            (ingredient) => _buildIngredientRow(
              ingredient['name'],
              ingredient['amount'],
              ingredient['isSeasoning'],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '手順',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          ...steps.asMap().entries.map(
            (entry) => _buildStepRow((entry.key + 1).toString(), entry.value),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(String name, String amount, bool isSeasoning) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          if (isSeasoning)
            ElevatedButton.icon(
              onPressed: () => _showAiSubstituteDialog(name),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('代替'),
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(60, 30),
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue,
                elevation: 0,
              ),
            )
          else
            const SizedBox(width: 85),
          const SizedBox(width: 16),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
          Text(amount, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildStepRow(String step, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue,
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedContent() {
    final savedRecipes = _recipes
        .where((recipe) => recipe['isSaved'] == true)
        .toList();
    final filteredRecipes = _selectedCategory == 'すべて'
        ? savedRecipes
        : savedRecipes
              .where((recipe) => recipe['category'] == _selectedCategory)
              .toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: _categories.map((category) {
              final isSelected = _selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = category);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filteredRecipes.isEmpty
              ? const Center(
                  child: Text(
                    '保存されたレシピがありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: filteredRecipes.length,
                  itemBuilder: (context, index) {
                    final recipe = filteredRecipes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12.0),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {},
                        child: Row(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.restaurant,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    recipe['title'],
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      recipe['category'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.bookmark,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                final originalIndex = _recipes.indexWhere(
                                  (r) => r['id'] == recipe['id'],
                                );
                                if (originalIndex != -1) {
                                  _toggleSave(originalIndex);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
