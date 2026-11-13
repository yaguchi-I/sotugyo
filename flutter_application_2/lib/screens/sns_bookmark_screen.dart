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

class _SnsBookmarkScreenState extends State {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _selectedMainCategory = 'すべて';
  String _selectedSubCategory = 'すべて';

  final Map _servingsPerPost = {};
  List _missingAppliances = [];

  final List _mainCategories = ['すべて', '料理', '掃除', '収納', 'AI', 'その他'];
  final Map _subCategories = {
    'すべて': ['すべて'],
    '料理': ['すべて', '野菜', '肉類', '麺類', '作り置き', 'その他'],
    '掃除': ['すべて', 'キッチン', 'お風呂', 'トイレ', 'リビング', 'その他'],
    '収納': ['すべて', 'クローゼット', 'デスク周り', '小物', 'その他'],
    'AI': ['すべて', 'レシピ', '節約術'],
    'その他': ['すべて', 'その他'],
  };

  @override
  void initState() {
    super.initState();
    _loadUserAppliances();
  }

  Future _loadUserAppliances() async {
    if (currentUserId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _missingAppliances = List.from(data['missingAppliances'] ?? []);
        });
      }
    } catch (e) {}
  }

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
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
    final missingText = _missingAppliances.isEmpty
        ? 'なし'
        : _missingAppliances.join('、');

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

  Widget _buildRecipeBookmarkCard(dynamic post, String docId) {
    final String recipeTitle =
        post['recipeTitle']?.toString().isNotEmpty == true
        ? post['recipeTitle'].toString()
        : '投稿レシピ';
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
    final String comment = post['content']?.toString() ?? '';
    final Uint8List? imageBytes = _decodeBase64(
      post['imageBase64']?.toString(),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '👤 ${post['userName'] ?? 'ユーザー'} のレシピ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _askAiSubstitution(
                    recipeTitle: recipeTitle,
                    ingredients: ingredients,
                    steps: steps,
                  ),
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.orange,
                  ),
                  label: const Text(
                    'AI 代替提案',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark, color: Colors.blue),
                  tooltip: '保存を解除',
                  onPressed: () {
                    FirebaseFirestore.instance
                        .collection('posts')
                        .doc(docId)
                        .update({
                          'savedUsers': FieldValue.arrayRemove([currentUserId]),
                        });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              recipeTitle,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (recipeTime.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('目安 $recipeTime'),
                    ],
                  ),
                if (baseCost > 0)
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
                        '約$scaledCost円（$currentServings人分）',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (imageBytes != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(imageBytes, fit: BoxFit.contain),
                ),
              ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '【材料】（$currentServings人分）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: currentServings > 1
                            ? () {
                                setState(() {
                                  _servingsPerPost[docId] = currentServings - 1;
                                });
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          '$currentServings人分',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
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
            const SizedBox(height: 8),
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
                        '$iName ： $iScaledAmount',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _askAiSubstitution(
                        recipeTitle: recipeTitle,
                        ingredients: ingredients,
                        steps: steps,
                        targetIngredient: iName,
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 15),
                      label: const Text('代用案', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
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
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '【作り方】',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(steps, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '💬 投稿者メモ: $comment',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
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
    final List currentSubs = List.from(
      _subCategories[_selectedMainCategory] ?? ['すべて'],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text('保存フォルダ'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Row(
              children: _mainCategories.map((cat) {
                final catStr = cat.toString();
                final isSelected = _selectedMainCategory == catStr;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(catStr),
                    selected: isSelected,
                    selectedColor: Colors.blue.shade100,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedMainCategory = catStr;
                          _selectedSubCategory = 'すべて';
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (currentSubs.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Row(
                children: currentSubs.map((sub) {
                  final subStr = sub.toString();
                  final isSelected = _selectedSubCategory == subStr;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(subStr),
                      selected: isSelected,
                      selectedColor: Colors.green.shade100,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedSubCategory = subStr);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: currentUserId.isEmpty
                ? const Center(child: Text('ログインしてください'))
                : StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('posts')
                        .where('savedUsers', arrayContains: currentUserId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: Text('保存された投稿はありません'));
                      }

                      final querySnap = snapshot.data as QuerySnapshot;
                      final filtered = querySnap.docs.where((doc) {
                        final data = doc.data() as Map;
                        final mainCat = data['mainCategory']?.toString() ?? '';
                        final subCat = data['subCategory']?.toString() ?? '';

                        if (_selectedMainCategory != 'すべて' &&
                            mainCat != _selectedMainCategory) {
                          return false;
                        }
                        if (_selectedSubCategory != 'すべて' &&
                            subCat != _selectedSubCategory) {
                          return false;
                        }
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'このカテゴリに保存された投稿はありません',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 110.0),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final dynamic data = doc.data();
                          final bool isRecipePost =
                              data['isRecipePost'] == true;

                          if (isRecipePost) {
                            return _buildRecipeBookmarkCard(data, doc.id);
                          }

                          final Uint8List? postImageBytes = _decodeBase64(
                            data['imageBase64']?.toString(),
                          );

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              data['userName']?.toString() ?? '投稿',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(data['content']?.toString() ?? ''),
                                if (postImageBytes != null) ...[
                                  const SizedBox(height: 8),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 160,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        postImageBytes,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.bookmark,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('posts')
                                    .doc(doc.id)
                                    .update({
                                      'savedUsers': FieldValue.arrayRemove([
                                        currentUserId,
                                      ]),
                                    });
                              },
                            ),
                            onTap: () {
                              if (data['mainCategory'] != 'AI') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        SnsDetailScreen(postId: doc.id),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
