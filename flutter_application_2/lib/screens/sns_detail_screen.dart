import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart';
import 'sns_reply_screen.dart';
import 'sns_screen.dart';

class SnsDetailScreen extends StatefulWidget {
  final String postId;

  const SnsDetailScreen({super.key, required this.postId});

  @override
  State createState() => _SnsDetailScreenState();
}

class _SnsDetailScreenState extends State {
  String get _postId => (widget as SnsDetailScreen).postId;

  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentUserEmail =
      FirebaseAuth.instance.currentUser?.email ?? '';
  final String currentEmailPrefix =
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  static const List _developerEmails = ['meisseikao62@gmail.com'];

  bool _manualDevMode = false;

  bool get _isDeveloper =>
      _manualDevMode || _developerEmails.contains(currentUserEmail);

  int? _customServings;
  final Map _imageCache = {};
  final Map _iconCache = {};

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
    if (rawCount is int) {
      return rawCount < 0 ? 0 : rawCount;
    }
    if (rawCount != null) {
      final parsed = int.tryParse(rawCount.toString());
      if (parsed != null) {
        return parsed < 0 ? 0 : parsed;
      }
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
        .map((e) => '${(e as Map)['name'] ?? ''} ${(e)['amount'] ?? ''}')
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

  Future _toggleReaction(
    String listField,
    String countField,
    List currentUsers,
    int currentDisplayCount,
  ) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('posts').doc(_postId);
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
    } catch (e) {}
  }

  Future _showDeveloperEditCountsDialog({
    required int currentLikes,
    required int currentHelpfuls,
    required int currentReplies,
  }) async {
    final likesCtrl = TextEditingController(text: currentLikes.toString());
    final helpfulsCtrl = TextEditingController(
      text: currentHelpfuls.toString(),
    );
    final repliesCtrl = TextEditingController(text: currentReplies.toString());
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
                  '開発者専用：数値の変更',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: likesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '❤️ いいね数 (likes)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: helpfulsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '💡 役立った・電球数 (helpfuls)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: repliesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '💬 返信数 (replies)',
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
              child: const Text('保存する'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final newLikes = int.tryParse(likesCtrl.text.trim()) ?? currentLikes;
      final newHelpfuls =
          int.tryParse(helpfulsCtrl.text.trim()) ?? currentHelpfuls;
      final newReplies =
          int.tryParse(repliesCtrl.text.trim()) ?? currentReplies;

      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(_postId)
            .update({
              'likes': newLikes < 0 ? 0 : newLikes,
              'helpfuls': newHelpfuls < 0 ? 0 : newHelpfuls,
              'replies': newReplies < 0 ? 0 : newReplies,
            });
        messenger.showSnackBar(const SnackBar(content: Text('🛠️ 数値を更新しました！')));
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
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.shade100,
                backgroundImage: iconBytes != null
                    ? MemoryImage(iconBytes)
                    : null,
                child: iconBytes == null
                    ? const Icon(Icons.person, size: 20, color: Colors.blue)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: GestureDetector(
          onLongPress: () {
            setState(() {
              _manualDevMode = !_manualDevMode;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isDeveloper ? '🛠️ 開発者モードが有効になりました' : '開発者モードを終了しました',
                ),
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
              final int repliesCount =
                  int.tryParse(post['replies']?.toString() ?? '0') ?? 0;

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
                                  CircleAvatar(
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          displayUserName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
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
                                      tooltip: '開発者専用：数値を変更',
                                      icon: const Icon(
                                        Icons.build_circle_outlined,
                                        color: Colors.deepPurple,
                                      ),
                                      onPressed: () =>
                                          _showDeveloperEditCountsDialog(
                                            currentLikes: likesCount,
                                            currentHelpfuls: helpfulsCount,
                                            currentReplies: repliesCount,
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
                                      ...recipeIngredients.map((rawIng) {
                                        final ingMap = rawIng as Map;
                                        final name =
                                            ingMap['name']?.toString() ?? '';
                                        final rawAmt =
                                            ingMap['amount']?.toString() ?? '';
                                        final scaledAmt = _scaleAmountString(
                                          rawAmt,
                                          baseServings,
                                          currentServings,
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
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
                                                      targetIngredient: name,
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
                                      'likedUsers',
                                      'likes',
                                      likedUsers,
                                      likesCount,
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
                                    color: isSaved ? Colors.blue : Colors.grey,
                                    count: 0,
                                    onTap: () => _toggleReaction(
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
