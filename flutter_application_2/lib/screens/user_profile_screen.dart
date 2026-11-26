import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart' show AiChatScreen;
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
  final String currentEmailPrefix =
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  _ProfilePostSortOrder _sortOrder = _ProfilePostSortOrder.likes;
  _ProfilePostFilter _postFilter = _ProfilePostFilter.all;
  bool _isTogglingFollow = false;

  final Map<String, int> _servingsPerPost = {};
  final Map<String, Map<String, dynamic>> _postImageCache = {};

  bool get _canFollowTarget =>
      currentUserId.isNotEmpty &&
      widget.userId.isNotEmpty &&
      currentUserId != widget.userId;

  String _getTopicKey(Map<String, dynamic> post) {
    final mainCat = post['mainCategory']?.toString() ?? '指定なし';
    final subCat = post['subCategory']?.toString() ?? '指定なし';
    if (mainCat == '指定なし' || mainCat.isEmpty) return '';
    if (subCat != '指定なし' && subCat.isNotEmpty) {
      return '$mainCat:$subCat';
    }
    return mainCat;
  }

  Future<void> _deletePost(String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
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
      messenger.showSnackBar(const SnackBar(content: Text('投稿を削除しました')));
    }
  }

  Future<void> _toggleTopicInterest(
    String topicKey,
    bool isCurrentlyDemoted,
  ) async {
    if (currentUserId.isEmpty || topicKey.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(currentUserId);

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

  Future<void> _hidePost(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('posts').doc(docId).update({
      'hiddenUsers': FieldValue.arrayUnion([currentUserId]),
    });
    messenger.showSnackBar(const SnackBar(content: Text('この投稿を非表示にしました')));
  }

  Future<void> _reportPost(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('posts').doc(docId).update({
      'reportedUsers': FieldValue.arrayUnion([currentUserId]),
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('投稿を通報しました。ご協力ありがとうございます。')),
    );
  }

  Future<void> _blockUser(String targetKey, String displayName) async {
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
                ),
              if (!isMyPost) ...[
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

  bool _isRecipePost(Map<String, dynamic> post) {
    if (post['isRecipePost'] == true) return true;
    final hasIngredients =
        post['recipeIngredients'] is List &&
        (post['recipeIngredients'] as List).isNotEmpty;
    final hasSteps =
        (post['recipeSteps']?.toString().trim().isNotEmpty ?? false);
    final hasTime =
        (post['recipeTime']?.toString().trim().isNotEmpty ?? false);
    final hasCost =
        (post['recipeCost']?.toString().trim().isNotEmpty ?? false);
    return hasIngredients || hasSteps || hasTime || hasCost;
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
    if (baseServings <= 0 || baseServings == targetServings) return rawAmount;
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

  Future<void> _askAiIngredientSubstitution({
    required String dishTitle,
    required String targetIngredient,
    required List allIngredients,
    required List missingAppliances,
    required List allergies,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AIチャット画面でAPIキーを設定してください')),
      );
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
        .map((e) => '${(e as Map)['name'] ?? ''} ${(e)['amount'] ?? ''}')
        .join('、');
    final missingText = missingAppliances.isEmpty
        ? '特になし'
        : missingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(allergies);

    final prompt =
        '料理「$dishTitle」（全体の材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
        '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdownの記号（*や#）は使わないでください。';

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
      } catch (_) {}
    }

    if (allergies.isNotEmpty &&
        AiChatScreen.containsAllergen(replyText, allergies)) {
      replyText =
          'アレルギー対象食材（${allergies.join('・')}）に関連する表現が含まれたため表示を控えました。AI相談画面で使える手持ち食材を指定して聞いてみてください。';
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

  Widget _buildRecipeSection(
    Map<String, dynamic> post,
    String docId, {
    required List missingAppliances,
    required List allergies,
  }) {
    final String titleCandidate =
        (post['title']?.toString().trim().isNotEmpty == true)
            ? post['title'].toString().trim()
            : (post['recipeTitle']?.toString().trim() ?? '');
    final String recipeTitle =
        titleCandidate.isNotEmpty ? titleCandidate : '手作りレシピ';

    final int baseServings = max(
      1,
      int.tryParse(
            (post['recipeServings'] ?? post['baseServings'] ?? '1').toString(),
          ) ??
          1,
    );
    final int currentServings = _servingsPerPost[docId] ?? baseServings;

    final String rawCostText = post['recipeCost'] is int
        ? ((post['recipeCost'] as int) > 0 ? '${post['recipeCost']}' : '')
        : (post['recipeCost']?.toString().trim() ?? '');
    final String scaledCostText = rawCostText.isNotEmpty
        ? _scaleAmountString(rawCostText, baseServings, currentServings)
        : '';

    final String recipeTime = post['recipeTime']?.toString().trim() ?? '';
    final List ingredients = post['recipeIngredients'] is List
        ? List.from(post['recipeIngredients'])
        : const [];
    final String steps = post['recipeSteps']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 10.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: Colors.deepOrange, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  recipeTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (recipeTime.isNotEmpty || scaledCostText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (recipeTime.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          recipeTime,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (scaledCostText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$scaledCostText（$currentServings人分）',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (ingredients.isNotEmpty) ...[
            const Divider(height: 18),
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 15),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(5),
                        onPressed: currentServings > 1
                            ? () {
                                setState(() {
                                  _servingsPerPost[docId] =
                                      currentServings - 1;
                                });
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: Text(
                          '$currentServings人分',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 15),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(5),
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
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in ingredients)
              if (item is Map)
                Builder(
                  builder: (_) {
                    final ingName = item['name']?.toString() ?? '';
                    final ingAmount = _scaleAmountString(
                      item['amount']?.toString() ?? '',
                      baseServings,
                      currentServings,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '・$ingName : $ingAmount',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _askAiIngredientSubstitution(
                              dishTitle: recipeTitle,
                              targetIngredient: ingName,
                              allIngredients: ingredients,
                              missingAppliances: missingAppliances,
                              allergies: allergies,
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'AI代用案',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '作り方',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(steps, style: const TextStyle(fontSize: 13, height: 1.45)),
          ],
        ],
      ),
    );
  }

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
            List lessInterestedTopics = const [];
            List blockedUsers = const [];
            List missingAppliances = const [];
            List allergies = const [];

            if (meSnap.hasData &&
                meSnap.data != null &&
                meSnap.data!.exists &&
                meSnap.data!.data() != null) {
              final meData = meSnap.data!.data() as Map<String, dynamic>;
              myFollowingSet.addAll(_readStringList(meData, 'followingUsers'));
              myFollowingSet.addAll(_readStringList(meData, 'following'));
              if (meData['lessInterestedTopics'] is List) {
                lessInterestedTopics = List.from(meData['lessInterestedTopics']);
              }
              if (meData['blockedUsers'] is List) {
                blockedUsers = List.from(meData['blockedUsers']);
              }
              if (meData['missingAppliances'] is List) {
                missingAppliances = List.from(meData['missingAppliances']);
              }
              if (meData['allergies'] is List) {
                allergies = List.from(meData['allergies'])
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
              }
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

                    final List hiddenUsers = data['hiddenUsers'] is List
                        ? List.from(data['hiddenUsers'])
                        : const [];
                    if (currentUserId.isNotEmpty &&
                        hiddenUsers.contains(currentUserId)) {
                      return false;
                    }

                    final List reportedUsers = data['reportedUsers'] is List
                        ? List.from(data['reportedUsers'])
                        : const [];
                    if (reportedUsers.length >= 3 ||
                        (currentUserId.isNotEmpty &&
                            reportedUsers.contains(currentUserId))) {
                      return false;
                    }

                    final postUid = data['userId']?.toString() ?? '';
                    final postUName = data['userName']?.toString() ?? '';
                    if ((postUid.isNotEmpty &&
                            blockedUsers.contains(postUid)) ||
                        (postUName.isNotEmpty &&
                            blockedUsers.contains(postUName))) {
                      return false;
                    }

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
                                  final bool isRecipe = _isRecipePost(post);
                                  final topicKey = _getTopicKey(post);
                                  final bool isTopicDemoted =
                                      topicKey.isNotEmpty &&
                                      lessInterestedTopics.contains(topicKey);
                                  final postUserId =
                                      post['userId']?.toString() ?? '';
                                  final rawPostUserName =
                                      post['userName']?.toString() ?? '名無し';
                                  final bool isMyPost =
                                      (postUserId.isNotEmpty &&
                                          postUserId == currentUserId) ||
                                      (currentEmailPrefix.isNotEmpty &&
                                          rawPostUserName == currentEmailPrefix);
                                  final String targetUserKey =
                                      postUserId.isNotEmpty
                                          ? postUserId
                                          : rawPostUserName;

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
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.more_vert,
                                                            size: 18,
                                                            color: Colors.grey,
                                                          ),
                                                          constraints:
                                                              const BoxConstraints(),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          onPressed: () =>
                                                              _showPostOptions(
                                                            docId: doc.id,
                                                            isMyPost: isMyPost,
                                                            topicKey: topicKey,
                                                            isTopicDemoted:
                                                                isTopicDemoted,
                                                            targetUserKey:
                                                                targetUserKey,
                                                            displayUserName:
                                                                displayName,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (!isRecipe &&
                                                        title.isNotEmpty)
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
                                                    if (isRecipe)
                                                      _buildRecipeSection(
                                                        post,
                                                        doc.id,
                                                        missingAppliances:
                                                            missingAppliances,
                                                        allergies: allergies,
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
