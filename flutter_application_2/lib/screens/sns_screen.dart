import 'package:flutter/material.dart';

class SnsScreen extends StatefulWidget {
  const SnsScreen({super.key});

  @override
  State<SnsScreen> createState() => _SnsScreenState();
}

class _SnsScreenState extends State<SnsScreen> {
  final List<Map<String, dynamic>> posts = [
    {
      'userName': 'ユーザー1',
      'content': '今日の夕飯はもやし炒めを作りました。とても安く済んでよかったです。',
      'hasImage': false,
      'replies': 2,
      'likes': 15,
      'isLiked': false,
      'helpfuls': 5,
      'isHelpful': false,
      'isBookmarked': false,
    },
    {
      'userName': '節約の達人',
      'content': 'スーパーの特売日をカレンダーに登録しておくと、月の食費が5000円浮きました！おすすめの節約術があれば教えてください！',
      'hasImage': true,
      'replies': 8,
      'likes': 42,
      'isLiked': false,
      'helpfuls': 12,
      'isHelpful': false,
      'isBookmarked': false,
    },
    {
      'userName': '駆け出しエンジニア',
      'content': 'AIに相談したら、素晴らしい家計簿のつけ方を教えてもらえました。カテゴリ分けを細かくしすぎないのがコツみたいです。',
      'hasImage': false,
      'replies': 0,
      'likes': 8,
      'isLiked': false,
      'helpfuls': 2,
      'isHelpful': false,
      'isBookmarked': false,
    },
    {
      'userName': '料理勉強中',
      'content': '余った野菜で作れるスープのレシピを保存しました。今週末にまとめて作って冷凍しておこうと思います。',
      'hasImage': true,
      'replies': 1,
      'likes': 24,
      'isLiked': false,
      'helpfuls': 9,
      'isHelpful': false,
      'isBookmarked': false,
    },
    {
      'userName': 'マイホーム目標',
      'content': '今月の貯金目標達成！このままいけば来年には頭金が貯まりそうです。',
      'hasImage': false,
      'replies': 5,
      'likes': 105,
      'isLiked': false,
      'helpfuls': 30,
      'isHelpful': false,
      'isBookmarked': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('タイムライン'),
            floating: true,
            snap: true,
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final post = posts[index];
              return _buildPostCard(post, index);
            }, childCount: posts.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, int index) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                post['userName'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post['content'], style: const TextStyle(fontSize: 15)),
          if (post['hasImage']) const SizedBox(height: 12),
          if (post['hasImage'])
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image, size: 50, color: Colors.grey),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(
                icon: Icons.chat_bubble_outline,
                color: Colors.black54,
                count: post['replies'],
                onTap: () {},
              ),
              _buildActionButton(
                icon: post['isLiked'] ? Icons.favorite : Icons.favorite_border,
                color: post['isLiked'] ? Colors.pink : Colors.black54,
                count: post['likes'],
                onTap: () {
                  setState(() {
                    post['isLiked'] = !post['isLiked'];
                    post['likes'] += post['isLiked'] ? 1 : -1;
                  });
                },
              ),
              _buildActionButton(
                icon: post['isHelpful']
                    ? Icons.thumb_up
                    : Icons.thumb_up_off_alt,
                color: post['isHelpful'] ? Colors.blue : Colors.black54,
                count: post['helpfuls'],
                onTap: () {
                  setState(() {
                    post['isHelpful'] = !post['isHelpful'];
                    post['helpfuls'] += post['isHelpful'] ? 1 : -1;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  post['isBookmarked'] ? Icons.bookmark : Icons.bookmark_border,
                  color: post['isBookmarked'] ? Colors.black87 : Colors.black54,
                ),
                onPressed: () {
                  setState(() {
                    post['isBookmarked'] = !post['isBookmarked'];
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 4),
            Text(
              count > 0 ? count.toString() : '',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
