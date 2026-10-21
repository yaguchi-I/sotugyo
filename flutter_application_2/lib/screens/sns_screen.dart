import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SnsScreen extends StatefulWidget {
  const SnsScreen({super.key});

  @override
  State<SnsScreen> createState() => _SnsScreenState();
}

class _SnsScreenState extends State<SnsScreen> {
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
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text('まだ投稿がありません。最初の投稿をしてみましょう！')),
                );
              }

              final docs = snapshot.data!.docs;

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;
                  return _buildPostCard(data, docId);
                }, childCount: docs.length),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, String docId) {
    final bool hasImage = post['hasImage'] ?? false;
    final int replies = post['replies'] ?? 0;
    final int likes = post['likes'] ?? 0;
    final int helpfuls = post['helpfuls'] ?? 0;

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
                post['userName'] ?? '名無し',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post['content'] ?? '', style: const TextStyle(fontSize: 15)),
          if (hasImage) const SizedBox(height: 12),
          if (hasImage)
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
                count: replies,
                onTap: () {},
              ),
              _buildActionButton(
                icon: Icons.favorite_border,
                color: Colors.pink,
                count: likes,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('posts')
                      .doc(docId)
                      .update({'likes': FieldValue.increment(1)});
                },
              ),
              _buildActionButton(
                icon: Icons.thumb_up_off_alt,
                color: Colors.blue,
                count: helpfuls,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('posts')
                      .doc(docId)
                      .update({'helpfuls': FieldValue.increment(1)});
                },
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_border, color: Colors.black54),
                onPressed: () {},
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
            Icon(icon, color: Colors.black54, size: 22),
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
