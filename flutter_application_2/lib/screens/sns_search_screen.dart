import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart';
import 'ai_chat_screen.dart';
import 'sns_detail_screen.dart';
import 'sns_reply_screen.dart';
import '../widgets/top_toast.dart';

class SnsSearchScreen extends StatefulWidget {
  const SnsSearchScreen({super.key});

  @override
  State<SnsSearchScreen> createState() => _SnsSearchScreenState();
}

class _SnsSearchScreenState extends State<SnsSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentEmailPrefix =
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  String _searchQuery = '';
  String _selectedTag = 'すべて';

  final List<String> _tags = ['すべて', 'トレンド', '料理', '掃除', '収納', 'その他'];
  final Map<String, int> _servingsPerPost = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.trim().isEmpty) return null;
    final cleaned = base64String.contains(',')
        ? base64String.split(',').last.replaceAll(RegExp(r'\s+'), '')
        : base64String.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    try {
      final decoded = base64Decode(cleaned);
      return decoded.isEmpty ? null : decoded;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  List _readUserList(Map<String, dynamic> data, String key) {
    final reactions = _asMap(data['reactions']);
    if (reactions[key] is List) {
      return List.from(reactions[key] as List);
    }
    final moderation = _asMap(data['moderation']);
    if (moderation[key] is List) {
      return List.from(moderation[key] as List);
    }
    if (data[key] is List) {
      return List.from(data[key] as List);
    }
    return const [];
  }

  int _readReactionCount(
    Map<String, dynamic> data,
    String countKey,
    List fallbackList,
  ) {
    final counts = _asMap(data['counts']);
    final dynamic rawCount = counts[countKey] ?? data[countKey];
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

  String _readMainCategory(Map<String, dynamic> data) {
    final category = _asMap(data['category']);
    if (category['main'] != null) {
      return category['main'].toString();
    }
    return data['mainCategory']?.toString() ?? '指定なし';
  }

  String _readSubCategory(Map<String, dynamic> data) {
    final category = _asMap(data['category']);
    if (category['sub'] != null) {
      return category['sub'].toString();
    }
    return data['subCategory']?.toString() ?? '指定なし';
  }

  int _getLikesCount(Map<String, dynamic> data) {
    final likedUsers = _readUserList(data, 'likedUsers');
    return _readReactionCount(data, 'likes', likedUsers);
  }

  int _compareTimestampsDesc(Timestamp? aTime, Timestamp? bTime) {
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }

  String _getTopicKey(Map<String, dynamic> post) {
    final mainCat = _readMainCategory(post);
    final subCat = _readSubCategory(post);
    if (mainCat == '指定なし') return '';
    if (subCat != '指定なし' && subCat.isNotEmpty) {
      return '$mainCat:$subCat';
    }
    return mainCat;
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

  Future<void> _toggleReaction({
    required String docId,
    required String listField,
    required String countField,
    required List currentUsers,
    required int likesCount,
    required int helpfulsCount,
    required int savesCount,
    required int repliesCount,
    required int impressionsCount,
  }) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('posts').doc(docId);
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
    } catch (_) {}
  }

  Future _askAiSubstitution({
    required String recipeTitle,
    required List ingredients,
    required String steps,
    required List missingAppliances,
    String? targetIngredient,
  }) async {
    final key = AiChatScreen.apiKey.trim();
    if (key.isEmpty || key.contains('ここに')) {
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

    final ingSummary = ingredients
        .map((e) {
          if (e is Map) {
            return '${e['name'] ?? ''}: ${e['amount'] ?? ''}';
          }
          return e.toString();
        })
        .join('、');
    final missingText = missingAppliances.isEmpty
        ? 'なし'
        : missingAppliances.join('、');

    final String prompt = targetIngredient != null
        ? '料理「$recipeTitle」（材料: $ingSummary）を作る際、「$targetIngredient」が家にありません。\n'
              '一人暮らしの家によくある身近な食材や調味料を使った「$targetIngredient」の代用案と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$recipeTitle」（材料: $ingSummary / 手順: $steps）について、\n'
              '持っていない調理家電【$missingText】を一切使わずに作る方法、およびさらに安く簡単に作れる代替アレンジ案を200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String aiReply = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(model: modelItem.toString(), apiKey: key);
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          aiReply = res.text!.trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetIngredient != null
                    ? '「$targetIngredient」のAI代用案'
                    : '「$recipeTitle」のAI代替提案',
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
            aiReply,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
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

  Future _deletePost(String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投稿の削除'),
        content: const Text('この投稿を完全に削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('posts').doc(docId).delete();
      messenger.showSnackBar(const SnackBar(content: Text('投稿を削除しました')));
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

  Future _toggleTopicDemotion(String topicKey, bool isCurrentlyDemoted) async {
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
        SnackBar(content: Text('「$topicKey」の表示頻度を元に戻しました')),
      );
    } else {
      await userRef.set({
        'lessInterestedTopics': FieldValue.arrayUnion([topicKey]),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(content: Text('「$topicKey」の話題をタイムラインに出にくくしました')),
      );
    }
  }

  Future _blockUser(String targetUserKey, String displayUserName) async {
    if (currentUserId.isEmpty || targetUserKey.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$displayUserName さんをブロック'),
        content: const Text('このユーザーの投稿を今後表示しないようにしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ブロックする'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .set({
            'blockedUsers': FieldValue.arrayUnion([targetUserKey]),
          }, SetOptions(merge: true));

      messenger.showSnackBar(
        SnackBar(content: Text('$displayUserName さんをブロックしました')),
      );
    }
  }

  Future _reportPost(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final List reasons = [
      '誹謗中傷・暴言・嫌がらせ',
      'スパム・荒らし行為',
      '不適切な写真・コンテンツ',
      'その他ガイドライン違反',
    ];

    final selectedReason = await showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('通報する理由を選択'),
        children: reasons.map((r) {
          final reasonText = r.toString();
          return SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.pop(dialogContext, reasonText),
            child: Text(reasonText, style: const TextStyle(fontSize: 15)),
          );
        }).toList(),
      ),
    );

    if (selectedReason != null) {
      await FirebaseFirestore.instance.collection('reports').add({
        'postId': docId,
        'reportedBy': currentUserId,
        'reason': selectedReason.toString(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('posts').doc(docId).update({
        'reportedUsers': FieldValue.arrayUnion([currentUserId]),
        'hiddenUsers': FieldValue.arrayUnion([currentUserId]),
      });

      messenger.showSnackBar(const SnackBar(content: Text('通報を受け付け、非表示にしました')));
    }
  }

  void _showPostOptionsSheet({
    required String docId,
    required bool isMyPost,
    required String targetUserKey,
    required String displayUserName,
    required String topicKey,
    required bool isTopicDemoted,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMyPost)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'この投稿を削除する',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deletePost(docId);
                  },
                ),
              if (topicKey.isNotEmpty)
                ListTile(
                  leading: Icon(
                    isTopicDemoted ? Icons.trending_up : Icons.trending_down,
                    color: Colors.blueGrey,
                  ),
                  title: Text(
                    isTopicDemoted
                        ? '「$topicKey」の話題を通常通り表示する'
                        : '「$topicKey」の話題を表示しにくくする',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _toggleTopicDemotion(topicKey, isTopicDemoted);
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
              if (!isMyPost) ...[
                ListTile(
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text('誹謗中傷・不適切な投稿として通報する'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _reportPost(docId);
                  },
                ),
                if (targetUserKey.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text('$displayUserName さんをブロックする'),
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

  Widget _buildRecipeSection(
    Map<String, dynamic> post,
    String docId,
    List missingAppliances,
  ) {
    final recipeBox = _asMap(post['recipe']);

    final rawTitle =
        (post['recipeTitle'] ?? post['title'] ?? recipeBox['title'] ?? '')
            .toString()
            .trim();
    final String recipeTitle = rawTitle.isNotEmpty ? rawTitle : '手作りレシピ';

    final rawServings =
        recipeBox['baseServings'] ??
        post['baseServings'] ??
        post['recipeServings'] ??
        1;
    final int baseServings = (rawServings is int)
        ? rawServings
        : (int.tryParse(rawServings.toString()) ?? 1);
    final int currentServings =
        (_servingsPerPost[docId] as int?) ??
        (baseServings > 0 ? baseServings : 1);

    final rawCost = recipeBox['cost'] ?? post['recipeCost'] ?? '';
    final int baseCost = (rawCost is int)
        ? rawCost
        : (int.tryParse(rawCost.toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
              0);
    final int scaledCost = baseServings > 0
        ? ((baseCost * currentServings) / baseServings).round()
        : baseCost;

    final String recipeTime = (recipeBox['time'] ?? post['recipeTime'] ?? '')
        .toString();
    final rawIngredients =
        recipeBox['ingredients'] ?? post['recipeIngredients'] ?? const [];
    final List ingredients = rawIngredients is List
        ? List.from(rawIngredients)
        : const [];
    final String steps = (recipeBox['steps'] ?? post['recipeSteps'] ?? '')
        .toString();

    return Container(
      margin: const EdgeInsets.only(top: 10.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withValues(alpha: 0.5),
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
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _askAiSubstitution(
                  recipeTitle: recipeTitle,
                  ingredients: ingredients,
                  steps: steps,
                  missingAppliances: missingAppliances,
                ),
                icon: const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: Colors.deepOrange,
                ),
                label: const Text(
                  'AI代替案',
                  style: TextStyle(fontSize: 11, color: Colors.deepOrange),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.deepOrange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
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
                  child: Text(
                    '調理時間: $recipeTime',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (baseCost > 0)
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
                    '目安費用: 約$scaledCost円（$currentServings人分）',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
          if (ingredients.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '【材料】（$currentServings人分）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
                                  _servingsPerPost[docId] = currentServings - 1;
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
                                  _servingsPerPost[docId] = currentServings + 1;
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
            ...ingredients.map((item) {
              final mapItem = item is Map ? item : const {};
              final iName = mapItem['name']?.toString() ?? item.toString();
              final iRawAmount = mapItem['amount']?.toString() ?? '';
              final iScaledAmount = _scaleAmountString(
                iRawAmount,
                baseServings,
                currentServings,
              );

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        iRawAmount.isNotEmpty
                            ? '$iName ： $iScaledAmount'
                            : iName,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _askAiSubstitution(
                        recipeTitle: recipeTitle,
                        ingredients: ingredients,
                        steps: steps,
                        missingAppliances: missingAppliances,
                        targetIngredient: iName,
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 14),
                      label: const Text('代用案', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (steps.isNotEmpty) ...[
            const Divider(height: 20),
            const Text(
              '【作り方】',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(steps, style: const TextStyle(fontSize: 13, height: 1.5)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: currentUserId.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .snapshots()
          : null,
      builder: (context, myUserSnapshot) {
        List blockedUsers = [];
        List lessInterestedTopics = [];
        List missingAppliances = [];

        if (myUserSnapshot.hasData && myUserSnapshot.data != null) {
          final myDoc = myUserSnapshot.data as DocumentSnapshot;
          if (myDoc.exists && myDoc.data() != null) {
            final myData = _asMap(myDoc.data());
            blockedUsers = List.from(myData['blockedUsers'] ?? const []);
            lessInterestedTopics = List.from(
              myData['lessInterestedTopics'] ?? const [],
            );
            missingAppliances = List.from(
              myData['missingAppliances'] ?? const [],
            );
          }
        }

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
                    hintText: '料理名・材料・本文・ユーザー名で検索...',
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
                      final data = _asMap(doc.data());
                      final mainCategory = _readMainCategory(data);
                      final subCategory = _readSubCategory(data);
                      if (mainCategory == 'AI') return false;

                      final hiddenUsers = _readUserList(data, 'hiddenUsers');
                      if (currentUserId.isNotEmpty &&
                          hiddenUsers.contains(currentUserId)) {
                        return false;
                      }

                      final reportedUsers = _readUserList(
                        data,
                        'reportedUsers',
                      );
                      if (reportedUsers.length >= 3 ||
                          (currentUserId.isNotEmpty &&
                              reportedUsers.contains(currentUserId))) {
                        return false;
                      }

                      final authorBox = _asMap(data['author']);
                      final String postUid =
                          (authorBox['userId'] ?? data['userId'] ?? '')
                              .toString();
                      final String postName =
                          (authorBox['userName'] ?? data['userName'] ?? '')
                              .toString();
                      final String userKey = postUid.isNotEmpty
                          ? postUid
                          : postName;
                      if (userKey.isNotEmpty &&
                          blockedUsers.contains(userKey)) {
                        return false;
                      }

                      final recipeBox = _asMap(data['recipe']);
                      final titleText =
                          (data['title'] ??
                                  data['recipeTitle'] ??
                                  recipeBox['title'] ??
                                  '')
                              .toString()
                              .toLowerCase();
                      final contentText = (data['content'] ?? '')
                          .toString()
                          .toLowerCase();
                      final userNameText = postName.toLowerCase();

                      final rawIngredients =
                          recipeBox['ingredients'] ?? data['recipeIngredients'];
                      final ingredientsText = rawIngredients is List
                          ? rawIngredients
                                .map(
                                  (e) => e is Map
                                      ? (e['name']?.toString() ?? '')
                                      : e.toString(),
                                )
                                .join(' ')
                                .toLowerCase()
                          : '';

                      final matchesQuery =
                          _searchQuery.isEmpty ||
                          titleText.contains(_searchQuery) ||
                          contentText.contains(_searchQuery) ||
                          userNameText.contains(_searchQuery) ||
                          ingredientsText.contains(_searchQuery);

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
                      final aData = _asMap(a.data());
                      final bData = _asMap(b.data());

                      if (_selectedTag == 'トレンド') {
                        final aLikes = _getLikesCount(aData);
                        final bLikes = _getLikesCount(bData);
                        if (aLikes != bLikes) {
                          return bLikes.compareTo(aLikes);
                        }
                      }

                      final aTime = aData['createdAt'] as Timestamp?;
                      final bTime = bData['createdAt'] as Timestamp?;
                      return _compareTimestampsDesc(aTime, bTime);
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
                        final data = _asMap(filteredDocs[index].data());
                        final docId = filteredDocs[index].id;
                        final String topicKey = _getTopicKey(data);
                        final bool isTopicDemoted =
                            topicKey.isNotEmpty &&
                            lessInterestedTopics.contains(topicKey);

                        return _buildPostCard(
                          data,
                          docId,
                          context,
                          topicKey,
                          isTopicDemoted,
                          missingAppliances,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostCard(
    Map<String, dynamic> post,
    String docId,
    BuildContext context,
    String topicKey,
    bool isTopicDemoted,
    List missingAppliances,
  ) {
    final mediaBox = _asMap(post['media']);
    final recipeBox = _asMap(post['recipe']);
    final authorBox = _asMap(post['author']);

    final mainCategory = _readMainCategory(post);
    final subCategory = _readSubCategory(post);

    final bool isRecipePost =
        recipeBox['isRecipePost'] == true || post['isRecipePost'] == true;

    final List likedUsers = _readUserList(post, 'likedUsers');
    final List helpfulUsers = _readUserList(post, 'helpfulUsers');
    final List savedUsers = _readUserList(post, 'savedUsers');

    final bool isLiked =
        currentUserId.isNotEmpty && likedUsers.contains(currentUserId);
    final bool isHelpful =
        currentUserId.isNotEmpty && helpfulUsers.contains(currentUserId);
    final bool isSaved =
        currentUserId.isNotEmpty && savedUsers.contains(currentUserId);

    final int repliesCount = _readReactionCount(post, 'replies', const []);
    final int likesCount = _readReactionCount(post, 'likes', likedUsers);
    final int helpfulsCount = _readReactionCount(
      post,
      'helpfuls',
      helpfulUsers,
    );
    final int savesCount = _readReactionCount(post, 'saves', savedUsers);
    final int impressionsCount = AiKnowledgeService.readIntField(
      post['impressions'],
    );

    final String postUserId = (authorBox['userId'] ?? post['userId'] ?? '')
        .toString();
    final String rawUserName =
        (authorBox['userName'] ?? post['userName'] ?? '名無し').toString();
    final bool isMyPost =
        (postUserId.isNotEmpty && postUserId == currentUserId) ||
        (currentEmailPrefix.isNotEmpty && rawUserName == currentEmailPrefix);

    final String targetLookupUid = postUserId.isNotEmpty
        ? postUserId
        : (isMyPost ? currentUserId : '');
    final String targetUserKey = postUserId.isNotEmpty
        ? postUserId
        : rawUserName;

    final String rawImageBase64 =
        (mediaBox['imageBase64'] ?? post['imageBase64'] ?? '').toString();
    final Uint8List? postImageBytes = _decodeBase64(rawImageBase64);
    final bool hasImage =
        (mediaBox['hasImage'] == true || post['hasImage'] == true) ||
        postImageBytes != null;
    final String heroTag = 'search_img_$docId';

    return StreamBuilder(
      stream: targetLookupUid.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(targetLookupUid)
                .snapshots()
          : null,
      builder: (context, userSnapshot) {
        String displayUserName = rawUserName;
        String displayIconBase64 =
            (authorBox['userIconBase64'] ?? post['userIconBase64'] ?? '')
                .toString();

        if (userSnapshot.hasData && userSnapshot.data != null) {
          final userDoc = userSnapshot.data as DocumentSnapshot;
          if (userDoc.exists && userDoc.data() != null) {
            final uData = _asMap(userDoc.data());
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
              border: Border(
                bottom: BorderSide(color: Colors.grey, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
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
                              fontSize: 16,
                            ),
                          ),
                          if (mainCategory.isNotEmpty && mainCategory != '指定なし')
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
                                mainCategory,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          if (subCategory.isNotEmpty && subCategory != '指定なし')
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
                                subCategory,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                          if (isRecipePost)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'レシピ',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          if (isTopicDemoted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '表示頻度低',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.grey,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showPostOptionsSheet(
                        docId: docId,
                        isMyPost: isMyPost,
                        targetUserKey: targetUserKey,
                        displayUserName: displayUserName,
                        topicKey: topicKey,
                        isTopicDemoted: isTopicDemoted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((post['content']?.toString() ?? '').isNotEmpty)
                  Text(
                    post['content'].toString(),
                    style: const TextStyle(fontSize: 15),
                  ),
                if (isRecipePost)
                  _buildRecipeSection(post, docId, missingAppliances),
                if (hasImage && postImageBytes != null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () =>
                        _openFullScreenImage(context, postImageBytes, heroTag),
                    child: Hero(
                      tag: heroTag,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
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
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      color: Colors.black54,
                      count: repliesCount,
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
                      color: isLiked ? Colors.pink : Colors.black54,
                      count: likesCount,
                      onTap: () => _toggleReaction(
                        docId: docId,
                        listField: 'likedUsers',
                        countField: 'likes',
                        currentUsers: likedUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: repliesCount,
                        impressionsCount: impressionsCount,
                      ),
                    ),
                    _buildActionButton(
                      icon: isHelpful ? Icons.thumb_up : Icons.thumb_up_off_alt,
                      color: isHelpful ? Colors.blue : Colors.black54,
                      count: helpfulsCount,
                      onTap: () => _toggleReaction(
                        docId: docId,
                        listField: 'helpfulUsers',
                        countField: 'helpfuls',
                        currentUsers: helpfulUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: repliesCount,
                        impressionsCount: impressionsCount,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? Colors.blue : Colors.black54,
                      ),
                      onPressed: () => _toggleReaction(
                        docId: docId,
                        listField: 'savedUsers',
                        countField: 'saves',
                        currentUsers: savedUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: repliesCount,
                        impressionsCount: impressionsCount,
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
