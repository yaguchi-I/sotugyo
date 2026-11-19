import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sns_detail_screen.dart';
import 'sns_reply_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? initialIconBase64;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.initialIconBase64,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // true: いいね順、false: 新着順
  bool _sortByLikes = true;

  Uint8List? _decodeBase64(String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    final cleaned = rawBase64.contains(',')
        ? rawBase64.split(',').last.replaceAll(RegExp(r'\s+'), '')
        : rawBase64.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    try {
      final decoded = base64Decode(cleaned);
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  int _readReactionCount(dynamic rawCount, List fallbackList) {
    if (rawCount is num) {
      return max(0, max(rawCount.toInt(), fallbackList.length));
    }
    if (rawCount != null) {
      final parsed = int.tryParse(rawCount.toString().trim());
      if (parsed != null) {
        return max(0, max(parsed, fallbackList.length));
      }
    }
    return fallbackList.length;
  }

  Future<void> _toggleReaction(
    String docId,
    String listField,
    String countField,
    List currentUsers,
    int currentDisplayCount,
  ) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('posts').doc(docId);
    final isAdded = currentUsers.contains(currentUserId);

    try {
      if (isAdded) {
        final nextCount = currentDisplayCount > 0 ? currentDisplayCount - 1 : 0;
        await docRef.update({
          listField: FieldValue.arrayRemove([currentUserId]),
          countField: nextCount,
        });
      } else {
        final nextCount = currentDisplayCount + 1;
        await docRef.update({
          listField: FieldValue.arrayUnion([currentUserId]),
          countField: nextCount,
        });
      }
    } catch (_) {}
  }

  bool _belongsToTargetUser(Map<String, dynamic> data) {
    final postUserId = data['userId']?.toString() ?? '';
    final postUserName = data['userName']?.toString() ?? '';

    if (widget.userId.isNotEmpty && postUserId.isNotEmpty) {
      return postUserId == widget.userId;
    }
    return postUserName == widget.userName;
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            if (count != 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.userId.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(widget.userId)
                .snapshots()
          : null,
      builder: (context, userSnap) {
        String displayName = widget.userName;
        String iconBase64 = widget.initialIconBase64 ?? '';

        if (userSnap.hasData &&
            userSnap.data != null &&
            userSnap.data!.exists &&
            userSnap.data!.data() != null) {
          final uData = userSnap.data!.data()!;
          final fetchedName = uData['userName']?.toString().trim() ?? '';
          if (fetchedName.isNotEmpty) {
            displayName = fetchedName;
          }
          final fetchedIcon = uData['iconBase64']?.toString() ?? '';
          if (fetchedIcon.isNotEmpty) {
            iconBase64 = fetchedIcon;
          }
        }

        final Uint8List? iconBytes = _decodeBase64(iconBase64);

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0.5,
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .snapshots(),
            builder: (context, postSnap) {
              if (postSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (postSnap.hasError) {
                return Center(child: Text('読み込みエラー: ${postSnap.error}'));
              }

              final allDocs = postSnap.data?.docs ?? [];
              final userPosts = allDocs.where((doc) {
                final data = doc.data();
                if (data['mainCategory'] == 'AI') return false;
                return _belongsToTargetUser(data);
              }).toList();

              userPosts.sort((a, b) {
                final dataA = a.data();
                final dataB = b.data();
                if (_sortByLikes) {
                  final likedA = dataA['likedUsers'] is List
                      ? List.from(dataA['likedUsers'])
                      : const [];
                  final likedB = dataB['likedUsers'] is List
                      ? List.from(dataB['likedUsers'])
                      : const [];
                  final likesA = _readReactionCount(dataA['likes'], likedA);
                  final likesB = _readReactionCount(dataB['likes'], likedB);
                  return likesB.compareTo(likesA);
                } else {
                  final tsA = dataA['createdAt'];
                  final tsB = dataB['createdAt'];
                  if (tsA is Timestamp && tsB is Timestamp) {
                    return tsB.compareTo(tsA);
                  }
                  return 0;
                }
              });

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: CustomScrollView(
                    slivers: [
                      // X風プロフィールヘッダー
                      SliverToBoxAdapter(
                        child: Container(
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 110,
                                width: double.infinity,
                                color: Colors.blueGrey.shade100,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Transform.translate(
                                      offset: const Offset(0, -36),
                                      child: CircleAvatar(
                                        radius: 40,
                                        backgroundColor: Colors.white,
                                        child: CircleAvatar(
                                          radius: 37,
                                          backgroundColor: Colors.blue.shade100,
                                          backgroundImage: iconBytes != null
                                              ? MemoryImage(iconBytes)
                                              : null,
                                          child: iconBytes == null
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 40,
                                                  color: Colors.blue,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                    Transform.translate(
                                      offset: const Offset(0, -20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF111111),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${userPosts.length} 件のポスト',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'ポスト一覧',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        ChoiceChip(
                                          label: const Text('いいね順'),
                                          selected: _sortByLikes,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setState(() => _sortByLikes = true);
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('新着順'),
                                          selected: !_sortByLikes,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setState(
                                                () => _sortByLikes = false,
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          ),
                        ),
                      ),

                      // ポスト一覧
                      if (userPosts.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'まだポストはありません',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final doc = userPosts[index];
                              final post = doc.data();
                              final title = post['title']?.toString() ?? '';
                              final content = post['content']?.toString() ?? '';

                              final List likedUsers = post['likedUsers'] is List
                                  ? List.from(post['likedUsers'])
                                  : const [];
                              final List helpfulUsers =
                                  post['helpfulUsers'] is List
                                  ? List.from(post['helpfulUsers'])
                                  : const [];
                              final List savedUsers = post['savedUsers'] is List
                                  ? List.from(post['savedUsers'])
                                  : const [];

                              final bool isLiked =
                                  currentUserId.isNotEmpty &&
                                  likedUsers.contains(currentUserId);
                              final bool isHelpful =
                                  currentUserId.isNotEmpty &&
                                  helpfulUsers.contains(currentUserId);
                              final bool isSaved =
                                  currentUserId.isNotEmpty &&
                                  savedUsers.contains(currentUserId);

                              final int repliesCount = _readReactionCount(
                                post['replies'],
                                const [],
                              );
                              final int likesCount = _readReactionCount(
                                post['likes'],
                                likedUsers,
                              );
                              final int helpfulsCount = _readReactionCount(
                                post['helpfuls'],
                                helpfulUsers,
                              );
                              final int savesCount = _readReactionCount(
                                post['saves'],
                                savedUsers,
                              );

                              return InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SnsDetailScreen(postId: doc.id),
                                    ),
                                  );
                                },
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: Colors.blue.shade100,
                                            backgroundImage: iconBytes != null
                                                ? MemoryImage(iconBytes)
                                                : null,
                                            child: iconBytes == null
                                                ? const Icon(
                                                    Icons.person,
                                                    color: Colors.blue,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  displayName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                if (title.trim().isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      title,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                if (content.trim().isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      content,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceAround,
                                                  children: [
                                                    _buildActionButton(
                                                      icon: Icons
                                                          .chat_bubble_outline,
                                                      color: Colors.grey,
                                                      count: repliesCount,
                                                      onTap: () {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                SnsReplyScreen(
                                                                  postId: doc.id,
                                                                  originalPost:
                                                                      post,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    _buildActionButton(
                                                      icon: isLiked
                                                          ? Icons.favorite
                                                          : Icons.favorite_border,
                                                      color: isLiked
                                                          ? Colors.pink
                                                          : Colors.grey,
                                                      count: likesCount,
                                                      onTap: () => _toggleReaction(
                                                        doc.id,
                                                        'likedUsers',
                                                        'likes',
                                                        likedUsers,
                                                        likesCount,
                                                      ),
                                                    ),
                                                    _buildActionButton(
                                                      icon: isHelpful
                                                          ? Icons.lightbulb
                                                          : Icons
                                                                .lightbulb_outline,
                                                      color: isHelpful
                                                          ? Colors.orange
                                                          : Colors.grey,
                                                      count: helpfulsCount,
                                                      onTap: () => _toggleReaction(
                                                        doc.id,
                                                        'helpfulUsers',
                                                        'helpfuls',
                                                        helpfulUsers,
                                                        helpfulsCount,
                                                      ),
                                                    ),
                                                    _buildActionButton(
                                                      icon: isSaved
                                                          ? Icons.bookmark
                                                          : Icons.bookmark_border,
                                                      color: isSaved
                                                          ? Colors.blue
                                                          : Colors.grey,
                                                      count: 0,
                                                      onTap: () => _toggleReaction(
                                                        doc.id,
                                                        'savedUsers',
                                                        'saves',
                                                        savedUsers,
                                                        savesCount,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 1),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: userPosts.length,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}



