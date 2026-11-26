import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sns_detail_screen.dart';
import 'sns_reply_screen.dart';

enum _ProfilePostSortOrder {
  likes,
  helpful,
  newest,
}

enum _ProfilePostFilter {
  all,
  withImages,
}

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
  static final RegExp _hashtagRegex = RegExp(
    r'[#＃]([^\s#＃、,。\.!！?？\(\)（）「」『』【】]+)',
  );

  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  _ProfilePostSortOrder _sortOrder = _ProfilePostSortOrder.likes;
  _ProfilePostFilter _postFilter = _ProfilePostFilter.all;
  bool _isTogglingFollow = false;

  final Map<String, Map<String, dynamic>> _postImageCache = {};

  bool get _canFollowTarget =>
      currentUserId.isNotEmpty &&
      widget.userId.isNotEmpty &&
      currentUserId != widget.userId;

  List<String> _extractHashtagsFromText(String text) {
    final List<String> result = [];
    if (text.trim().isEmpty) return result;
    for (final match in _hashtagRegex.allMatches(text)) {
      final tag = (match.group(1) ?? '').trim();
      if (tag.isNotEmpty && !result.contains(tag)) {
        result.add(tag);
      }
    }
    return result;
  }

  List<String> _extractHashtagsFromPost(Map<String, dynamic> post) {
    final List<String> result = [];
    if (post['hashtags'] is List) {
      for (final raw in List.from(post['hashtags'])) {
        final cleaned = (raw?.toString() ?? '')
            .trim()
            .replaceFirst(RegExp(r'^[#＃]+'), '')
            .trim();
        if (cleaned.isNotEmpty && !result.contains(cleaned)) {
          result.add(cleaned);
        }
      }
    }
    final titleTags = _extractHashtagsFromText(post['title']?.toString() ?? '');
    final contentTags =
        _extractHashtagsFromText(post['content']?.toString() ?? '');
    for (final tag in [...titleTags, ...contentTags]) {
      if (!result.contains(tag)) {
        result.add(tag);
      }
    }
    return result;
  }

  Widget _buildHighlightedContent(String content) {
    final List<TextSpan> spans = [];
    int lastEnd = 0;

    for (final match in _hashtagRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: content.substring(lastEnd, match.start),
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.black87,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: content.substring(match.start, match.end),
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(lastEnd),
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.black87,
          ),
        ),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  List<String> _readStringList(Map<String, dynamic> data, String key) {
    final raw = data[key];
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _formatDateLabel(dynamic rawTimestamp) {
    if (rawTimestamp is! Timestamp) return '';
    final dt = rawTimestamp.toDate();
    final now = DateTime.now();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    if (dt.year == now.year) {
      return '$month/$day';
    }
    return '${dt.year}/$month/$day';
  }

  String get _sortLabel {
    switch (_sortOrder) {
      case _ProfilePostSortOrder.likes:
        return 'いいね順';
      case _ProfilePostSortOrder.helpful:
        return '役に立った順';
      case _ProfilePostSortOrder.newest:
        return '新着順';
    }
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    if (!_canFollowTarget || _isTogglingFollow) return;

    setState(() {
      _isTogglingFollow = true;
    });

    final currentUserRef =
        FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final targetUserRef =
        FirebaseFirestore.instance.collection('users').doc(widget.userId);

    try {
      if (currentlyFollowing) {
        await currentUserRef.set({
          'followingUsers': FieldValue.arrayRemove([widget.userId]),
          'following': FieldValue.arrayRemove([widget.userId]),
        }, SetOptions(merge: true));

        await targetUserRef.set({
          'followerUsers': FieldValue.arrayRemove([currentUserId]),
          'followers': FieldValue.arrayRemove([currentUserId]),
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('フォローを解除しました'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        await currentUserRef.set({
          'followingUsers': FieldValue.arrayUnion([widget.userId]),
          'following': FieldValue.arrayUnion([widget.userId]),
        }, SetOptions(merge: true));

        await targetUserRef.set({
          'followerUsers': FieldValue.arrayUnion([currentUserId]),
          'followers': FieldValue.arrayUnion([currentUserId]),
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('フォローしました！タイムラインの「フォロー中」に表示されます'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('フォロー処理に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFollow = false;
        });
      }
    }
  }

  void _openIconLightbox(BuildContext context, Uint8List? iconBytes) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double avatarDiameter = min(320.0, screenWidth * 0.72);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'アイコンを閉じる',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: const SizedBox.expand(),
                  ),
                ),
                Center(
                  child: IgnorePointer(
                    child: Container(
                      width: avatarDiameter,
                      height: avatarDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.shade100,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: iconBytes != null
                          ? Image.memory(
                              iconBytes,
                              width: avatarDiameter,
                              height: avatarDiameter,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Icon(
                              Icons.person,
                              size: avatarDiameter * 0.5,
                              color: Colors.blue,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

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

  Uint8List? _decodeAndCacheImage(String cacheKey, String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    final cleaned = rawBase64.contains(',')
        ? rawBase64.split(',').last.replaceAll(RegExp(r'\s+'), '')
        : rawBase64.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;

    final existing = _postImageCache[cacheKey];
    if (existing != null &&
        existing['srcLen'] == cleaned.length &&
        existing['bytes'] is Uint8List) {
      return existing['bytes'] as Uint8List;
    }

    try {
      final decoded = base64Decode(cleaned);
      if (decoded.isEmpty) return null;
      _postImageCache[cacheKey] = {'srcLen': cleaned.length, 'bytes': decoded};
      return decoded;
    } catch (_) {
      return null;
    }
  }

  List<Uint8List> _extractPostImages(String docId, Map<String, dynamic> post) {
    final List<Uint8List> result = [];
    if (post['imagesBase64'] != null && post['imagesBase64'] is List) {
      final rawList = List.from(post['imagesBase64']);
      for (int i = 0; i < rawList.length; i++) {
        final bytes = _decodeAndCacheImage(
          '${docId}_$i',
          rawList[i]?.toString(),
        );
        if (bytes != null) {
          result.add(bytes);
        }
      }
    }
    if (result.isEmpty && post['imageBase64'] != null) {
      final bytes = _decodeAndCacheImage(
        '${docId}_single',
        post['imageBase64']?.toString(),
      );
      if (bytes != null) {
        result.add(bytes);
      }
    }
    return result;
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

  Widget _buildSortChip({
    required _ProfilePostSortOrder value,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final bool selected = _sortOrder == value;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : Colors.grey.shade700,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: activeColor,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: selected ? activeColor : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.white : Colors.black87,
      ),
      shape: const StadiumBorder(),
      onSelected: (isSelected) {
        if (isSelected) {
          setState(() => _sortOrder = value);
        }
      },
    );
  }

  Widget _buildImageFilterChip(int imagePostCount) {
    final bool selected = _postFilter == _ProfilePostFilter.withImages;
    return FilterChip(
      avatar: Icon(
        Icons.image_outlined,
        size: 16,
        color: selected ? Colors.blue.shade800 : Colors.grey.shade700,
      ),
      label: Text('画像付き ($imagePostCount)'),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: Colors.blue.shade50,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: selected ? Colors.blue : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.blue.shade900 : Colors.black87,
      ),
      shape: const StadiumBorder(),
      onSelected: (isSelected) {
        setState(() {
          _postFilter = isSelected
              ? _ProfilePostFilter.withImages
              : _ProfilePostFilter.all;
        });
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            if (count > 0) ...[
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
        int followingCount = 0;
        int followerCount = 0;

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

          final followingSet = <String>{
            ..._readStringList(uData, 'followingUsers'),
            ..._readStringList(uData, 'following'),
          };
          final followerSet = <String>{
            ..._readStringList(uData, 'followerUsers'),
            ..._readStringList(uData, 'followers'),
          };
          followingCount = followingSet.length;
          followerCount = followerSet.length;
        }

        final Uint8List? iconBytes = _decodeBase64(iconBase64);

        return StreamBuilder<DocumentSnapshot>(
          stream: currentUserId.isNotEmpty
              ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUserId)
                    .snapshots()
              : null,
          builder: (context, meSnap) {
            final Set<String> myFollowingSet = {};
            if (meSnap.hasData &&
                meSnap.data != null &&
                meSnap.data!.exists &&
                meSnap.data!.data() != null) {
              final meData = meSnap.data!.data() as Map<String, dynamic>;
              myFollowingSet.addAll(_readStringList(meData, 'followingUsers'));
              myFollowingSet.addAll(_readStringList(meData, 'following'));
            }
            final bool isFollowingTarget =
                widget.userId.isNotEmpty && myFollowingSet.contains(widget.userId);

            return Scaffold(
              backgroundColor: Colors.grey.shade100,
              appBar: AppBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0.5,
                title: Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              body: StreamBuilder(
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
                  final allUserPosts = allDocs.where((doc) {
                    final data = doc.data();
                    if (data['mainCategory'] == 'AI') return false;
                    return _belongsToTargetUser(data);
                  }).toList();

                  final Map<String, List<Uint8List>> imagesByDocId = {};
                  int imagePostCount = 0;

                  for (final doc in allUserPosts) {
                    final imgs = _extractPostImages(doc.id, doc.data());
                    imagesByDocId[doc.id] = imgs;
                    if (imgs.isNotEmpty) {
                      imagePostCount++;
                    }
                  }

                  final userPosts = allUserPosts.where((doc) {
                    if (_postFilter == _ProfilePostFilter.withImages) {
                      return (imagesByDocId[doc.id]?.isNotEmpty ?? false);
                    }
                    return true;
                  }).toList();

                  userPosts.sort((a, b) {
                    final dataA = a.data();
                    final dataB = b.data();
                    switch (_sortOrder) {
                      case _ProfilePostSortOrder.likes:
                        final likedA = dataA['likedUsers'] is List
                            ? List.from(dataA['likedUsers'])
                            : const [];
                        final likedB = dataB['likedUsers'] is List
                            ? List.from(dataB['likedUsers'])
                            : const [];
                        final likesA =
                            _readReactionCount(dataA['likes'], likedA);
                        final likesB =
                            _readReactionCount(dataB['likes'], likedB);
                        if (likesB != likesA) {
                          return likesB.compareTo(likesA);
                        }
                        break;
                      case _ProfilePostSortOrder.helpful:
                        final helpfulA = dataA['helpfulUsers'] is List
                            ? List.from(dataA['helpfulUsers'])
                            : const [];
                        final helpfulB = dataB['helpfulUsers'] is List
                            ? List.from(dataB['helpfulUsers'])
                            : const [];
                        final helpfulsA = _readReactionCount(
                          dataA['helpfuls'],
                          helpfulA,
                        );
                        final helpfulsB = _readReactionCount(
                          dataB['helpfuls'],
                          helpfulB,
                        );
                        if (helpfulsB != helpfulsA) {
                          return helpfulsB.compareTo(helpfulsA);
                        }
                        break;
                      case _ProfilePostSortOrder.newest:
                        break;
                    }
                    final tsA = dataA['createdAt'];
                    final tsB = dataB['createdAt'];
                    if (tsA is Timestamp && tsB is Timestamp) {
                      return tsB.compareTo(tsA);
                    }
                    return 0;
                  });

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: CustomScrollView(
                        slivers: [
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Transform.translate(
                                          offset: const Offset(0, -36),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              GestureDetector(
                                                onTap: () => _openIconLightbox(
                                                  context,
                                                  iconBytes,
                                                ),
                                                child: CircleAvatar(
                                                  radius: 40,
                                                  backgroundColor: Colors.white,
                                                  child: CircleAvatar(
                                                    radius: 37,
                                                    backgroundColor:
                                                        Colors.blue.shade100,
                                                    backgroundImage:
                                                        iconBytes != null
                                                            ? MemoryImage(
                                                                iconBytes,
                                                              )
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
                                              if (_canFollowTarget)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    bottom: 4,
                                                  ),
                                                  child: isFollowingTarget
                                                      ? OutlinedButton(
                                                          onPressed:
                                                              _isTogglingFollow
                                                                  ? null
                                                                  : () =>
                                                                      _toggleFollow(
                                                                        true,
                                                                      ),
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                Colors.black87,
                                                            side: BorderSide(
                                                              color: Colors
                                                                  .grey
                                                                  .shade400,
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                20,
                                                              ),
                                                            ),
                                                          ),
                                                          child: _isTogglingFollow
                                                              ? const SizedBox(
                                                                  width: 16,
                                                                  height: 16,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              : const Text(
                                                                  'フォロー中',
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                        )
                                                      : ElevatedButton(
                                                          onPressed:
                                                              _isTogglingFollow
                                                                  ? null
                                                                  : () =>
                                                                      _toggleFollow(
                                                                        false,
                                                                      ),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.blue,
                                                            foregroundColor:
                                                                Colors.white,
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                20,
                                                              ),
                                                            ),
                                                          ),
                                                          child: _isTogglingFollow
                                                              ? const SizedBox(
                                                                  width: 16,
                                                                  height: 16,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                )
                                                              : const Text(
                                                                  'フォローする',
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                        ),
                                                ),
                                            ],
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
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 14,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    '$followingCount フォロー中',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  Text(
                                                    '$followerCount フォロワー',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${allUserPosts.length} 件のポスト',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color:
                                                          Colors.grey.shade800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
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
                                            Text(
                                              '$_sortLabel・${_postFilter == _ProfilePostFilter.withImages ? '画像付き' : 'すべて'} (${userPosts.length}件)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _buildSortChip(
                                                value: _ProfilePostSortOrder
                                                    .likes,
                                                label: 'いいね順',
                                                icon: Icons.favorite,
                                                activeColor: Colors.pink.shade500,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildSortChip(
                                                value: _ProfilePostSortOrder
                                                    .helpful,
                                                label: '役に立った順',
                                                icon: Icons.lightbulb,
                                                activeColor:
                                                    Colors.orange.shade600,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildSortChip(
                                                value: _ProfilePostSortOrder
                                                    .newest,
                                                label: '新着順',
                                                icon: Icons.schedule,
                                                activeColor: Colors.blue.shade600,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildImageFilterChip(
                                                imagePostCount,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                ],
                              ),
                            ),
                          ),

                          if (userPosts.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 48,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _postFilter ==
                                              _ProfilePostFilter.withImages
                                          ? Icons.image_not_supported_outlined
                                          : Icons.article_outlined,
                                      size: 44,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _postFilter ==
                                              _ProfilePostFilter.withImages
                                          ? '画像付きのポストはありません'
                                          : 'まだポストはありません',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (_postFilter ==
                                        _ProfilePostFilter.withImages) ...[
                                      const SizedBox(height: 12),
                                      OutlinedButton(
                                        onPressed: () {
                                          setState(() {
                                            _postFilter =
                                                _ProfilePostFilter.all;
                                          });
                                        },
                                        child: const Text('すべてのポストを表示'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final doc = userPosts[index];
                                  final post = doc.data();
                                  final mainCategory =
                                      post['mainCategory']?.toString().trim() ??
                                      '';
                                  final subCategory =
                                      post['subCategory']?.toString().trim() ??
                                      '';
                                  final title =
                                      post['title']?.toString().trim() ?? '';
                                  final content =
                                      post['content']?.toString().trim() ?? '';
                                  final postHashtags =
                                      _extractHashtagsFromPost(post);
                                  final dateLabel = _formatDateLabel(
                                    post['createdAt'],
                                  );
                                  final postImages = imagesByDocId[doc.id] ??
                                      _extractPostImages(doc.id, post);

                                  final List likedUsers =
                                      post['likedUsers'] is List
                                          ? List.from(post['likedUsers'])
                                          : const [];
                                  final List helpfulUsers =
                                      post['helpfulUsers'] is List
                                          ? List.from(post['helpfulUsers'])
                                          : const [];
                                  final List savedUsers =
                                      post['savedUsers'] is List
                                          ? List.from(post['savedUsers'])
                                          : const [];

                                  final bool isLiked = currentUserId.isNotEmpty &&
                                      likedUsers.contains(currentUserId);
                                  final bool isHelpful =
                                      currentUserId.isNotEmpty &&
                                      helpfulUsers.contains(currentUserId);
                                  final bool isSaved = currentUserId.isNotEmpty &&
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

                                  return Column(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SnsDetailScreen(
                                                    postId: doc.id,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          color: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 20,
                                                backgroundColor:
                                                    Colors.blue.shade100,
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
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Wrap(
                                                            crossAxisAlignment:
                                                                WrapCrossAlignment
                                                                    .center,
                                                            spacing: 6,
                                                            runSpacing: 4,
                                                            children: [
                                                              Text(
                                                                displayName,
                                                                style:
                                                                    const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                              if (mainCategory
                                                                      .isNotEmpty &&
                                                                  mainCategory !=
                                                                      '指定なし')
                                                                Container(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        2,
                                                                  ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .blue
                                                                        .shade50,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      12,
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    mainCategory,
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .blue
                                                                          .shade800,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                ),
                                                              if (subCategory
                                                                      .isNotEmpty &&
                                                                  subCategory !=
                                                                      '指定なし')
                                                                Container(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        2,
                                                                  ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .grey
                                                                        .shade100,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      12,
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    subCategory,
                                                                    style:
                                                                        const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (dateLabel
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            dateLabel,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey
                                                                  .shade500,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    if (title.isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          top: 6,
                                                        ),
                                                        child: Text(
                                                          title,
                                                          style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 15,
                                                            height: 1.35,
                                                          ),
                                                        ),
                                                      ),
                                                    if (content.isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          top: 4,
                                                        ),
                                                        child:
                                                            _buildHighlightedContent(
                                                          content,
                                                        ),
                                                      ),
                                                    if (postHashtags.isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          top: 8,
                                                        ),
                                                        child: Wrap(
                                                          spacing: 6,
                                                          runSpacing: 6,
                                                          children: [
                                                            for (final tag
                                                                in postHashtags)
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      8,
                                                                  vertical:
                                                                      3,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .indigo
                                                                      .shade50,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    12,
                                                                  ),
                                                                  border: Border
                                                                      .all(
                                                                    color: Colors
                                                                        .indigo
                                                                        .shade100,
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '#$tag',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .indigo
                                                                        .shade700,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    if (postImages.isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          top: 10,
                                                        ),
                                                        child:
                                                            _ProfilePostImageCarousel(
                                                          imagesList:
                                                              postImages,
                                                          keyPrefix:
                                                              'up_${doc.id}',
                                                        ),
                                                      ),
                                                    const SizedBox(height: 10),
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
                                                                  postId:
                                                                      doc.id,
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
                                                              : Icons
                                                                  .favorite_border,
                                                          color: isLiked
                                                              ? Colors.pink
                                                              : Colors.grey,
                                                          count: likesCount,
                                                          onTap: () =>
                                                              _toggleReaction(
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
                                                          onTap: () =>
                                                              _toggleReaction(
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
                                                              : Icons
                                                                  .bookmark_border,
                                                          color: isSaved
                                                              ? Colors.blue
                                                              : Colors.grey,
                                                          count: savesCount,
                                                          onTap: () =>
                                                              _toggleReaction(
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
                                        ),
                                      ),
                                      Divider(
                                        height: 1,
                                        color: Colors.grey.shade200,
                                      ),
                                    ],
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
      },
    );
  }
}

class _ProfilePostImageCarousel extends StatefulWidget {
  final List<Uint8List> imagesList;
  final String keyPrefix;

  const _ProfilePostImageCarousel({
    required this.imagesList,
    required this.keyPrefix,
  });

  @override
  State<_ProfilePostImageCarousel> createState() =>
      _ProfilePostImageCarouselState();
}

class _ProfilePostImageCarouselState extends State<_ProfilePostImageCarousel> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreenGallery(int initialIndex) {
    final images = widget.imagesList;
    final PageController fullCtrl = PageController(initialPage: initialIndex);
    int currentFullIdx = initialIndex;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (pageContext, animation, secondaryAnimation) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return FadeTransition(
                opacity: animation,
                child: Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    title: images.length > 1
                        ? Text(
                            '${currentFullIdx + 1} / ${images.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          )
                        : null,
                    leading: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(pageContext).pop(),
                    ),
                  ),
                  body: Stack(
                    alignment: Alignment.center,
                    children: [
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(ctx).copyWith(
                          dragDevices: PointerDeviceKind.values.toSet(),
                        ),
                        child: PageView.builder(
                          controller: fullCtrl,
                          itemCount: images.length,
                          onPageChanged: (idx) {
                            setModalState(() {
                              currentFullIdx = idx;
                            });
                          },
                          itemBuilder: (_, idx) {
                            return InteractiveViewer(
                              panEnabled: true,
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: Center(
                                child: Image.memory(
                                  images[idx],
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (images.length > 1 && currentFullIdx > 0)
                        Positioned(
                          left: 16,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white24,
                            ),
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () {
                              fullCtrl.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                          ),
                        ),
                      if (images.length > 1 &&
                          currentFullIdx < images.length - 1)
                        Positioned(
                          right: 16,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white24,
                            ),
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () {
                              fullCtrl.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imagesList;
    if (images.isEmpty) return const SizedBox.shrink();
    final int total = images.length;
    final int safeIndex = _currentIndex >= total ? 0 : _currentIndex;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: total,
                    onPageChanged: (idx) {
                      setState(() {
                        _currentIndex = idx;
                      });
                    },
                    itemBuilder: (context, idx) {
                      return GestureDetector(
                        onTap: () => _openFullScreenGallery(idx),
                        child: Image.memory(
                          images[idx],
                          key: ValueKey('${widget.keyPrefix}_$idx'),
                          width: double.infinity,
                          height: 240,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 36,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (total > 1)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${safeIndex + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (total > 1 && safeIndex > 0)
                  Positioned(
                    left: 8,
                    child: InkWell(
                      onTap: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                if (total > 1 && safeIndex < total - 1)
                  Positioned(
                    right: 8,
                    child: InkWell(
                      onTap: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (idx) {
                  final isSelected = idx == safeIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isSelected ? 16 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}