import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sns_detail_screen.dart';
import 'sns_reply_screen.dart';

class SnsSearchScreen extends StatefulWidget {
  const SnsSearchScreen({super.key});

  @override
  State<SnsSearchScreen> createState() => _SnsSearchScreenState();
}

class _SnsSearchScreenState extends State<SnsSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _searchQuery = '';
  String _selectedTag = 'すべて';

  final List<String> _tags = ['すべて', 'トレンド', '料理', '掃除', '収納', 'その他'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('検索'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: '検索...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tags.length,
              itemBuilder: (context, index) {
                final tag = _tags[index];
                final isSelected = _selectedTag == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(tag),
                    selected: isSelected,
                    selectedColor: Colors.blue.shade100,
                    backgroundColor: Colors.grey.shade200,
                    side: BorderSide.none,
                    onSelected: (selected) {
                      setState(() {
                        _selectedTag = tag;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedTag == 'トレンド' ? 'トレンドの投稿（いいね順）' : '検索結果・人気の投稿',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('まだ投稿がありません。'));
                }

                final docs = snapshot.data!.docs;

                final filteredDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final content = (data['content'] ?? '')
                      .toString()
                      .toLowerCase();
                  final userName = (data['userName'] ?? '')
                      .toString()
                      .toLowerCase();
                  final mainCategory = (data['mainCategory'] ?? '').toString();
                  final subCategory = (data['subCategory'] ?? '').toString();

                  final matchesQuery =
                      _searchQuery.isEmpty ||
                      content.contains(_searchQuery) ||
                      userName.contains(_searchQuery);

                  bool matchesTag = true;
                  if (_selectedTag == 'すべて' || _selectedTag == 'トレンド') {
                    matchesTag = true;
                  } else {
                    matchesTag =
                        mainCategory == _selectedTag ||
                        subCategory == _selectedTag;
                  }

                  return matchesQuery && matchesTag;
                }).toList();

                filteredDocs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;

                  if (_selectedTag == 'トレンド') {
                    final aLikes = (aData['likedUsers'] is List)
                        ? (aData['likedUsers'] as List).length
                        : 0;
                    final bLikes = (bData['likedUsers'] is List)
                        ? (bData['likedUsers'] as List).length
                        : 0;
                    if (aLikes != bLikes) {
                      return bLikes.compareTo(aLikes);
                    }
                  }

                  final aTime = aData['createdAt'] as Timestamp?;
                  final bTime = bData['createdAt'] as Timestamp?;
                  if (aTime == null || bTime == null) return 0;
                  return bTime.compareTo(aTime);
                });

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      '該当する投稿が見つかりませんでした',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final data =
                        filteredDocs[index].data() as Map<String, dynamic>;
                    final docId = filteredDocs[index].id;
                    return _buildPostCard(data, docId, context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(
    Map<String, dynamic> post,
    String docId,
    BuildContext context,
  ) {
    final bool hasImage = post['hasImage'] ?? false;
    final int replies = post['replies'] ?? 0;

    final List<dynamic> likedUsers = post['likedUsers'] != null
        ? List<dynamic>.from(post['likedUsers'])
        : [];
    final List<dynamic> helpfulUsers = post['helpfulUsers'] != null
        ? List<dynamic>.from(post['helpfulUsers'])
        : [];
    final List<dynamic> savedUsers = post['savedUsers'] != null
        ? List<dynamic>.from(post['savedUsers'])
        : [];

    final bool isLiked = likedUsers.contains(currentUserId);
    final bool isHelpful = helpfulUsers.contains(currentUserId);
    final bool isSaved = savedUsers.contains(currentUserId);

    final int likesCount = likedUsers.length;
    final int helpfulsCount = helpfulUsers.length;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SnsDetailScreen(postId: docId),
          ),
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [
                      Text(
                        post['userName'] ?? '名無し',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (post['mainCategory'] != null &&
                          post['mainCategory'] != '指定なし')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            post['mainCategory'],
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      if (post['subCategory'] != null &&
                          post['subCategory'] != '指定なし')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            post['subCategory'],
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                    ],
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SnsReplyScreen(postId: docId, originalPost: post),
                      ),
                    );
                  },
                ),
                _buildActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.pink : Colors.black54,
                  count: likesCount,
                  onTap: () {
                    if (currentUserId.isEmpty) return;
                    final docRef = FirebaseFirestore.instance
                        .collection('posts')
                        .doc(docId);
                    if (isLiked) {
                      docRef.update({
                        'likedUsers': FieldValue.arrayRemove([currentUserId]),
                      });
                    } else {
                      docRef.update({
                        'likedUsers': FieldValue.arrayUnion([currentUserId]),
                      });
                    }
                  },
                ),
                _buildActionButton(
                  icon: isHelpful ? Icons.thumb_up : Icons.thumb_up_off_alt,
                  color: isHelpful ? Colors.blue : Colors.black54,
                  count: helpfulsCount,
                  onTap: () {
                    if (currentUserId.isEmpty) return;
                    final docRef = FirebaseFirestore.instance
                        .collection('posts')
                        .doc(docId);
                    if (isHelpful) {
                      docRef.update({
                        'helpfulUsers': FieldValue.arrayRemove([currentUserId]),
                      });
                    } else {
                      docRef.update({
                        'helpfulUsers': FieldValue.arrayUnion([currentUserId]),
                      });
                    }
                  },
                ),
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: isSaved ? Colors.blue : Colors.black54,
                  ),
                  onPressed: () {
                    if (currentUserId.isEmpty) return;
                    final docRef = FirebaseFirestore.instance
                        .collection('posts')
                        .doc(docId);
                    if (isSaved) {
                      docRef.update({
                        'savedUsers': FieldValue.arrayRemove([currentUserId]),
                      });
                    } else {
                      docRef.update({
                        'savedUsers': FieldValue.arrayUnion([currentUserId]),
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        ),
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
