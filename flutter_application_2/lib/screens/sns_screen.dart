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
      FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? '';

  final Map _servingsPerPost = {};

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
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
          final m = e as Map;
          return '${m['name']}: ${m['amount']}';
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
        content: const Text('このユーザーの投稿を今後タイムラインに表示しないようにしますか？'),
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

      messenger.showSnackBar(
        const SnackBar(content: Text('通報を受け付け、タイムラインから非表示にしました')),
      );
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
    dynamic post,
    String docId,
    List missingAppliances,
  ) {
    final String recipeTitle =
        post['recipeTitle']?.toString().isNotEmpty == true
        ? post['recipeTitle'].toString()
        : '手作りレシピ';
    final int baseServings = (post['baseServings'] is int)
        ? (post['baseServings'] as int)
        : (int.tryParse(post['baseServings']?.toString() ?? '1') ?? 1);
    final int currentServings =
        (_servingsPerPost[docId] as int?) ?? baseServings;

    final int baseCost = (post['recipeCost'] is int)
        ? (post['recipeCost'] as int)
        : (int.tryParse(post['recipeCost']?.toString() ?? '0') ?? 0);
    final int scaledCost = baseServings > 0
        ? ((baseCost * currentServings) / baseServings).round()
        : baseCost;

    final String recipeTime = post['recipeTime']?.toString() ?? '';
    final List ingredients = List.from(post['recipeIngredients'] ?? []);
    final String steps = post['recipeSteps']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 10.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withOpacity(0.5),
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
                    '⏱ 調理時間: $recipeTime',
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
                    '💰 目安費用: 約$scaledCost円（$currentServings人分）',
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
              final mapItem = item as Map;
              final iName = mapItem['name']?.toString() ?? '';
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
                        '$iName ： $iScaledAmount',
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
            final dynamic myData = myDoc.data();
            blockedUsers = List.from(myData['blockedUsers'] ?? []);
            lessInterestedTopics = List.from(
              myData['lessInterestedTopics'] ?? [],
            );
            missingAppliances = List.from(myData['missingAppliances'] ?? []);
          }
        }

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text('タイムライン'),
                floating: true,
                snap: true,
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                ),
              ),
              StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SliverFillRemaining(
                      child: Center(child: Text('まだ投稿がありません。最初の投稿をしてみましょう！')),
                    );
                  }

                  final querySnap = snapshot.data as QuerySnapshot;
                  if (querySnap.docs.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(child: Text('まだ投稿がありません。最初の投稿をしてみましょう！')),
                    );
                  }

                  final filteredDocs = querySnap.docs.where((doc) {
                    final data = doc.data() as Map;
                    if (data['mainCategory'] == 'AI') return false;

                    final List hiddenUsers = List.from(
                      data['hiddenUsers'] ?? [],
                    );
                    if (hiddenUsers.contains(currentUserId)) return false;

                    final List reportedUsers = List.from(
                      data['reportedUsers'] ?? [],
                    );
                    if (reportedUsers.length >= 3) return false;

                    final String postUid = data['userId']?.toString() ?? '';
                    final String postName = data['userName']?.toString() ?? '';
                    final String userKey = postUid.isNotEmpty
                        ? postUid
                        : postName;
                    if (userKey.isNotEmpty && blockedUsers.contains(userKey)) {
                      return false;
                    }

                    return true;
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(child: Text('表示できる投稿がありません')),
                    );
                  }

                  final List normalDocs = [];
                  final List demotedDocs = [];

                  for (final doc in filteredDocs) {
                    final dynamic data = doc.data();
                    final String topicKey = _getTopicKey(data);
                    final String mainCat =
                        data['mainCategory']?.toString() ?? '';
                    final bool isDemoted =
                        (topicKey.isNotEmpty &&
                            lessInterestedTopics.contains(topicKey)) ||
                        (mainCat.isNotEmpty &&
                            lessInterestedTopics.contains(mainCat));

                    if (isDemoted) {
                      demotedDocs.add(doc);
                    } else {
                      normalDocs.add(doc);
                    }
                  }

                  final List sortedDocs = [...normalDocs, ...demotedDocs];

                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final dynamic data = sortedDocs[index].data();
                      final String docId = sortedDocs[index].id;
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
                    }, childCount: sortedDocs.length),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostCard(
    dynamic post,
    String docId,
    BuildContext context,
    String topicKey,
    bool isTopicDemoted,
    List missingAppliances,
  ) {
    final bool hasImage = post['hasImage'] ?? false;
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

    final Uint8List? postImageBytes = _decodeBase64(
      post['imageBase64']?.toString(),
    );
    final String heroTag = 'timeline_img_$docId';

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
                                '🍳 レシピ',
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
                      color: isLiked ? Colors.pink : Colors.black54,
                      count: likesCount,
                      onTap: () {
                        if (currentUserId.isEmpty) return;
                        final docRef = FirebaseFirestore.instance
                            .collection('posts')
                            .doc(docId);
                        if (isLiked) {
                          docRef.update({
                            'likedUsers': FieldValue.arrayRemove([
                              currentUserId,
                            ]),
                          });
                        } else {
                          docRef.update({
                            'likedUsers': FieldValue.arrayUnion([
                              currentUserId,
                            ]),
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
                            .doc(docId);
                        if (isSaved) {
                          docRef.update({
                            'savedUsers': FieldValue.arrayRemove([
                              currentUserId,
                            ]),
                          });
                        } else {
                          docRef.update({
                            'savedUsers': FieldValue.arrayUnion([
                              currentUserId,
                            ]),
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
