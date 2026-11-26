import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_screen.dart' show SnsScreen, PostImageCarousel;
import 'sns_detail_screen.dart' show SnsDetailScreen;
import 'sns_reply_screen.dart' show SnsReplyScreen;
import '../widgets/top_toast.dart' show showReactionToast;

class SnsSearchScreen extends StatefulWidget {
  final String? initialHashtag;

  const SnsSearchScreen({super.key, this.initialHashtag});

  @override
  State createState() => _SnsSearchScreenState();
}

class _SnsSearchScreenState extends State {
  final TextEditingController _searchController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentEmailPrefix =
      FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? '';

  String _searchQuery = '';
  String _selectedTag = 'すべて';
  String _selectedHashtag = '';
  bool _excludeAllergens = true;
  bool _recipeOnly = false;
  int? _maxRecipeCost;

  final List _tags = ['すべて', 'トレンド', '料理', '掃除', '収納', 'その他'];

  final _costPresets = const [
    {'label': '150円以下', 'max': 150},
    {'label': '300円以下', 'max': 300},
    {'label': '500円以下', 'max': 500},
    {'label': '1000円以下', 'max': 1000},
  ];
  final Map _servingsPerPost = {};

  final Map _postImageCache = {};
  final Map _userIconCache = {};

  late final Stream? _userPrefStream = currentUserId.isNotEmpty
      ? FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .snapshots()
      : null;

  late final Stream _postsStream = FirebaseFirestore.instance
      .collection('posts')
      .snapshots();

