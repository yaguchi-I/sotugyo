import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sns_detail_screen.dart';

class SnsBookmarkScreen extends StatefulWidget {
  const SnsBookmarkScreen({super.key});

  @override
  State<SnsBookmarkScreen> createState() => _SnsBookmarkScreenState();
}

class _SnsBookmarkScreenState extends State<SnsBookmarkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  final List<String> _mainTabs = ['すべて', '料理', '掃除', '収納', 'AI'];

  final Map<String, List<String>> _subTags = {
    'すべて': [],
    '料理': ['すべて', '野菜', '肉類', '麺類', '作り置き'],
    '掃除': ['すべて', 'キッチン', 'お風呂', 'トイレ', 'リビング'],
    '収納': ['すべて', 'クローゼット', 'デスク周り', '小物'],
    'AI': ['すべて', 'レシピ', '節約術', 'その他'],
  };

  String _selectedSubTag = 'すべて';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _mainTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedSubTag = 'すべて';
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSave(String docId) {
    if (currentUserId.isEmpty) return;
    FirebaseFirestore.instance.collection('posts').doc(docId).update({
      'savedUsers': FieldValue.arrayRemove([currentUserId]),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存フォルダ'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _mainTabs.map((tab) => Tab(text: tab)).toList(),
        ),
      ),
      body: currentUserId.isEmpty
          ? const Center(child: Text('ログインしていません'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .where('savedUsers', arrayContains: currentUserId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      '保存された項目がありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final List<dynamic> docs = snapshot.data!.docs.toList();
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['createdAt'] as Timestamp?;
                  final bTime = bData['createdAt'] as Timestamp?;
                  if (aTime == null || bTime == null) return 0;
                  return bTime.compareTo(aTime);
                });

                return TabBarView(
                  controller: _tabController,
                  children: _mainTabs.map((mainTab) {
                    if (mainTab == 'すべて') {
                      return _buildTimelineTab(docs);
                    } else {
                      return _buildCategoryTab(docs, mainTab);
                    }
                  }).toList(),
                );
              },
            ),
    );
  }

  Widget _buildTimelineTab(List<dynamic> docs) {
    return ListView.separated(
      itemCount: docs.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: Colors.grey.shade300),
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final docId = docs[index].id;

        return InkWell(
          onTap: () {
            if (data['mainCategory'] == 'AI') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiRecipeDetailScreen(postId: docId),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SnsDetailScreen(postId: docId),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: data['mainCategory'] == 'AI'
                      ? Colors.purple.shade100
                      : Colors.blue.shade100,
                  child: Icon(
                    data['mainCategory'] == 'AI'
                        ? Icons.auto_awesome
                        : Icons.person,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['userName'] ?? '名無し',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data['content'] ?? '',
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                      if (data['hasImage'] == true) ...[
                        const SizedBox(height: 12),
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.image,
                            color: Colors.grey,
                            size: 40,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.bookmark,
                              color: Colors.blue,
                              size: 20,
                            ),
                            onPressed: () => _toggleSave(docId),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTab(List<dynamic> docs, String mainCategory) {
    final currentSubTags = _subTags[mainCategory] ?? [];

    final filteredItems = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final docMainCategory = data['mainCategory'] ?? 'その他';
      final docSubCategory = data['subCategory'] ?? 'その他';

      final matchMain = docMainCategory == mainCategory;
      final matchSub =
          _selectedSubTag == 'すべて' || docSubCategory == _selectedSubTag;
      return matchMain && matchSub;
    }).toList();

    return Column(
      children: [
        if (currentSubTags.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: currentSubTags.map((tag) {
                final isSelected = _selectedSubTag == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(tag),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedSubTag = tag);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        if (currentSubTags.isNotEmpty) const Divider(height: 1),
        Expanded(
          child: filteredItems.isEmpty
              ? const Center(
                  child: Text(
                    'このカテゴリに保存された項目がありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final data =
                        filteredItems[index].data() as Map<String, dynamic>;
                    final docId = filteredItems[index].id;

                    return Card(
                      margin: const EdgeInsets.only(
                        bottom: 12.0,
                        left: 16.0,
                        right: 16.0,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          if (data['mainCategory'] == 'AI') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AiRecipeDetailScreen(postId: docId),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    SnsDetailScreen(postId: docId),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              color: Colors.grey.shade200,
                              child: Icon(
                                data['mainCategory'] == '料理'
                                    ? Icons.restaurant
                                    : data['mainCategory'] == '掃除'
                                    ? Icons.cleaning_services
                                    : data['mainCategory'] == 'AI'
                                    ? Icons.auto_awesome
                                    : Icons.inventory_2,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['userName'] ?? '名無し',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (data['content'] ?? '')
                                        .toString()
                                        .split('\n')
                                        .first,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: data['mainCategory'] == 'AI'
                                              ? Colors.purple.shade50
                                              : Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          data['mainCategory'] ?? '未分類',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: data['mainCategory'] == 'AI'
                                                ? Colors.purple.shade700
                                                : Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          data['subCategory'] ?? '未分類',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.bookmark,
                                color: Colors.blue,
                              ),
                              onPressed: () => _toggleSave(docId),
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

class AiRecipeDetailScreen extends StatelessWidget {
  final String postId;

  const AiRecipeDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('データが見つかりません'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final content = data['content'] ?? '';
          final subCategory = data['subCategory'] ?? 'レシピ';

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
