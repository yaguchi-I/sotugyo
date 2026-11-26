import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_reply_screen.dart' show SnsReplyScreen;
import 'sns_screen.dart' show PostImageCarousel;
import 'user_profile_screen.dart' show UserProfileScreen;
import '../widgets/top_toast.dart' show showReactionToast;

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
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  bool _isDeveloper = true;
  bool _hasRecordedImpression = false;

  int? _customServings;
  final Map _imageCache = {};
  final Map _iconCache = {};

  void _openUserProfile(
    BuildContext context, {
    required String userId,
    required String userName,
    required String iconBase64,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          userName: userName,
          initialIconBase64: iconBase64,
        ),
      ),
    );
  }

  void _recordDetailImpressionOnce({
    required int likes,
    required int helpfuls,
    required int saves,
    required int replies,
    required int currentImpressions,
  }) {
    if (_hasRecordedImpression || _postId.isEmpty) return;
    _hasRecordedImpression = true;

    final nextImpressions = currentImpressions + 1;
    final nextScore = AiKnowledgeService.calculateValueScore(
      likes: likes,
      helpfuls: helpfuls,
      saves: saves,
      replies: replies,
      impressions: nextImpressions,
    );

    FirebaseFirestore.instance
        .collection('posts')
        .doc(_postId)
        .update({
          'impressions': FieldValue.increment(1),
          'valueScore': nextScore,
        })
        .catchError((_) {});
  }

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

  List _extractImages(String prefixKey, dynamic data) {
    if (data == null) return [];
    final List result = [];
    if (data['imagesBase64'] != null && data['imagesBase64'] is List) {
      final rawList = List.from(data['imagesBase64']);
      for (int i = 0; i < rawList.length; i++) {
        final bytes = _decodeAndCache(
          '${prefixKey}_$i',
          rawList[i]?.toString(),
          _imageCache,
        );
        if (bytes != null) result.add(bytes);
      }
    }
    if (result.isEmpty && data['imageBase64'] != null) {
      final bytes = _decodeAndCache(
        '${prefixKey}_single',
        data['imageBase64']?.toString(),
        _imageCache,
      );
      if (bytes != null) result.add(bytes);
    }
    return result;
  }

  int _readReactionCount(dynamic rawCount, List fallbackList) {
    final parsed = AiKnowledgeService.readIntField(rawCount, -1);
    if (rawCount != null && parsed >= 0) {
      return max(parsed, fallbackList.length);
    }
    return fallbackList.length;
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
        return _formatScaledNumber((num / den) * ratio);
      });
    }

    final decimalRegex = RegExp(r'(\d+(?:\.\d+)?)');
    if (decimalRegex.hasMatch(rawAmount)) {
      return rawAmount.replaceAllMapped(decimalRegex, (match) {
        final num = double.tryParse(match.group(1) ?? '0') ?? 0;
        return _formatScaledNumber(num * ratio);
      });
    }

    return '$rawAmount（×${_formatScaledNumber(ratio)}）';
  }

  Future _askAiIngredientSubstitution({
    required String dishTitle,
    required String targetIngredient,
    required List allIngredients,
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
        .where((e) => e is Map)
        .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}')
        .join('、');

    final prompt =
        '料理「$dishTitle」（全体の材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
        '一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String replyText = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelName in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelName.toString(),
          apiKey: currentKey,
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          replyText = res.text!
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

  Future _sendReactionNotification({
    required String targetUserId,
    required String postSummary,
    required String type,
  }) async {
    if (currentUserId.isEmpty ||
        targetUserId.isEmpty ||
        targetUserId == currentUserId) {
      return;
    }

    try {
      String fromName = FirebaseAuth.instance.currentUser?.displayName ?? '';
      String fromIcon = '';
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (uDoc.exists && uDoc.data() != null) {
        final uData = uDoc.data()!;
        if (uData['userName'] != null &&
            uData['userName'].toString().trim().isNotEmpty) {
          fromName = uData['userName'].toString().trim();
        }
        if (uData['iconBase64'] != null) {
          fromIcon = uData['iconBase64'].toString();
        }
      }
      if (fromName.isEmpty) {
        fromName = currentEmailPrefix.isNotEmpty ? currentEmailPrefix : 'ユーザー';
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': targetUserId,
        'fromUserId': currentUserId,
        'fromUserName': fromName,
        'fromUserIconBase64': fromIcon,
        'postId': _postId,
        'postSummary': postSummary,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {}
  }

  Future _toggleReaction({
    required String listField,
    required String countField,
    required List currentUsers,
    required int likesCount,
    required int helpfulsCount,
    required int savesCount,
    required int repliesCount,
    required int impressionsCount,
    required String postOwnerUid,
    required String postSummary,
  }) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('posts').doc(_postId);
    final isAdded = currentUsers.contains(currentUserId);

    showReactionToast(context, listField, added: !isAdded);

    int nextLikes = likesCount;
    int nextHelpfuls = helpfulsCount;
    int nextSaves = savesCount;

    if (countField == 'likes') {
      nextLikes = isAdded ? max(0, likesCount - 1) : likesCount + 1;
    } else if (countField == 'helpfuls') {
      nextHelpfuls = isAdded ? max(0, helpfulsCount - 1) : helpfulsCount + 1;
    } else if (countField == 'saves') {
      nextSaves = isAdded ? max(0, savesCount - 1) : savesCount + 1;
    }

    final nextScore = AiKnowledgeService.calculateValueScore(
      likes: nextLikes,
      helpfuls: nextHelpfuls,
      saves: nextSaves,
      replies: repliesCount,
      impressions: impressionsCount,
    );

    final int nextTargetCount = countField == 'likes'
        ? nextLikes
        : (countField == 'helpfuls' ? nextHelpfuls : nextSaves);

    try {
      await docRef.update({
        listField: isAdded
            ? FieldValue.arrayRemove([currentUserId])
            : FieldValue.arrayUnion([currentUserId]),
        countField: nextTargetCount,
        'valueScore': nextScore,
      });

      if (!isAdded && (countField == 'likes' || countField == 'helpfuls')) {
        _sendReactionNotification(
          targetUserId: postOwnerUid,
          postSummary: postSummary,
          type: countField == 'likes' ? 'like' : 'helpful',
        );
      }
    } catch (e) {}
  }

  void _openPostInAiChat(Map post, String displayUserName) {
    final title = (post['title'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final preview = title.isNotEmpty ? title : content;
    final shortPreview = preview.length > 36
        ? '${preview.substring(0, 36)}...'
        : preview;

    final Map lightweightContext = {
      'docId': _postId,
      'userName': displayUserName,
      'mainCategory': (post['mainCategory'] ?? '').toString(),
      'subCategory': (post['subCategory'] ?? '').toString(),
      'title': title,
      'content': content,
      'recipeCost': (post['recipeCost'] ?? '').toString(),
      'recipeIngredients': post['recipeIngredients'] is List
          ? List.from(post['recipeIngredients'])
          : const [],
      'recipeSteps': (post['recipeSteps'] ?? '').toString(),
      'helpfuls': AiKnowledgeService.readIntField(post['helpfuls']),
      'saves': AiKnowledgeService.readIntField(post['saves']),
      'likes': AiKnowledgeService.readIntField(post['likes']),
      'priceTier': (post['priceTier'] ?? 'none').toString(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatScreen(
          initialPrompt:
              'タイムラインの「$shortPreview」という投稿が気になっています。私の家電状況や一人暮らし向けにアレンジ・実践するコツを教えて！',
          referencedPost: lightweightContext,
        ),
      ),
    );
  }

  Future _showDeveloperEditCountsDialog({
    required int currentLikes,
    required int currentHelpfuls,
    required int currentSaves,
    required int currentReplies,
    required int currentImpressions,
  }) async {
    final likesCtrl = TextEditingController(text: currentLikes.toString());
    final helpfulsCtrl = TextEditingController(
      text: currentHelpfuls.toString(),
    );
    final savesCtrl = TextEditingController(text: currentSaves.toString());
    final repliesCtrl = TextEditingController(text: currentReplies.toString());
    final impressionsCtrl = TextEditingController(
      text: currentImpressions.toString(),
    );
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.build_circle, color: Colors.deepPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '開発者専用：数値・スコア変更',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '対象投稿ID: $_postId',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: likesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '❤️ いいね数 (likes)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: helpfulsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '💡 参考になった数 (helpfuls)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: savesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '🔖 保存数 (saves)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: repliesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '💬 返信数 (replies)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: impressionsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '👁️ インプレッション数 (impressions)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('保存してスコア再計算'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final newLikes = max(
        0,
        int.tryParse(likesCtrl.text.trim()) ?? currentLikes,
      );
      final newHelpfuls = max(
        0,
        int.tryParse(helpfulsCtrl.text.trim()) ?? currentHelpfuls,
      );
      final newSaves = max(
        0,
        int.tryParse(savesCtrl.text.trim()) ?? currentSaves,
      );
      final newReplies = max(
        0,
        int.tryParse(repliesCtrl.text.trim()) ?? currentReplies,
      );
      final newImpressions = max(
        0,
        int.tryParse(impressionsCtrl.text.trim()) ?? currentImpressions,
      );

      final newValueScore = AiKnowledgeService.calculateValueScore(
        likes: newLikes,
        helpfuls: newHelpfuls,
        saves: newSaves,
        replies: newReplies,
        impressions: newImpressions,
      );

      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(_postId)
            .update({
              'likes': newLikes,
              'helpfuls': newHelpfuls,
              'saves': newSaves,
              'replies': newReplies,
              'impressions': newImpressions,
              'valueScore': newValueScore,
            });
        messenger.showSnackBar(
          SnackBar(content: Text('🛠️ 更新完了！ valueScore: $newValueScore')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
      }
    }
  }

  Widget _buildReplyItem(String replyDocId, Map reply) {
    final String replyUserId = reply['userId']?.toString() ?? '';
    final String rawReplyName = reply['userName']?.toString() ?? '名無し';
    final String targetLookupUid = replyUserId.isNotEmpty
        ? replyUserId
        : (currentEmailPrefix.isNotEmpty && rawReplyName == currentEmailPrefix
              ? currentUserId
              : '');
    final String cacheUserKey = targetLookupUid.isNotEmpty
        ? targetLookupUid
        : rawReplyName;
    final List replyImages = _extractImages('reply_$replyDocId', reply);

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
            final uData = Map.from(userDoc.data() as Map);
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

        final Uint8List? iconBytes = _decodeAndCache(
          cacheUserKey,
          displayIconBase64,
          _iconCache,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openUserProfile(
                  context,
                  userId: targetLookupUid,
                  userName: displayName,
                  iconBase64: displayIconBase64,
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: iconBytes != null
                      ? MemoryImage(iconBytes)
                      : null,
                  child: iconBytes == null
                      ? const Icon(Icons.person, size: 20, color: Colors.blue)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openUserProfile(
                        context,
                        userId: targetLookupUid,
                        userName: displayName,
                        iconBase64: displayIconBase64,
                      ),
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reply['content']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    if (replyImages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: PostImageCarousel(
                          imagesList: replyImages,
                          keyPrefix: 'reply_img_$replyDocId',
                        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
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
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: GestureDetector(
          onLongPress: () {
            setState(() {
              _isDeveloper = !_isDeveloper;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_isDeveloper ? '🛠️ 開発者モード：ON' : '開発者モード：OFF'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: const Text(
            '投稿の詳細・返信一覧',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: StreamBuilder(
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

              final Map post = Map.from(postDoc.data() as Map);
              final bool isRecipePost = post['isRecipePost'] == true;
              final int repliesCount = _readReactionCount(
                post['replies'],
                const [],
              );

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
              final int impressionsCount = AiKnowledgeService.readIntField(
                post['impressions'],
              );

              _recordDetailImpressionOnce(
                likes: likesCount,
                helpfuls: helpfulsCount,
                saves: savesCount,
                replies: repliesCount,
                currentImpressions: impressionsCount,
              );

              final String postUserId = post['userId']?.toString() ?? '';
              final String rawUserName = post['userName']?.toString() ?? '名無し';
              final String targetLookupUid = postUserId.isNotEmpty
                  ? postUserId
                  : (currentEmailPrefix.isNotEmpty &&
                            rawUserName == currentEmailPrefix
                        ? currentUserId
                        : '');
              final String cacheUserKey = targetLookupUid.isNotEmpty
                  ? targetLookupUid
                  : rawUserName;
              final String postSummary =
                  (post['title']?.toString().isNotEmpty == true)
                  ? post['title'].toString()
                  : (post['content']?.toString() ?? '');

              final List postImages = _extractImages('detail_$_postId', post);

              final int baseServings =
                  int.tryParse(post['recipeServings']?.toString() ?? '1') ?? 1;
              final int currentServings = _customServings ?? baseServings;
              final String rawCost = post['recipeCost']?.toString() ?? '';
              final String scaledCost = _scaleAmountString(
                rawCost,
                baseServings,
                currentServings,
              );
              final String recipeTime = post['recipeTime']?.toString() ?? '';
              final List recipeIngredients = post['recipeIngredients'] != null
                  ? List.from(post['recipeIngredients'])
                  : [];
              final String recipeSteps = post['recipeSteps']?.toString() ?? '';

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: StreamBuilder(
                      stream: targetLookupUid.isNotEmpty
                          ? FirebaseFirestore.instance
                                .collection('users')
                                .doc(targetLookupUid)
                                .snapshots()
                          : null,
                      builder: (context, userSnap) {
                        String displayUserName = rawUserName;
                        String displayIconBase64 =
                            post['userIconBase64']?.toString() ?? '';

                        if (userSnap.hasData && userSnap.data != null) {
                          final uDoc = userSnap.data as DocumentSnapshot;
                          if (uDoc.exists && uDoc.data() != null) {
                            final uData = uDoc.data() as Map;
                            if (uData['userName'] != null &&
                                uData['userName']
                                    .toString()
                                    .trim()
                                    .isNotEmpty) {
                              displayUserName = uData['userName'].toString();
                            }
                            if (uData['iconBase64'] != null &&
                                uData['iconBase64'].toString().isNotEmpty) {
                              displayIconBase64 = uData['iconBase64']
                                  .toString();
                            }
                          }
                        }

                        final Uint8List? userIconBytes = _decodeAndCache(
                          cacheUserKey,
                          displayIconBase64,
                          _iconCache,
                        );

                        return Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _openUserProfile(
                                      context,
                                      userId: targetLookupUid,
                                      userName: displayUserName,
                                      iconBase64: displayIconBase64,
                                    ),
                                    child: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.blue.shade100,
                                      backgroundImage: userIconBytes != null
                                          ? MemoryImage(userIconBytes)
                                          : null,
                                      child: userIconBytes == null
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.blue,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _openUserProfile(
                                            context,
                                            userId: targetLookupUid,
                                            userName: displayUserName,
                                            iconBase64: displayIconBase64,
                                          ),
                                          child: Text(
                                            displayUserName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                            post['subCategory']
                                                .toString()
                                                .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                  if (_isDeveloper)
                                    IconButton(
                                      tooltip: '開発者専用：数値・スコアを変更',
                                      icon: const Icon(
                                        Icons.build_circle_outlined,
                                        color: Colors.deepPurple,
                                      ),
                                      onPressed: () =>
                                          _showDeveloperEditCountsDialog(
                                            currentLikes: likesCount,
                                            currentHelpfuls: helpfulsCount,
                                            currentSaves: savesCount,
                                            currentReplies: repliesCount,
                                            currentImpressions:
                                                impressionsCount,
                                          ),
                                    ),
                                ],
                              ),
                              if (post['title'] != null &&
                                  post['title'].toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12.0,
                                    bottom: 4.0,
                                  ),
                                  child: Text(
                                    post['title'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              if (post['content'] != null &&
                                  post['content'].toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    post['content'].toString(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              if (isRecipePost) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 12,
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
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (scaledCost.isNotEmpty)
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
                                                  '$scaledCost（$currentServings人分）',
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
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
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                onPressed: currentServings > 1
                                                    ? () {
                                                        setState(() {
                                                          _customServings =
                                                              currentServings -
                                                              1;
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
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                onPressed: currentServings < 6
                                                    ? () {
                                                        setState(() {
                                                          _customServings =
                                                              currentServings +
                                                              1;
                                                        });
                                                      }
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      for (final rawIng in recipeIngredients)
                                        Builder(
                                          builder: (_) {
                                            final ingMap = rawIng as Map;
                                            final name =
                                                ingMap['name']?.toString() ??
                                                '';
                                            final rawAmt =
                                                ingMap['amount']?.toString() ??
                                                '';
                                            final scaledAmt =
                                                _scaleAmountString(
                                                  rawAmt,
                                                  baseServings,
                                                  currentServings,
                                                );
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2.0,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '・$name : $scaledAmt',
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        _askAiIngredientSubstitution(
                                                          dishTitle:
                                                              post['title']
                                                                  ?.toString() ??
                                                              'レシピ',
                                                          targetIngredient:
                                                              name,
                                                          allIngredients:
                                                              recipeIngredients,
                                                        ),
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                    child: const Text(
                                                      'AI代用案',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
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
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              if (postImages.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: PostImageCarousel(
                                    imagesList: postImages,
                                    keyPrefix: 'detail_img_$_postId',
                                  ),
                                ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.chat_bubble_outline,
                                    color: Colors.grey,
                                    count: repliesCount,
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
                                    icon: isLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isLiked ? Colors.pink : Colors.grey,
                                    count: likesCount,
                                    onTap: () => _toggleReaction(
                                      listField: 'likedUsers',
                                      countField: 'likes',
                                      currentUsers: likedUsers,
                                      likesCount: likesCount,
                                      helpfulsCount: helpfulsCount,
                                      savesCount: savesCount,
                                      repliesCount: repliesCount,
                                      impressionsCount: impressionsCount,
                                      postOwnerUid: postUserId,
                                      postSummary: postSummary,
                                    ),
                                  ),
                                  _buildActionButton(
                                    icon: isHelpful
                                        ? Icons.lightbulb
                                        : Icons.lightbulb_outline,
                                    color: isHelpful
                                        ? Colors.orange
                                        : Colors.grey,
                                    count: helpfulsCount,
                                    onTap: () => _toggleReaction(
                                      listField: 'helpfulUsers',
                                      countField: 'helpfuls',
                                      currentUsers: helpfulUsers,
                                      likesCount: likesCount,
                                      helpfulsCount: helpfulsCount,
                                      savesCount: savesCount,
                                      repliesCount: repliesCount,
                                      impressionsCount: impressionsCount,
                                      postOwnerUid: postUserId,
                                      postSummary: postSummary,
                                    ),
                                  ),
                                  _buildActionButton(
                                    icon: isSaved
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    color: isSaved ? Colors.blue : Colors.grey,
                                    count: savesCount,
                                    onTap: () => _toggleReaction(
                                      listField: 'savedUsers',
                                      countField: 'saves',
                                      currentUsers: savedUsers,
                                      likesCount: likesCount,
                                      helpfulsCount: helpfulsCount,
                                      savesCount: savesCount,
                                      repliesCount: repliesCount,
                                      impressionsCount: impressionsCount,
                                      postOwnerUid: postUserId,
                                      postSummary: postSummary,
                                    ),
                                  ),
                                  _buildActionButton(
                                    icon: Icons.auto_awesome_outlined,
                                    color: Colors.teal,
                                    count: 0,
                                    onTap: () => _openPostInAiChat(
                                      post,
                                      displayUserName,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: Colors.grey.shade200,
                      child: Text(
                        '返信一覧 ($repliesCount件)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black54,
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
                    builder: (context, replySnap) {
                      if (!replySnap.hasData || replySnap.data == null) {
                        return const SliverToBoxAdapter(
                          child: SizedBox.shrink(),
                        );
                      }
                      final rDocs = (replySnap.data as QuerySnapshot).docs;
                      if (rDocs.isEmpty) {
                        return const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Center(
                              child: Text(
                                'まだ返信はありません',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate((context, idx) {
                          final rDoc = rDocs[idx];
                          final rData = Map.from(rDoc.data() as Map);
                          return _buildReplyItem(rDoc.id, rData);
                        }, childCount: rDocs.length),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SnsReplyScreen(postId: _postId),
            ),
          );
        },
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.reply),
        label: const Text('返信を書く'),
      ),
    );
  }
}