  @override
  void initState() {
    super.initState();
    final initial = (widget as SnsSearchScreen).initialHashtag?.trim() ?? '';
    if (initial.isNotEmpty) {
      _selectedHashtag = initial.replaceFirst(RegExp(r'^[#＃]+'), '').trim();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int? _extractCostYen(dynamic rawCost) {
    if (rawCost == null) return null;
    if (rawCost is num) {
      final value = rawCost.toInt();
      return value > 0 ? value : null;
    }
    final digitsOnly = rawCost.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;
    final parsed = int.tryParse(digitsOnly);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  bool _matchesRecipeCostFilter(Map data) {
    if (_maxRecipeCost == null) return true;
    final cost = _extractCostYen(data['recipeCost']);
    if (cost == null) return false;
    return cost <= _maxRecipeCost!;
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

  List _extractPostImages(String docId, Map post) {
    final List result = [];
    if (post['imagesBase64'] != null && post['imagesBase64'] is List) {
      final rawList = List.from(post['imagesBase64']);
      for (int i = 0; i < rawList.length; i++) {
        final bytes = _decodeAndCache(
          '${docId}_$i',
          rawList[i]?.toString(),
          _postImageCache,
        );
        if (bytes != null) {
          result.add(bytes);
        }
      }
    }
    if (result.isEmpty && post['imageBase64'] != null) {
      final bytes = _decodeAndCache(
        '${docId}_single',
        post['imageBase64']?.toString(),
        _postImageCache,
      );
      if (bytes != null) {
        result.add(bytes);
      }
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

  String _buildPostAllergyTarget(Map post) {
    final title = (post['title'] ?? post['recipeTitle'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final steps = (post['recipeSteps'] ?? '').toString();
    final List ingList = post['recipeIngredients'] is List
        ? List.from(post['recipeIngredients'])
        : const [];
    final ingText = ingList
        .where((e) => e is Map)
        .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}')
        .join('\n');
    return '$title\n$content\n$ingText\n$steps';
  }

  Widget _buildHighlightedContent(String content) {
    final List<TextSpan> spans = [];
    int lastEnd = 0;

    for (final match in SnsScreen.hashtagRegex.allMatches(content)) {
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

  Future _askAiSubstitution({
    required String recipeTitle,
    required List ingredients,
    required String steps,
    required List missingAppliances,
    required List allergies,
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
        .where((e) => e is Map)
        .map((e) {
          final m = e as Map;
          return '${m['name'] ?? ''}: ${m['amount'] ?? ''}';
        })
        .join('、');
    final missingText = missingAppliances.isEmpty
        ? 'なし'
        : missingAppliances.join('、');
    final allergyRule = AiChatScreen.buildAllergyPromptRule(allergies);

    final String prompt = targetIngredient != null
        ? '料理「$recipeTitle」（材料: $ingSummary）を作る際、「$targetIngredient」が家にありません。\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】は絶対に使わず、一人暮らしの家によくある身近な食材や調味料を使った「$targetIngredient」の代用案と分量の目安を、150文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。'
        : '料理「$recipeTitle」（材料: $ingSummary / 手順: $steps）について、\n'
              '持っていない調理家電【$missingText】と、アレルギー食材【$allergyRule】を一切使わずに作る方法、およびさらに安く簡単に作れる代替アレンジ案を200文字以内で簡潔に教えてください。Markdown記号（*や#）は使わないでください。';

    String aiReply = '代用案を取得できませんでした。もう一度お試しください。';

    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(model: modelItem.toString(), apiKey: key);
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          aiReply = res.text!.replaceAll('**', '').replaceAll('##', '').trim();
          break;
        }
      } catch (e) {}
    }

    if (allergies.isNotEmpty &&
        AiChatScreen.containsAllergen(aiReply, allergies)) {
      aiReply =
          'アレルギー対象食材（${allergies.join('・')}）に関連する表現が含まれたため表示を控えました。AI相談画面で使える手持ち食材を指定して聞いてみてください。';
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

  Future _toggleReaction({
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
    } catch (e) {}
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
        children: [
          for (final r in reasons)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.pop(dialogContext, r.toString()),
              child: Text(r.toString(), style: const TextStyle(fontSize: 15)),
            ),
        ],
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
    Map post,
    String docId,
    List missingAppliances,
    List allergies,
  ) {
    final String titleCandidate =
        (post['title']?.toString().trim().isNotEmpty == true)
        ? post['title'].toString().trim()
        : (post['recipeTitle']?.toString().trim() ?? '');
    final String recipeTitle = titleCandidate.isNotEmpty
        ? titleCandidate
        : '手作りレシピ';

    final int baseServings =
        int.tryParse(
          (post['recipeServings'] ?? post['baseServings'] ?? '1').toString(),
        ) ??
        1;
    final int currentServings =
        (_servingsPerPost[docId] as int?) ?? baseServings;

    final String rawCostText = post['recipeCost'] is int
        ? ((post['recipeCost'] as int) > 0 ? '約${post['recipeCost']}円' : '')
        : (post['recipeCost']?.toString().trim() ?? '');
    final String scaledCostText = rawCostText.isNotEmpty
        ? _scaleAmountString(rawCostText, baseServings, currentServings)
        : '';

    final String recipeTime = post['recipeTime']?.toString() ?? '';
    final List ingredients = post['recipeIngredients'] is List
        ? List.from(post['recipeIngredients'])
        : const [];
    final String steps = post['recipeSteps']?.toString() ?? '';

    final List matchedAllergens = allergies.isNotEmpty
        ? AiChatScreen.findMatchedAllergens(
            _buildPostAllergyTarget(post),
            allergies,
          )
        : const [];

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
          if (matchedAllergens.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'アレルギー設定食材（${matchedAllergens.join('・')}）を含む可能性があります',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
              OutlinedButton.icon(
                onPressed: () => _askAiSubstitution(
                  recipeTitle: recipeTitle,
                  ingredients: ingredients,
                  steps: steps,
                  missingAppliances: missingAppliances,
                  allergies: allergies,
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
            for (final item in ingredients)
              Builder(
                builder: (_) {
                  if (item is! Map) return const SizedBox.shrink();
                  final iName = item['name']?.toString() ?? '';
                  final iRawAmount = item['amount']?.toString() ?? '';
                  final iScaledAmount = _scaleAmountString(
                    iRawAmount,
                    baseServings,
                    currentServings,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '・$iName : $iScaledAmount',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _askAiSubstitution(
                            recipeTitle: recipeTitle,
                            ingredients: ingredients,
                            steps: steps,
                            missingAppliances: missingAppliances,
                            allergies: allergies,
                            targetIngredient: iName,
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _userPrefStream,
      builder: (context, myUserSnapshot) {
        List blockedUsers = [];
        List lessInterestedTopics = [];
        List missingAppliances = [];
        List allergies = [];

        if (myUserSnapshot.hasData && myUserSnapshot.data != null) {
          final myDoc = myUserSnapshot.data as DocumentSnapshot;
          if (myDoc.exists && myDoc.data() != null) {
            final myData = myDoc.data() as Map;
            blockedUsers = List.from(myData['blockedUsers'] ?? []);
            lessInterestedTopics = List.from(
              myData['lessInterestedTopics'] ?? [],
            );
            missingAppliances = List.from(myData['missingAppliances'] ?? []);
            if (myData['allergies'] is List) {
              allergies = List.from(myData['allergies'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
          }
        }

        final bool showRecipeCostFilter = _selectedTag == '料理' && _recipeOnly;

        return Scaffold(
          appBar: AppBar(
            leading: Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
            title: const Text(
              'さがす',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 0,
            backgroundColor: Colors.white,
          ),
          backgroundColor: Colors.grey.shade100,
          body: StreamBuilder(
            stream: _postsStream,
            builder: (context, snapshot) {
              final List rawDocs = (snapshot.hasData && snapshot.data != null)
                  ? (snapshot.data as QuerySnapshot).docs
                  : const [];

              final List baseVisibleDocs = [];
              for (final doc in rawDocs) {
                final data = doc.data() as Map;
                if (data['mainCategory'] == 'AI') continue;

                final List hiddenUsers = List.from(data['hiddenUsers'] ?? []);
                if (hiddenUsers.contains(currentUserId)) continue;

                final List reportedUsers = List.from(
                  data['reportedUsers'] ?? [],
                );
                if (reportedUsers.length >= 3 ||
                    reportedUsers.contains(currentUserId)) {
                  continue;
                }

                final String postUid = data['userId']?.toString() ?? '';
                final String postName = data['userName']?.toString() ?? '';
                if ((postUid.isNotEmpty && blockedUsers.contains(postUid)) ||
                    (postName.isNotEmpty && blockedUsers.contains(postName))) {
                  continue;
                }

                if (_excludeAllergens &&
                    allergies.isNotEmpty &&
                    data['isRecipePost'] == true) {
                  if (AiChatScreen.containsAllergen(
                    _buildPostAllergyTarget(data),
                    allergies,
                  )) {
                    continue;
                  }
                }

                baseVisibleDocs.add(doc);
              }

              final List categoryFilteredDocs = baseVisibleDocs.where((doc) {
                final data = (doc as QueryDocumentSnapshot).data() as Map;
                if (_selectedTag == 'すべて' || _selectedTag == 'トレンド') {
                  return true;
                }
                final mainCategory = (data['mainCategory'] ?? '').toString();
                final subCategory = (data['subCategory'] ?? '').toString();
                final matchesCategory =
                    mainCategory == _selectedTag || subCategory == _selectedTag;
                if (!matchesCategory) return false;

                if (_selectedTag == '料理' && _recipeOnly) {
                  if (data['isRecipePost'] != true) return false;
                  if (!_matchesRecipeCostFilter(data)) return false;
                }
                return true;
              }).toList();

              final Map hashtagCounts = {};
              for (final doc in categoryFilteredDocs) {
                final data = (doc as QueryDocumentSnapshot).data() as Map;
                final tags = SnsScreen.extractHashtagsFromPost(data);
                for (final rawT in tags) {
                  final t = rawT.toString();
                  hashtagCounts[t] = ((hashtagCounts[t] as int?) ?? 0) + 1;
                }
              }

              final List sortedHashtags = hashtagCounts.entries.toList()
                ..sort((a, b) => (b.value as int).compareTo(a.value as int));
              final List topHashtags = sortedHashtags
                  .take(15)
                  .map(
                    (e) => {'tag': e.key.toString(), 'count': e.value as int},
                  )
                  .toList();

              if (_selectedHashtag.isNotEmpty &&
                  !topHashtags.any(
                    (e) => (e as Map)['tag'] == _selectedHashtag,
                  )) {
                topHashtags.insert(0, {
                  'tag': _selectedHashtag,
                  'count': (hashtagCounts[_selectedHashtag] as int?) ?? 0,
                });
              }

              final String cleanedQuery = _searchQuery
                  .replaceFirst(RegExp(r'^[#＃]+'), '')
                  .trim();

              final List filteredDocs = categoryFilteredDocs.where((doc) {
                final data = (doc as QueryDocumentSnapshot).data() as Map;
                final List postHashtags = SnsScreen.extractHashtagsFromPost(
                  data,
                );

                if (_selectedHashtag.isNotEmpty &&
                    !postHashtags.contains(_selectedHashtag)) {
                  return false;
                }

                if (cleanedQuery.isEmpty) return true;

                final title = (data['title'] ?? data['recipeTitle'] ?? '')
                    .toString()
                    .toLowerCase();
                final content = (data['content'] ?? '')
                    .toString()
                    .toLowerCase();
                final userName = (data['userName'] ?? '')
                    .toString()
                    .toLowerCase();
                final steps = (data['recipeSteps'] ?? '')
                    .toString()
                    .toLowerCase();
                final mainCat = (data['mainCategory'] ?? '')
                    .toString()
                    .toLowerCase();
                final subCat = (data['subCategory'] ?? '')
                    .toString()
                    .toLowerCase();
                final aiTagsText = data['aiTags'] is List
                    ? List.from(data['aiTags']).join(' ').toLowerCase()
                    : '';
                final hashtagsText = postHashtags.join(' ').toLowerCase();
                final ingText = data['recipeIngredients'] is List
                    ? List.from(data['recipeIngredients'])
                          .where((e) => e is Map)
                          .map((e) => ((e as Map)['name'] ?? '').toString())
                          .join(' ')
                          .toLowerCase()
                    : '';

                return title.contains(cleanedQuery) ||
                    content.contains(cleanedQuery) ||
                    userName.contains(cleanedQuery) ||
                    steps.contains(cleanedQuery) ||
                    mainCat.contains(cleanedQuery) ||
                    subCat.contains(cleanedQuery) ||
                    aiTagsText.contains(cleanedQuery) ||
                    hashtagsText.contains(cleanedQuery) ||
                    ingText.contains(cleanedQuery);
              }).toList();

              filteredDocs.sort((a, b) {
                final aData = (a as QueryDocumentSnapshot).data() as Map;
                final bData = (b as QueryDocumentSnapshot).data() as Map;

                if (_selectedTag == 'トレンド') {
                  final aScore = aData['valueScore'] is num
                      ? (aData['valueScore'] as num).toDouble()
                      : ((aData['likedUsers'] is List)
                            ? (aData['likedUsers'] as List).length.toDouble()
                            : 0.0);
                  final bScore = bData['valueScore'] is num
                      ? (bData['valueScore'] as num).toDouble()
                      : ((bData['likedUsers'] is List)
                            ? (bData['likedUsers'] as List).length.toDouble()
                            : 0.0);
                  if (aScore != bScore) {
                    return bScore.compareTo(aScore);
                  }
                }

                final aTime = aData['createdAt'] as Timestamp?;
                final bTime = bData['createdAt'] as Timestamp?;
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              return Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.trim().toLowerCase();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'キーワード・食材・#ハッシュタグで検索...',
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
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final rawTag in _tags)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: ChoiceChip(
                                    label: Text(
                                      rawTag.toString(),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: _selectedTag == rawTag.toString(),
                                    showCheckmark: false,
                                    visualDensity: VisualDensity.compact,
                                    selectedColor: Colors.blue,
                                    backgroundColor: Colors.grey.shade100,
                                    labelStyle: TextStyle(
                                      color: _selectedTag == rawTag.toString()
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight:
                                          _selectedTag == rawTag.toString()
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    side: BorderSide.none,
                                    onSelected: (_) {
                                      final nextTag = rawTag.toString();
                                      setState(() {
                                        _selectedTag = nextTag;
                                        if (nextTag != '料理') {
                                          _recipeOnly = false;
                                          _maxRecipeCost = null;
                                        }
                                      });
                                    },
                                  ),
                                ),
                              if (_selectedTag == '料理')
                                Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: FilterChip(
                                    avatar: Icon(
                                      Icons.restaurant_menu,
                                      size: 14,
                                      color: _recipeOnly
                                          ? Colors.deepOrange.shade800
                                          : Colors.grey,
                                    ),
                                    label: Text(
                                      'レシピのみ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _recipeOnly
                                            ? Colors.deepOrange.shade900
                                            : Colors.black54,
                                        fontWeight: _recipeOnly
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    selected: _recipeOnly,
                                    showCheckmark: false,
                                    visualDensity: VisualDensity.compact,
                                    selectedColor: Colors.orange.shade100,
                                    backgroundColor: Colors.grey.shade100,
                                    side: BorderSide(
                                      color: _recipeOnly
                                          ? Colors.deepOrange.shade300
                                          : Colors.grey.shade300,
                                    ),
                                    onSelected: (val) {
                                      setState(() {
                                        _recipeOnly = val;
                                        if (!val) {
                                          _maxRecipeCost = null;
                                        }
                                      });
                                    },
                                  ),
                                ),
                              if (allergies.isNotEmpty)
                                FilterChip(
                                  avatar: Icon(
                                    Icons.no_food_outlined,
                                    size: 15,
                                    color: _excludeAllergens
                                        ? Colors.red.shade700
                                        : Colors.grey,
                                  ),
                                  label: Text(
                                    'アレルギー除外',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _excludeAllergens
                                          ? Colors.red.shade900
                                          : Colors.black54,
                                      fontWeight: _excludeAllergens
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: _excludeAllergens,
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  selectedColor: Colors.red.shade50,
                                  backgroundColor: Colors.grey.shade100,
                                  side: BorderSide(
                                    color: _excludeAllergens
                                        ? Colors.red.shade200
                                        : Colors.grey.shade300,
                                  ),
                                  onSelected: (val) {
                                    setState(() {
                                      _excludeAllergens = val;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                        if (showRecipeCostFilter) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: ChoiceChip(
                                    label: const Text(
                                      '材料費指定なし',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: _maxRecipeCost == null,
                                    showCheckmark: false,
                                    visualDensity: VisualDensity.compact,
                                    selectedColor: Colors.green.shade600,
                                    backgroundColor: Colors.grey.shade100,
                                    labelStyle: TextStyle(
                                      color: _maxRecipeCost == null
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: _maxRecipeCost == null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    side: BorderSide.none,
                                    onSelected: (_) {
                                      setState(() {
                                        _maxRecipeCost = null;
                                      });
                                    },
                                  ),
                                ),
                                for (final preset in _costPresets)
                                  Builder(
                                    builder: (_) {
                                      final int maxYen = preset['max'] as int;
                                      final String label =
                                          preset['label'] as String;
                                      final bool selected =
                                          _maxRecipeCost == maxYen;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6.0,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            label,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          selected: selected,
                                          showCheckmark: false,
                                          visualDensity: VisualDensity.compact,
                                          selectedColor: Colors.green.shade600,
                                          backgroundColor: Colors.grey.shade100,
                                          labelStyle: TextStyle(
                                            color: selected
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: selected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                          side: BorderSide.none,
                                          onSelected: (_) {
                                            setState(() {
                                              _maxRecipeCost = selected
                                                  ? null
                                                  : maxYen;
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (topHashtags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (_selectedHashtag.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      avatar: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.black54,
                                      ),
                                      label: const Text(
                                        'タグ解除',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor: Colors.grey.shade100,
                                      onPressed: () {
                                        setState(() => _selectedHashtag = '');
                                      },
                                    ),
                                  ),
                                for (final rawH in topHashtags)
                                  Builder(
                                    builder: (_) {
                                      final h = rawH as Map;
                                      final tag = h['tag'].toString();
                                      final count = h['count'] as int;
                                      final selected = _selectedHashtag == tag;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6.0,
                                        ),
                                        child: FilterChip(
                                          label: Text('#$tag ($count)'),
                                          selected: selected,
                                          showCheckmark: false,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          selectedColor: Colors.indigo.shade50,
                                          backgroundColor: Colors.grey.shade50,
                                          side: BorderSide(
                                            color: selected
                                                ? Colors.indigo
                                                : Colors.grey.shade300,
                                          ),
                                          labelStyle: TextStyle(
                                            fontSize: 12,
                                            color: selected
                                                ? Colors.indigo.shade800
                                                : Colors.blue.shade800,
                                            fontWeight: selected
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                          shape: const StadiumBorder(),
                                          onSelected: (_) {
                                            setState(() {
                                              _selectedHashtag = selected
                                                  ? ''
                                                  : tag;
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedHashtag.isNotEmpty
                                ? '#$_selectedHashtag の投稿（${filteredDocs.length}件）'
                                : (_selectedTag == 'トレンド'
                                      ? 'トレンドの投稿（${filteredDocs.length}件）'
                                      : (_selectedTag == '料理' && _recipeOnly
                                            ? (_maxRecipeCost != null
                                                  ? '料理レシピ（${_maxRecipeCost}円以下・${filteredDocs.length}件）'
                                                  : '料理レシピの投稿（${filteredDocs.length}件）')
                                            : '検索結果（${filteredDocs.length}件）')),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_selectedHashtag.isNotEmpty ||
                            _searchQuery.isNotEmpty ||
                            _selectedTag != 'すべて' ||
                            _recipeOnly ||
                            _maxRecipeCost != null)
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedTag = 'すべて';
                                _selectedHashtag = '';
                                _recipeOnly = false;
                                _maxRecipeCost = null;
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              '条件リセット',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator())
                        : filteredDocs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 46,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  '該当する投稿が見つかりませんでした',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 110),
                                itemCount: filteredDocs.length,
                                itemBuilder: (context, index) {
                                  final doc =
                                      filteredDocs[index]
                                          as QueryDocumentSnapshot;
                                  final data = doc.data() as Map;
                                  final docId = doc.id;
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
                                    allergies,
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPostCard(
    Map post,
    String docId,
    BuildContext context,
    String topicKey,
    bool isTopicDemoted,
    List missingAppliances,
    List allergies,
  ) {
    final bool isRecipePost = post['isRecipePost'] == true;
    final int replies = _readReactionCount(post['replies'], const []);

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

    final int likesCount = _readReactionCount(post['likes'], likedUsers);
    final int helpfulsCount = _readReactionCount(
      post['helpfuls'],
      helpfulUsers,
    );
    final int savesCount = _readReactionCount(post['saves'], savedUsers);
    final int impressionsCount = AiKnowledgeService.readIntField(
      post['impressions'],
    );

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

    final List postImages = _extractPostImages(docId, post);
    final List postHashtags = SnsScreen.extractHashtagsFromPost(post);

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
            final uData = userDoc.data() as Map;
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

        final Uint8List? userIconBytes = _decodeAndCache(
          targetUserKey,
          displayIconBase64,
          _userIconCache,
        );

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
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                left: BorderSide(color: Colors.grey.shade200, width: 0.5),
                right: BorderSide(color: Colors.grey.shade200, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        spacing: 6.0,
                        runSpacing: 4.0,
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
                          if (isTopicDemoted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
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
                if (!isRecipePost &&
                    (post['title']?.toString().trim().isNotEmpty == true))
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0, bottom: 2.0),
                    child: Text(
                      post['title'].toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                if ((post['content']?.toString().trim() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _buildHighlightedContent(post['content'].toString()),
                  ),
                if (postHashtags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final rawTag in postHashtags)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                _selectedHashtag = rawTag.toString();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedHashtag == rawTag.toString()
                                    ? Colors.indigo.shade100
                                    : Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedHashtag == rawTag.toString()
                                      ? Colors.indigo
                                      : Colors.indigo.shade100,
                                ),
                              ),
                              child: Text(
                                '#${rawTag.toString()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (isRecipePost)
                  _buildRecipeSection(
                    post,
                    docId,
                    missingAppliances,
                    allergies,
                  ),
                if (postImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: PostImageCarousel(
                      imagesList: postImages,
                      keyPrefix: 'search_$docId',
                    ),
                  ),
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
                        docId: docId,
                        listField: 'likedUsers',
                        countField: 'likes',
                        currentUsers: likedUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: replies,
                        impressionsCount: impressionsCount,
                      ),
                    ),
                    _buildActionButton(
                      icon: isHelpful
                          ? Icons.lightbulb
                          : Icons.lightbulb_outline,
                      color: isHelpful ? Colors.orange : Colors.grey,
                      count: helpfulsCount,
                      onTap: () => _toggleReaction(
                        docId: docId,
                        listField: 'helpfulUsers',
                        countField: 'helpfuls',
                        currentUsers: helpfulUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: replies,
                        impressionsCount: impressionsCount,
                      ),
                    ),
                    _buildActionButton(
                      icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: isSaved ? Colors.blue : Colors.grey,
                      count: savesCount,
                      onTap: () => _toggleReaction(
                        docId: docId,
                        listField: 'savedUsers',
                        countField: 'saves',
                        currentUsers: savedUsers,
                        likesCount: likesCount,
                        helpfulsCount: helpfulsCount,
                        savesCount: savesCount,
                        repliesCount: replies,
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
}
