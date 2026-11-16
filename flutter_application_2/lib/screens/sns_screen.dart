import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart';
import 'sns_reply_screen.dart';
import 'sns_detail_screen.dart';

class SnsScreen extends StatefulWidget {
  const SnsScreen({super.key});

  @override
  State createState() => _SnsScreenState();
}

class _SnsScreenState extends State {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentEmailPrefix =
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  final Map _servingsPerPost = {};
  final Map _postImageCache = {};
  final Map _userIconCache = {};

  Uint8List? _decodeAndCache(String cacheKey, String? rawBase64, Map cacheMap) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    final cleaned = rawBase64.contains(',')
        ? rawBase64.split(',').last.replaceAll(RegExp(r'\s+'), '')
        : rawBase64.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;

    final existing = cacheMap[cacheKey];
    if (existing != null &&
        existing is Map &&
        existing['srcLen'] == cleaned.length &&
        existing['bytes'] is Uint8List) {
      return existing['bytes'] as Uint8List;
    }

    try {
      final decoded = base64Decode(cleaned);
      if (decoded.isEmpty) return null;
      cacheMap[cacheKey] = {'srcLen': cleaned.length, 'bytes': decoded};
      return decoded;
    } catch (e) {
      return null;
    }
  }

  String _getTopicKey(dynamic post) {
    final mainCat = post['mainCategory']?.toString() ?? '指定なし';
    final subCat = post['subCategory']?.toString() ?? '指定なし';
    if (mainCat == '指定なし') return '';
    if (subCat != '指定なし' && subCat.isNotEmpty) {
      return '$mainCat:$subCat';
    }
    return mainCat;
  }

  int _calcRecommendScore(
    dynamic post,
    List interestedTags,
    List lessInterestedTopics,
  ) {
    final topicKey = _getTopicKey(post);
    final mainCat = post['mainCategory']?.toString() ?? '';

    if (topicKey.isNotEmpty && lessInterestedTopics.contains(topicKey)) {
      return 0;
    }
    if (topicKey.isNotEmpty && interestedTags.contains(topicKey)) {
      return 3;
    }
    if (mainCat.isNotEmpty &&
        interestedTags.any((t) => t.toString().startsWith('$mainCat:'))) {
      return 2;
    }
    return 1;
  }

  String _formatScaledNumber(double val) {
    if ((val - val.round()).abs() < 0.05) {
      return val.round().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _scaleAmountString(
    String rawAmount,
    int baseServings,
    int targetServings,
  ) {
    if (baseServings <= 0 || baseServings == targetServings) {
      return rawAmount;
    }
    final double ratio = targetServings / baseServings;

    final fractionRegex = RegExp(r'(\d+)\s*/\s*(\d+)');
    if (fractionRegex.hasMatch(rawAmount)) {
      return rawAmount.replaceAllMapped(fractionRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '1') ?? 1;
        final den = double.tryParse(match.group(2) ?? '1') ?? 1;
        if (den == 0) return match.group(0) ?? '';
        final scaled = (num / den) * ratio;
        return _formatScaledNumber(scaled);
      });
    }

    final decimalRegex = RegExp(r'(\d+(?:\.\d+)?)');
    if (decimalRegex.hasMatch(rawAmount)) {
      return rawAmount.replaceAllMapped(decimalRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '0') ?? 0;
        final scaled = num * ratio;
        return _formatScaledNumber(scaled);
      });
    }

    return '$rawAmount（×${_formatScaledNumber(ratio)}）';
  }

  Future _askAiIngredientSubstitution({
    required String dishTitle,
    required String targetIngredient,
    required List allIngredients,
    required List missingAppliances,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AIチャット画面でAPIキーを設定してください')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AIが代用・アレンジ案を考えています...')),
          ],
        ),
      ),
    );

    final ingNames = allIngredients
        .map((e) => '${(e as Map)['name'] ?? ''} ${(e)['amount'] ?? ''}')
        .join('、');
    final missingText = missingAppliances.isEmpty
        ? '特になし'
        : missingAppliances.join('、');

    final prompt =
        '料理「$dishTitle」（全体の材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
        '持っていない調理家電【$missingText】を使わず、一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdownの記号（*や#）は使わないでください。';

    String replyText = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelName in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelName.toString(),
          apiKey: currentKey,
        );
        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (response.text != null && response.text!.trim().isNotEmpty) {
          replyText = response.text!
              .replaceAll('**', '')
              .replaceAll('##', '')
              .trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '「$targetIngredient」の代用案',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            replyText,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _openFullScreenImage(Uint8List imageBytes) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
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
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
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

  Widget _buildTimelineImage(Uint8List imageBytes, String docId) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: GestureDetector(
        onTap: () => _openFullScreenImage(imageBytes),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            imageBytes,
            key: ValueKey('post_img_$docId'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                height: 120,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                    size: 36,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future _toggleReaction(
    String docId,
    String listField,
    String countField,
    List currentUsers,
  ) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('posts').doc(docId);
    final isAdded = currentUsers.contains(currentUserId);

    try {
      if (isAdded) {
        await docRef.update({
          listField: FieldValue.arrayRemove([currentUserId]),
          countField: FieldValue.increment(-1),
        });
      } else {
        await docRef.update({
          listField: FieldValue.arrayUnion([currentUserId]),
          countField: FieldValue.increment(1),
        });
      }
    } catch (e) {}
  }

  Future _deletePost(String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投稿の削除'),
        content: const Text('この投稿を削除してもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('posts').doc(docId).delete();
      _postImageCache.remove(docId);
      messenger.showSnackBar(const SnackBar(content: Text('投稿を削除しました')));
    }
  }

  Future _toggleTopicInterest(String topicKey, bool isCurrentlyDemoted) async {
    if (currentUserId.isEmpty || topicKey.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId);

    if (isCurrentlyDemoted) {
      await userRef.set({
        'lessInterestedTopics': FieldValue.arrayRemove([topicKey]),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(content: Text('「$topicKey」の表示制限を解除しました')),
      );
    } else {
      await userRef.set({
        'lessInterestedTopics': FieldValue.arrayUnion([topicKey]),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(content: Text('「$topicKey」の投稿を表示しにくくしました')),
      );
    }
  }

  Future _hidePost(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('posts').doc(docId).update({
      'hiddenUsers': FieldValue.arrayUnion([currentUserId]),
    });
    messenger.showSnackBar(const SnackBar(content: Text('この投稿を非表示にしました')));
  }

  Future _reportPost(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('posts').doc(docId).update({
      'reportedUsers': FieldValue.arrayUnion([currentUserId]),
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('投稿を通報しました。ご協力ありがとうございます。')),
    );
  }

  Future _blockUser(String targetKey, String displayName) async {
    if (currentUserId.isEmpty || targetKey.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('users').doc(currentUserId).set(
      {
        'blockedUsers': FieldValue.arrayUnion([targetKey]),
      },
      SetOptions(merge: true),
    );
    messenger.showSnackBar(SnackBar(content: Text('$displayName さんをブロックしました')));
  }

  void _showPostOptions({
    required String docId,
    required bool isMyPost,
    required String topicKey,
    required bool isTopicDemoted,
    required String targetUserKey,
    required String displayUserName,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              if (isMyPost)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'この投稿を削除する',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deletePost(docId);
                  },
                )
              else ...[
                if (topicKey.isNotEmpty)
                  ListTile(
                    leading: Icon(
                      isTopicDemoted
                          ? Icons.visibility_outlined
                          : Icons.thumb_down_outlined,
                    ),
                    title: Text(
                      isTopicDemoted
                          ? '「$topicKey」の表示制限を解除する'
                          : 'この話題（$topicKey）の表示を減らす',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _toggleTopicInterest(topicKey, isTopicDemoted);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('この投稿を非表示にする'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _hidePost(docId);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text('この投稿を通報する'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _reportPost(docId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: Text(
                    '$displayUserName さんをブロックする',
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _blockUser(targetUserKey, displayUserName);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
          title: const Text(
            'タイムライン',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            tabs: [
              Tab(text: 'おすすめ'),
              Tab(text: '最新'),
            ],
          ),
        ),
        body: StreamBuilder(
          stream: currentUserId.isNotEmpty
              ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUserId)
                    .snapshots()
              : null,
          builder: (context, userPrefSnap) {
            List interestedTags = [];
            List lessInterestedTopics = [];
            List blockedUsers = [];
            List missingAppliances = [];

            if (userPrefSnap.hasData && userPrefSnap.data != null) {
              final uDoc = userPrefSnap.data as DocumentSnapshot;
              if (uDoc.exists && uDoc.data() != null) {
                final uData = uDoc.data() as Map;
                if (uData['interestedTags'] != null) {
                  interestedTags = List.from(uData['interestedTags']);
                }
                if (uData['lessInterestedTopics'] != null) {
                  lessInterestedTopics = List.from(
                    uData['lessInterestedTopics'],
                  );
                }
                if (uData['blockedUsers'] != null) {
                  blockedUsers = List.from(uData['blockedUsers']);
                }
                if (uData['missingAppliances'] != null) {
                  missingAppliances = List.from(uData['missingAppliances']);
                }
              }
            }

            return StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data == null) {
                  return const Center(child: Text('まだ投稿がありません'));
                }

                final querySnap = snapshot.data as QuerySnapshot;
                final allDocs = querySnap.docs;

                final List visibleDocs = [];
                for (final doc in allDocs) {
                  final data = doc.data() as Map;
                  if (data['mainCategory'] == 'AI') continue;

                  final List hiddenUsers = data['hiddenUsers'] != null
                      ? List.from(data['hiddenUsers'])
                      : [];
                  if (hiddenUsers.contains(currentUserId)) continue;

                  final List reportedUsers = data['reportedUsers'] != null
                      ? List.from(data['reportedUsers'])
                      : [];
                  if (reportedUsers.length >= 3 ||
                      reportedUsers.contains(currentUserId)) {
                    continue;
                  }

                  final postUid = data['userId']?.toString() ?? '';
                  final postUName = data['userName']?.toString() ?? '';
                  if ((postUid.isNotEmpty && blockedUsers.contains(postUid)) ||
                      (postUName.isNotEmpty &&
                          blockedUsers.contains(postUName))) {
                    continue;
                  }

                  visibleDocs.add(doc);
                }

                final List recommendedDocs = List.from(visibleDocs);
                recommendedDocs.sort((a, b) {
                  final dataA = (a as QueryDocumentSnapshot).data() as Map;
                  final dataB = (b as QueryDocumentSnapshot).data() as Map;
                  final scoreA = _calcRecommendScore(
                    dataA,
                    interestedTags,
                    lessInterestedTopics,
                  );
                  final scoreB = _calcRecommendScore(
                    dataB,
                    interestedTags,
                    lessInterestedTopics,
                  );
                  return scoreB.compareTo(scoreA);
                });

                return TabBarView(
                  children: [
                    _buildFeedList(
                      docs: recommendedDocs,
                      isRecommendedTab: true,
                      interestedTags: interestedTags,
                      lessInterestedTopics: lessInterestedTopics,
                      missingAppliances: missingAppliances,
                    ),
                    _buildFeedList(
                      docs: visibleDocs,
                      isRecommendedTab: false,
                      interestedTags: interestedTags,
                      lessInterestedTopics: lessInterestedTopics,
                      missingAppliances: missingAppliances,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedList({
    required List docs,
    required bool isRecommendedTab,
    required List interestedTags,
    required List lessInterestedTopics,
    required List missingAppliances,
  }) {
    if (docs.isEmpty) {
      return const Center(
        child: Text('表示できる投稿がありません', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        if (isRecommendedTab && interestedTags.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.blue.shade50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '優先表示中のタグ: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  ...interestedTags.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          t.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 110),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index] as QueryDocumentSnapshot;
              final post = doc.data() as Map;
              final topicKey = _getTopicKey(post);
              final isTopicDemoted =
                  topicKey.isNotEmpty &&
                  lessInterestedTopics.contains(topicKey);
              final score = _calcRecommendScore(
                post,
                interestedTags,
                lessInterestedTopics,
              );
              final isMatchedInterest = isRecommendedTab && score >= 2;

              return _buildPostCard(
                post: post,
                docId: doc.id,
                context: context,
                topicKey: topicKey,
                isTopicDemoted: isTopicDemoted,
                isMatchedInterest: isMatchedInterest,
                missingAppliances: missingAppliances,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPostCard({
    required dynamic post,
    required String docId,
    required BuildContext context,
    required String topicKey,
    required bool isTopicDemoted,
    required bool isMatchedInterest,
    required List missingAppliances,
  }) {
    final bool isRecipePost = post['isRecipePost'] == true;
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

    final int likesCount = likedUsers.length;
    final int helpfulsCount = helpfulUsers.length;

    final String postUserId = post['userId']?.toString() ?? '';
    final String rawUserName = post['userName']?.toString() ?? '名無し';
    final bool isMyPost =
        (postUserId.isNotEmpty && postUserId == currentUserId) ||
        (currentEmailPrefix.isNotEmpty && rawUserName == currentEmailPrefix);

    final String targetLookupUid = postUserId.isNotEmpty
        ? postUserId
        : (isMyPost ? currentUserId : '');
    final String targetUserKey = postUserId.isNotEmpty
        ? postUserId
        : rawUserName;

    final Uint8List? postImageBytes = _decodeAndCache(
      docId,
      post['imageBase64']?.toString(),
      _postImageCache,
    );

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
          final uDoc = userSnapshot.data as DocumentSnapshot;
          if (uDoc.exists && uDoc.data() != null) {
            final uData = uDoc.data() as Map;
            if (uData['userName'] != null &&
                uData['userName'].toString().trim().isNotEmpty) {
              displayUserName = uData['userName'].toString();
            }
            if (uData['iconBase64'] != null &&
                uData['iconBase64'].toString().isNotEmpty) {
              displayIconBase64 = uData['iconBase64'].toString();
            }
          }
        }

        final Uint8List? userIconBytes = _decodeAndCache(
          targetUserKey,
          displayIconBase64,
          _userIconCache,
        );

        final int baseServings =
            int.tryParse(post['recipeServings']?.toString() ?? '1') ?? 1;
        final int currentServings =
            (_servingsPerPost[docId] as int?) ?? baseServings;
        final String rawRecipeCost = post['recipeCost']?.toString() ?? '';
        final String scaledRecipeCost = _scaleAmountString(
          rawRecipeCost,
          baseServings,
          currentServings,
        );
        final String recipeTime = post['recipeTime']?.toString() ?? '';
        final List recipeIngredients = post['recipeIngredients'] != null
            ? List.from(post['recipeIngredients'])
            : [];
        final String recipeSteps = post['recipeSteps']?.toString() ?? '';

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
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMatchedInterest)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '興味のあるタグに一致',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.blue.shade100,
                      backgroundImage: userIconBytes != null
                          ? MemoryImage(userIconBytes)
                          : null,
                      child: userIconBytes == null
                          ? const Icon(Icons.person, color: Colors.blue)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            displayUserName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (post['mainCategory'] != null &&
                              post['mainCategory'] != '指定なし')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                post['mainCategory'].toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (post['subCategory'] != null &&
                              post['subCategory'] != '指定なし' &&
                              post['subCategory'].toString().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                post['subCategory'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Colors.grey,
                      ),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showPostOptions(
                        docId: docId,
                        isMyPost: isMyPost,
                        topicKey: topicKey,
                        isTopicDemoted: isTopicDemoted,
                        targetUserKey: targetUserKey,
                        displayUserName: displayUserName,
                      ),
                    ),
                  ],
                ),
                if (post['title'] != null &&
                    post['title'].toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
                    child: Text(
                      post['title'].toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                if (post['content'] != null &&
                    post['content'].toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                      post['content'].toString(),
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                if (isRecipePost) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (recipeTime.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 15,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    recipeTime,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            if (scaledRecipeCost.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.payments_outlined,
                                    size: 15,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$scaledRecipeCost（$currentServings人分）',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '材料（$currentServings人分）',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 18,
                                  ),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: currentServings > 1
                                      ? () {
                                          setState(() {
                                            _servingsPerPost[docId] =
                                                currentServings - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text(
                                  '$currentServings人分',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                  ),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: currentServings < 6
                                      ? () {
                                          setState(() {
                                            _servingsPerPost[docId] =
                                                currentServings + 1;
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ...recipeIngredients.map((rawIng) {
                          final ingMap = rawIng as Map;
                          final name = ingMap['name']?.toString() ?? '';
                          final rawAmt = ingMap['amount']?.toString() ?? '';
                          final scaledAmt = _scaleAmountString(
                            rawAmt,
                            baseServings,
                            currentServings,
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '・$name : $scaledAmt',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _askAiIngredientSubstitution(
                                    dishTitle:
                                        post['title']?.toString() ?? 'レシピ',
                                    targetIngredient: name,
                                    allIngredients: recipeIngredients,
                                    missingAppliances: missingAppliances,
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'AI代用案',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (recipeSteps.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '作り方',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            recipeSteps,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (postImageBytes != null)
                  _buildTimelineImage(postImageBytes, docId),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      color: Colors.grey,
                      count: replies,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SnsReplyScreen(
                              postId: docId,
                              originalPost: post,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.pink : Colors.grey,
                      count: likesCount,
                      onTap: () => _toggleReaction(
                        docId,
                        'likedUsers',
                        'likes',
                        likedUsers,
                      ),
                    ),
                    _buildActionButton(
                      icon: isHelpful
                          ? Icons.lightbulb
                          : Icons.lightbulb_outline,
                      color: isHelpful ? Colors.orange : Colors.grey,
                      count: helpfulsCount,
                      onTap: () => _toggleReaction(
                        docId,
                        'helpfulUsers',
                        'helpfuls',
                        helpfulUsers,
                      ),
                    ),
                    _buildActionButton(
                      icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: isSaved ? Colors.blue : Colors.grey,
                      count: 0,
                      onTap: () => _toggleReaction(
                        docId,
                        'savedUsers',
                        'saves',
                        savedUsers,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
