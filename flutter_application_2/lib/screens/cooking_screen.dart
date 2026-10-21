import 'package:flutter/material.dart';

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
        children: [
          _buildRecipeContent(),
          const Center(child: Text('保存済みのレシピ')),
        ],
      ),
    );
  }

  Widget _buildRecipeContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'もやしの〇〇〇〇',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_border),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            width: double.infinity,
            color: Colors.grey.shade300,
            child: const Center(
              child: Text('写真', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '材料',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          _buildIngredientRow('もやし', '1袋'),
          _buildIngredientRow('豚肉', '100g'),
          _buildIngredientRow('ごま油', '大さじ1'),
          const SizedBox(height: 24),
          const Text(
            '手順',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          _buildStepRow('1', 'もやしを水洗いして水気を切る。'),
          _buildStepRow('2', '豚肉を一口大に切る。'),
          _buildStepRow('3', 'フライパンにごま油を熱し、豚肉を炒める。'),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(String name, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(60, 30),
            ),
            child: const Text('代替'),
          ),
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
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}
