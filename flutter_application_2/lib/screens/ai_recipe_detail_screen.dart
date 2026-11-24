import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AiRecipeDetailScreen extends StatelessWidget {
  final String postId;

  const AiRecipeDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: FutureBuilder(
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('データが見つかりません'));
          }

          final docSnap = snapshot.data as DocumentSnapshot;
          if (!docSnap.exists || docSnap.data() == null) {
            return const Center(child: Text('データが見つかりません'));
          }

          final data = docSnap.data() as Map;
          final content = (data['content'] ?? '').toString();
          final subCategory = (data['subCategory'] ?? 'レシピ').toString();

          final bool isRecipe = subCategory == 'レシピ';

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 200,
                  color: isRecipe
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  child: Icon(
                    isRecipe ? Icons.restaurant_menu : Icons.lightbulb_outline,
                    size: 80,
                    color: isRecipe ? Colors.orange : Colors.green,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: isRecipe ? Colors.purple : Colors.teal,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRecipe ? 'AIが考えたあなた専用レシピ' : 'AIからの生活アドバイス',
                            style: TextStyle(
                              color: isRecipe
                                  ? Colors.purple.shade700
                                  : Colors.teal.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State createState() => _CookingScreenState();
}

class _CookingScreenState extends State with SingleTickerProviderStateMixin {
  static const String _apiKey = '';

  late TabController _tabController;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Set _savedRecipeIds = Set();

  final List _recipes = [
    {
      'id': 'recipe_1',
      'title': '豚こまともやしのスタミナ炒め',
      'time': '10分',
      'cost': '約200円',
      'ingredients': [
        '豚こま切れ肉 150g',
        'もやし 1袋',
        '醤油 大さじ1',
        '鶏ガラスープの素 小さじ1',
        'にんにくチューブ 2cm',
      ],
      'steps': [
        'もやしを水洗いして水気を切り、耐熱ボウルに入れてレンジで3分加熱する。',
        '豚肉を一口大に切り、フライパンで炒める。',
        'もやしの水気をしっかり絞り、炒めた豚肉と合わせる。',
        '調味料をすべて加えて手早く炒め合わせたら完成。',
      ],
    },
    {
      'id': 'recipe_2',
      'title': '包丁いらず！ツナと塩昆布の炊き込みご飯',
      'time': '40分',
      'cost': '約150円',
      'ingredients': ['米 2合', 'ツナ缶 1缶', '塩昆布 20g', '醤油 小さじ2', 'ごま油 小さじ1'],
      'steps': [
        '米を研いで炊飯釜に入れ、2合の目盛りまで水を入れる。',
        'ツナ缶（油ごと）、塩昆布、醤油を加えて軽く混ぜる。',
        '通常モードで炊飯する。',
        '炊き上がったらごま油を回しかけ、全体をさっくり混ぜて完成。',
      ],
    },
    {
      'id': 'recipe_3',
      'title': 'レンジで完結！ふわとろ親子丼',
      'time': '8分',
      'cost': '約180円',
      'ingredients': [
        '鶏もも肉（カット済み） 100g',
        '卵 2個',
        'めんつゆ（3倍濃縮） 大さじ2',
        '水 大さじ4',
        'ご飯 1膳',
      ],
      'steps': [
        '耐熱ボウルにめんつゆ、水、鶏肉を入れてふんわりラップをし、レンジで3分加熱する。',
        '溶き卵の3分の2を回し入れ、再度ラップをしてレンジで1分加熱する。',
        '残りの溶き卵を入れて軽く混ぜ、余熱で火を通す。',
        '温かいご飯の上にかけて完成。',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedRecipes();
  }

  Future _loadSavedRecipes() async {
    if (_currentUserId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      if (doc.exists && doc.data()?['savedCookingRecipes'] != null) {
        setState(() {
          _savedRecipeIds.addAll(List.from(doc.data()!['savedCookingRecipes']));
        });
      }
    } catch (e) {}
  }

  Future _toggleSaveRecipe(String recipeId) async {
    if (_currentUserId.isEmpty) return;
    setState(() {
      if (_savedRecipeIds.contains(recipeId)) {
        _savedRecipeIds.remove(recipeId);
      } else {
        _savedRecipeIds.add(recipeId);
      }
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'savedCookingRecipes': _savedRecipeIds.toList(),
          }, SetOptions(merge: true));
    } catch (e) {}
  }

  Future _showAiAlternativeDialog(Map recipe) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('AIが代替案を考えています...')),
            ],
          ),
        ),
      ),
    );

    String resultText = '';

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
        apiKey: _apiKey.trim(),
      );

      final prompt =
          '以下のレシピについて、一人暮らし向けの代替提案をしてください。\n'
          '【料理名】${recipe['title']}\n'
          '【材料】${(recipe['ingredients'] as List).join('、')}\n'
          '【作り方】${(recipe['steps'] as List).join(' ')}\n'
          '【ユーザーが持っていない調理家電】$missingText\n\n'
          '持っていない家電を使わない調理法の代替案と、足りない食材や調味料の代用アイデアを、200文字程度で簡潔に提案してください。Markdown記号は使わないでください。';

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
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.blue),
            SizedBox(width: 8),
            Text('AI 代替提案'),
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
    final savedRecipes = _recipes
        .where((r) => _savedRecipeIds.contains((r as Map)['id']))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('自炊レシピ'),
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
        children: [
          _buildRecipeList(_recipes),
          savedRecipes.isEmpty
              ? const Center(
                  child: Text(
                    '保存済みのレシピがありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildRecipeList(savedRecipes),
        ],
      ),
    );
  }

  Widget _buildRecipeList(List recipes) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 120.0,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index] as Map;
        final isSaved = _savedRecipeIds.contains(recipe['id']);
        final ingredients = List.from(recipe['ingredients']);
        final steps = List.from(recipe['steps']);

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
                        recipe['title'].toString(),
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
                          tooltip: 'AI代替提案',
                          onPressed: () => _showAiAlternativeDialog(recipe),
                        ),
                        IconButton(
                          icon: Icon(
                            isSaved ? Icons.bookmark : Icons.bookmark_border,
                            color: isSaved ? Colors.blue : Colors.grey,
                          ),
                          onPressed: () =>
                              _toggleSaveRecipe(recipe['id'].toString()),
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
                      recipe['time'].toString(),
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
                      recipe['cost'].toString(),
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Divider(height: 24),
                const Text(
                  '【材料】',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...ingredients.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('・$item'),
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
