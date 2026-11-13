import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sns_reply_screen.dart';

class SnsDetailScreen extends StatefulWidget {
  final String postId;

  const SnsDetailScreen({super.key, required this.postId});

  @override
  State createState() => _SnsDetailScreenState();
}

class _SnsDetailScreenState extends State {
  String get _postId => (widget as SnsDetailScreen).postId;

  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentEmailPrefix =
      FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? '';

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
  }

  void _openFullScreenImage(
    BuildContext context,
    Uint8List imageBytes,
    String heroTag,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        pageBuilder: (pageContext, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(pageContext).pop(),
                ),
              ),
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(pageContext).pop(),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Hero(
                      tag: heroTag,
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿の詳細・返信一覧'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(_postId)
            .snapshots(),
        builder: (context, postSnapshot) {
          if (postSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!postSnapshot.hasData || postSnapshot.data == null) {
            return const Center(child: Text('投稿が見つかりません'));
          }

          final postDoc = postSnapshot.data as DocumentSnapshot;
          if (!postDoc.exists || postDoc.data() == null) {
            return const Center(child: Text('投稿が見つかりません'));
          }

          final dynamic post = postDoc.data();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildOriginalPostSection(post)),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Text(
                    '返信一覧',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(_postId)
                    .collection('replies')
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, replySnapshot) {
                  if (replySnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }
                  if (!replySnapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'まだ返信がありません',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  final querySnap = replySnapshot.data as QuerySnapshot;
                  if (querySnap.docs.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'まだ返信がありません',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final dynamic replyData = querySnap.docs[index].data();
                      return _buildReplyCard(replyData);
                    }, childCount: querySnap.docs.length),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final doc = await FirebaseFirestore.instance
              .collection('posts')
              .doc(_postId)
              .get();
          if (!mounted || !doc.exists) return;
          final dynamic postData = doc.data();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  SnsReplyScreen(postId: _postId, originalPost: postData),
            ),
          );
        },
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.reply),
        label: const Text('返信する'),
      ),
    );
  }

  Widget _buildOriginalPostSection(dynamic post) {
    final bool hasImage = post['hasImage'] ?? false;
    final int replies = post['replies'] ?? 0;

    final List likedUsers = post['likedUsers'] != null
        ? List.from(post['likedUsers'])
        : [];
    final List helpfulUsers = post['helpfulUsers'] != null
        ? List.from(post['helpfulUsers'])
        : [];
    final List savedUsers = post['savedUsers'] != null
        ? List.from(post['savedUsers'])
        : [];

    final bool isLiked = likedUsers.contains(currentUserId);
    final bool isHelpful = helpfulUsers.contains(currentUserId);
    final bool isSaved = savedUsers.contains(currentUserId);

    final String postUserId = post['userId']?.toString() ?? '';
    final String rawUserName = post['userName']?.toString() ?? '名無し';
    final String targetLookupUid = postUserId.isNotEmpty
        ? postUserId
        : (currentEmailPrefix.isNotEmpty && rawUserName == currentEmailPrefix
              ? currentUserId
              : '');

    final Uint8List? postImageBytes = _decodeBase64(
      post['imageBase64']?.toString(),
    );
    final String heroTag = 'detail_img_$_postId';

    return StreamBuilder(
      stream: targetLookupUid.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(targetLookupUid)
                .snapshots()
          : null,
      builder: (context, userSnapshot) {
        String displayUserName = rawUserName;
        String displayIconBase64 = post['userIconBase64']?.toString() ?? '';

        if (userSnapshot.hasData && userSnapshot.data != null) {
          final userDoc = userSnapshot.data as DocumentSnapshot;
          if (userDoc.exists && userDoc.data() != null) {
            final dynamic uData = userDoc.data();
            if (uData['userName'] != null &&
                uData['userName'].toString().trim().isNotEmpty) {
              displayUserName = uData['userName'].toString().trim();
            }
            if (uData['iconBase64'] != null &&
                uData['iconBase64'].toString().isNotEmpty) {
              displayIconBase64 = uData['iconBase64'].toString();
            }
          }
        }

        final Uint8List? userIconBytes = _decodeBase64(displayIconBase64);

        return Container(
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
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey,
                    backgroundImage: userIconBytes != null
                        ? MemoryImage(userIconBytes)
                        : null,
                    child: userIconBytes == null
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: [
                        Text(
                          displayUserName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
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
                              post['mainCategory'].toString(),
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
                              post['subCategory'].toString(),
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
              const SizedBox(height: 14),
              Text(
                post['content']?.toString() ?? '',
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              if (hasImage && postImageBytes != null) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () =>
                      _openFullScreenImage(context, postImageBytes, heroTag),
                  child: Hero(
                    tag: heroTag,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 350),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          postImageBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
                          builder: (context) => SnsReplyScreen(
                            postId: _postId,
                            originalPost: post,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildActionButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.pink : Colors.black54,
                    count: likedUsers.length,
                    onTap: () {
                      if (currentUserId.isEmpty) return;
                      final docRef = FirebaseFirestore.instance
                          .collection('posts')
                          .doc(_postId);
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
                    count: helpfulUsers.length,
                    onTap: () {
                      if (currentUserId.isEmpty) return;
                      final docRef = FirebaseFirestore.instance
                          .collection('posts')
                          .doc(_postId);
                      if (isHelpful) {
                        docRef.update({
                          'helpfulUsers': FieldValue.arrayRemove([
                            currentUserId,
                          ]),
                        });
                      } else {
                        docRef.update({
                          'helpfulUsers': FieldValue.arrayUnion([
                            currentUserId,
                          ]),
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
                          .doc(_postId);
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
        );
      },
    );
  }

  Widget _buildReplyCard(dynamic reply) {
    final String replyUserId = reply['userId']?.toString() ?? '';
    final String rawReplyName = reply['userName']?.toString() ?? '名無し';
    final String targetLookupUid = replyUserId.isNotEmpty
        ? replyUserId
        : (currentEmailPrefix.isNotEmpty && rawReplyName == currentEmailPrefix
              ? currentUserId
              : '');

    return StreamBuilder(
      stream: targetLookupUid.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(targetLookupUid)
                .snapshots()
          : null,
      builder: (context, userSnapshot) {
        String displayName = rawReplyName;
        String displayIconBase64 = reply['userIconBase64']?.toString() ?? '';

        if (userSnapshot.hasData && userSnapshot.data != null) {
          final userDoc = userSnapshot.data as DocumentSnapshot;
          if (userDoc.exists && userDoc.data() != null) {
            final dynamic uData = userDoc.data();
            if (uData['userName'] != null &&
                uData['userName'].toString().trim().isNotEmpty) {
              displayName = uData['userName'].toString().trim();
            }
            if (uData['iconBase64'] != null &&
                uData['iconBase64'].toString().isNotEmpty) {
              displayIconBase64 = uData['iconBase64'].toString();
            }
          }
        }

        final Uint8List? iconBytes = _decodeBase64(displayIconBase64);

        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey,
                backgroundImage: iconBytes != null
                    ? MemoryImage(iconBytes)
                    : null,
                child: iconBytes == null
                    ? const Icon(Icons.person, color: Colors.white, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reply['content']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
              count != 0 ? count.toString() : '',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
