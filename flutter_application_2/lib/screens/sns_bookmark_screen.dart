import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart';
import 'sns_detail_screen.dart';

class SnsBookmarkScreen extends StatefulWidget {
  const SnsBookmarkScreen({super.key});

  @override
  State createState() => _SnsBookmarkScreenState();
}

class _SnsBookmarkScreenState extends State
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  final List _mainTabs = ['すべて', '料理', '掃除', '収納', 'AI'];

  final Map _subTags = {
    'すべて': [],
    '料理': ['すべて', '野菜', '肉類', '麺類', '作り置き', 'その他'],
    '掃除': ['すべて', 'キッチン', 'お風呂', 'トイレ', 'リビング', 'その他'],
    '収納': ['すべて', 'クローゼット', 'デスク周り', '小物', 'その他'],
    'AI': ['すべて', 'レシピ', '節約術', 'その他'],
  };

  String _selectedSubTag = 'すべて';
  final Map _servingsPerPost = {};

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

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
  }

  void _showFullScreenImage(Uint8List imageBytes, String tag) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (BuildContext pageContext, _, __) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: Hero(
                tag: tag,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(imageBytes, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      ),
    );
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

  Future _toggleSave(String docId) async {
    if (currentUserId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('posts').doc(docId).update({
        'savedUsers': FieldValue.arrayRemove([currentUserId]),
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('保存フォルダから解除しました'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {}
  }

  Future _askAiSubstitution({
    required String dishTitle,
    required List allIngredients,
    required List missingAppliances,
    String? targetIngredient,
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
        .map((e) {
          if (e is Map) {
            return '${e['name'] ?? ''} ${e['amount'] ?? ''}'.trim();
          }
          return e.toString();
        })
        .join('、');

    final missingText = missingAppliances.isEmpty
        ? '特になし'
        : missingAppliances.join('、');

    final prompt = targetIngredient != null
        ? '料理「$dishTitle」（材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
              '持っていない調理家電【$missingText】を使わず、一人暮らしの家によくある身近な食材や調味料で「$targetIngredient」を代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$dishTitle」（材料：$ingNames）について、\n'
              '持っていない調理家電【$missingText】を使わず、さらに安く手軽に作れる代替食材やアレンジのコツを200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

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
                targetIngredient != null
                    ? '「$targetIngredient」の代用案'
                    : '「$dishTitle」のAI代替提案',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text(
          '保存フォルダ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          tabs: _mainTabs.map((t) => Tab(text: t.toString())).toList(),
        ),
      ),
      body: currentUserId.isEmpty
          ? const Center(child: Text('ログインが必要です'))
          : StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUserId)
                  .snapshots(),
              builder: (context, userPrefSnap) {
                List missingAppliances = [];
                if (userPrefSnap.hasData && userPrefSnap.data != null) {
                  final uDoc = userPrefSnap.data as DocumentSnapshot;
                  if (uDoc.exists && uDoc.data() != null) {
                    final uData = uDoc.data() as Map;
                    if (uData['missingAppliances'] != null) {
                      missingAppliances = List.from(uData['missingAppliances']);
                    }
                  }
                }

                return StreamBuilder(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .where('savedUsers', arrayContains: currentUserId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const Center(child: Text('保存した投稿はまだありません'));
                    }

                    final querySnap = snapshot.data as QuerySnapshot;
                    final List docs = List.from(querySnap.docs);

                    docs.sort((a, b) {
                      final dataA = (a as QueryDocumentSnapshot).data() as Map;
                      final dataB = (b as QueryDocumentSnapshot).data() as Map;
                      final tsA = dataA['createdAt'] as Timestamp?;
                      final tsB = dataB['createdAt'] as Timestamp?;
                      if (tsA == null && tsB == null) return 0;
                      if (tsA == null) return 1;
                      if (tsB == null) return -1;
                      return tsB.compareTo(tsA);
                    });

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          '保存した投稿・レシピはまだありません。\nタイムラインやAI相談でブックマークを押して保存しよう！',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return TabBarView(
                      controller: _tabController,
                      children: _mainTabs.map((rawMainTab) {
                        final mainTab = rawMainTab.toString();
                        if (mainTab == 'すべて') {
                          return _buildPostList(docs, missingAppliances, 'all');
                        } else {
                          return _buildCategoryTab(
                            docs,
                            mainTab,
                            missingAppliances,
                          );
                        }
                      }).toList(),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildCategoryTab(
    List allDocs,
    String mainCategory,
    List missingAppliances,
  ) {
    final List subTagList = List.from(_subTags[mainCategory] ?? []);

    final List filteredDocs = allDocs.where((rawDoc) {
      final doc = rawDoc as QueryDocumentSnapshot;
      final data = doc.data() as Map;
      if (data['mainCategory'] != mainCategory) return false;
      if (_selectedSubTag != 'すべて' && data['subCategory'] != _selectedSubTag) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subTagList.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: subTagList.map((rawTag) {
                final tag = rawTag.toString();
                final isSelected = _selectedSubTag == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: Colors.blue.shade100,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedSubTag = tag;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: filteredDocs.isEmpty
              ? const Center(
                  child: Text(
                    'このカテゴリに保存された項目はありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildPostList(filteredDocs, missingAppliances, mainCategory),
        ),
      ],
    );
  }

  Widget _buildPostList(List docs, List missingAppliances, String tabKey) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: docs.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: Colors.grey.shade300),
      itemBuilder: (context, index) {
        final doc = docs[index] as QueryDocumentSnapshot;
        final data = doc.data() as Map;
        final docId = doc.id;
        return _buildSavedCard(data, docId, missingAppliances, tabKey);
      },
    );
  }

  Widget _buildSavedCard(
    Map data,
    String docId,
    List missingAppliances,
    String tabKey,
  ) {
    final bool isAi = data['mainCategory'] == 'AI';
    final bool isRecipePost =
        data['isRecipePost'] == true || data['subCategory'] == 'レシピ';
    final String postUserId = data['userId']?.toString() ?? '';
    final String rawUserName = data['userName']?.toString() ?? '名無し';
    final String title = data['title']?.toString() ?? '';
    final String content = data['content']?.toString() ?? '';

    final int baseServings =
        int.tryParse(data['recipeServings']?.toString() ?? '1') ?? 1;
    final int currentServings =
        (_servingsPerPost[docId] as int?) ?? baseServings;
    final String rawCost = data['recipeCost']?.toString() ?? '';
    final String scaledCost = _scaleAmountString(
      rawCost,
      baseServings,
      currentServings,
    );
    final String recipeTime = data['recipeTime']?.toString() ?? '';
    final List recipeIngredients = data['recipeIngredients'] != null
        ? List.from(data['recipeIngredients'])
        : [];
    final String recipeSteps = data['recipeSteps']?.toString() ?? '';
    final Uint8List? postImageBytes = _decodeBase64(
      data['imageBase64']?.toString(),
    );
    final String heroTag = 'bookmark_img_${tabKey}_$docId';

    return StreamBuilder(
      stream: (!isAi && postUserId.isNotEmpty)
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(postUserId)
                .snapshots()
          : null,
      builder: (context, userSnap) {
        String displayUserName = rawUserName;
        String displayIconBase64 = data['userIconBase64']?.toString() ?? '';

        if (userSnap.hasData && userSnap.data != null) {
          final uDoc = userSnap.data as DocumentSnapshot;
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

        final Uint8List? userIconBytes = _decodeBase64(displayIconBase64);

        return InkWell(
          onTap: () {
            if (isAi) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiRecipeDetailScreen(
                    postId: docId,
                    missingAppliances: missingAppliances,
                  ),
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
                  radius: 20,
                  backgroundColor: isAi
                      ? Colors.purple.shade100
                      : Colors.blue.shade100,
                  backgroundImage: (!isAi && userIconBytes != null)
                      ? MemoryImage(userIconBytes)
                      : null,
                  child: isAi
                      ? const Icon(Icons.auto_awesome, color: Colors.purple)
                      : (userIconBytes == null
                            ? const Icon(Icons.person, color: Colors.blue)
                            : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              displayUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '保存を解除',
                            icon: const Icon(
                              Icons.bookmark,
                              color: Colors.blue,
                            ),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () => _toggleSave(docId),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (data['mainCategory'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isAi
                                    ? Colors.purple.shade50
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                data['mainCategory'].toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isAi
                                      ? Colors.purple.shade800
                                      : Colors.blue.shade800,
                                ),
                              ),
                            ),
                          if (data['subCategory'] != null &&
                              data['subCategory'].toString().isNotEmpty)
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
                                data['subCategory'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      if (!isRecipePost || recipeIngredients.isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ],
                      if (isRecipePost && recipeIngredients.isNotEmpty) ...[
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                  OutlinedButton.icon(
                                    onPressed: () => _askAiSubstitution(
                                      dishTitle: title.isNotEmpty
                                          ? title
                                          : 'レシピ',
                                      allIngredients: recipeIngredients,
                                      missingAppliances: missingAppliances,
                                    ),
                                    icon: const Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: Colors.orange,
                                    ),
                                    label: const Text(
                                      'AI代替提案',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.orange,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
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
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _askAiSubstitution(
                                          dishTitle: title.isNotEmpty
                                              ? title
                                              : 'レシピ',
                                          allIngredients: recipeIngredients,
                                          missingAppliances: missingAppliances,
                                          targetIngredient: name,
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
                      if (postImageBytes != null) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () =>
                              _showFullScreenImage(postImageBytes, heroTag),
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
}

class AiRecipeDetailScreen extends StatefulWidget {
  final String postId;
  final List missingAppliances;

  const AiRecipeDetailScreen({
    super.key,
    required this.postId,
    this.missingAppliances = const [],
  });

  @override
  State createState() => _AiRecipeDetailScreenState();
}

class _AiRecipeDetailScreenState extends State<AiRecipeDetailScreen> {
  int _currentServings = 1;
  bool _initializedServings = false;

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

  Future _askDetailAiSubstitution({
    required String dishTitle,
    required List allIngredients,
    String? targetIngredient,
  }) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) return;

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
        .map((e) {
          if (e is Map) {
            return '${e['name'] ?? ''} ${e['amount'] ?? ''}'.trim();
          }
          return e.toString();
        })
        .join('、');

    final missingText = widget.missingAppliances.isEmpty
        ? '特になし'
        : widget.missingAppliances.join('、');

    final prompt = targetIngredient != null
        ? '料理「$dishTitle」（材料：$ingNames）を作る際、「$targetIngredient」が家にありません。\n'
              '持っていない調理家電【$missingText】を使わず、一人暮らしの家によくある身近な食材や調味料で代用する方法と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$dishTitle」（材料：$ingNames）について、\n'
              '持っていない調理家電【$missingText】を使わず、さらに安く手軽に作れる代替食材やアレンジのコツを200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

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
                targetIngredient != null
                    ? '「$targetIngredient」の代用案'
                    : '「$dishTitle」のAI代替提案',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('AI提案の詳細'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('データが見つかりません'));
          }

          final docSnap = snapshot.data as DocumentSnapshot;
          if (!docSnap.exists || docSnap.data() == null) {
            return const Center(child: Text('データが見つかりません'));
          }

          final data = docSnap.data() as Map;
          final String title = data['title']?.toString() ?? 'AIからの提案';
          final String content = data['content']?.toString() ?? '';
          final String subCategory = data['subCategory']?.toString() ?? '';
          final bool isRecipe =
              data['isRecipePost'] == true || subCategory == 'レシピ';

          final int baseServings =
              int.tryParse(data['recipeServings']?.toString() ?? '1') ?? 1;
          if (!_initializedServings) {
            _currentServings = baseServings;
            _initializedServings = true;
          }

          final String rawCost = data['recipeCost']?.toString() ?? '';
          final String scaledCost = _scaleAmountString(
            rawCost,
            baseServings,
            _currentServings,
          );
          final String recipeTime = data['recipeTime']?.toString() ?? '';
          final List ingredients = data['recipeIngredients'] != null
              ? List.from(data['recipeIngredients'])
              : [];
          final String steps = data['recipeSteps']?.toString() ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 150,
                  color: isRecipe ? Colors.orange.shade50 : Colors.teal.shade50,
                  child: Icon(
                    isRecipe ? Icons.restaurant_menu : Icons.lightbulb_outline,
                    size: 64,
                    color: isRecipe ? Colors.orange : Colors.teal,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: isRecipe ? Colors.orange : Colors.teal,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isRecipe ? 'AIが考えたあなた専用レシピ' : 'AIからの生活アドバイス',
                              style: TextStyle(
                                color: isRecipe ? Colors.orange : Colors.teal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isRecipe && ingredients.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _askDetailAiSubstitution(
                                dishTitle: title,
                                allIngredients: ingredients,
                              ),
                              icon: const Icon(
                                Icons.auto_awesome,
                                size: 15,
                                color: Colors.orange,
                              ),
                              label: const Text(
                                'AI代替提案',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isRecipe && ingredients.isNotEmpty) ...[
                        Wrap(
                          spacing: 16,
                          children: [
                            if (recipeTime.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(recipeTime),
                                ],
                              ),
                            if (scaledCost.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.payments_outlined,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$scaledCost（$_currentServings人分）',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const Divider(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '【材料】（$_currentServings人分）',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16),
                                    onPressed: _currentServings > 1
                                        ? () {
                                            setState(() {
                                              _currentServings--;
                                            });
                                          }
                                        : null,
                                  ),
                                  Text(
                                    '$_currentServings人分',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16),
                                    onPressed: _currentServings < 6
                                        ? () {
                                            setState(() {
                                              _currentServings++;
                                            });
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...ingredients.map((rawIng) {
                          final ingMap = rawIng as Map;
                          final name = ingMap['name']?.toString() ?? '';
                          final rawAmt = ingMap['amount']?.toString() ?? '';
                          final scaledAmt = _scaleAmountString(
                            rawAmt,
                            baseServings,
                            _currentServings,
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$name : $scaledAmt',
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _askDetailAiSubstitution(
                                    dishTitle: title,
                                    allIngredients: ingredients,
                                    targetIngredient: name,
                                  ),
                                  icon: const Icon(Icons.swap_horiz, size: 15),
                                  label: const Text(
                                    '代用案',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        const Text(
                          '【作り方】',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          steps.isNotEmpty ? steps : content,
                          style: const TextStyle(fontSize: 15, height: 1.6),
                        ),
                      ] else ...[
                        const Divider(height: 24),
                        Text(
                          content,
                          style: const TextStyle(fontSize: 16, height: 1.7),
                        ),
                      ],
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
