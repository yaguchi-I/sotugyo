import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_reply_screen.dart' show SnsReplyScreen;
import 'sns_detail_screen.dart' show SnsDetailScreen;
import 'sns_add_screen.dart' show openPostScreen;
import 'user_profile_screen.dart' show UserProfileScreen;
import '../widgets/top_toast.dart' show showReactionToast;

class SnsScreen extends StatefulWidget {
  const SnsScreen({super.key});

  static final RegExp hashtagRegex = RegExp(
    r'[#＃]([^\s#＃、,。\.!！?？\(\)（）「」『』【】]+)',
  );

  static List extractHashtagsFromText(String text) {
    final List result = [];
    if (text.trim().isEmpty) return result;
    for (final match in hashtagRegex.allMatches(text)) {
      final tag = (match.group(1) ?? '').trim();
      if (tag.isNotEmpty && !result.contains(tag)) {
        result.add(tag);
      }
    }
    return result;
  }

  static List extractHashtagsFromPost(Map post) {
    final List result = [];
    if (post['hashtags'] is List) {
      for (final raw in List.from(post['hashtags'])) {
        final cleaned = raw
            .toString()
            .trim()
            .replaceFirst(RegExp(r'^[#＃]+'), '')
            .trim();
        if (cleaned.isNotEmpty && !result.contains(cleaned)) {
          result.add(cleaned);
        }
      }
    }
    final titleTags = extractHashtagsFromText((post['title'] ?? '').toString());
    final contentTags = extractHashtagsFromText(
      (post['content'] ?? '').toString(),
    );
    for (final t in [...titleTags, ...contentTags]) {
      final str = t.toString();
      if (!result.contains(str)) {
        result.add(str);
      }
    }
    return result;
  }

  @override
  State createState() => _SnsScreenState();
}

class _SnsScreenState extends State with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _recommendScrollCtrl = ScrollController();
  final ScrollController _followingScrollCtrl = ScrollController();
  final ScrollController _tagScrollCtrl = ScrollController();
  bool _showScrollToTop = false;

  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String currentEmailPrefix =
      (FirebaseAuth.instance.currentUser?.email ?? '').split('@').first;

  bool _isDeveloper = true;

  final Map _servingsPerPost = {};
  final Map _postImageCache = {};
  final Map _userIconCache = {};
  final Set _viewedPostIds = Set();

  static const String _followingField = 'following';

  static const String _all = 'すべて';
  static const Map _tagCategories = {
    '料理': ['野菜', '肉類', '麺類', '作り置き', 'その他'],
    '掃除': ['キッチン', 'お風呂', 'トイレ', 'リビング', 'その他'],
    '収納': ['クローゼット', 'デスク周り', '小物', 'その他'],
    'その他': [],
  };
  static const Map _tagIcons = {
    _all: Icons.apps,
    '料理': Icons.restaurant,
    '掃除': Icons.cleaning_services_outlined,
    '収納': Icons.inventory_2_outlined,
    'その他': Icons.more_horiz,
  };
  String _tagMain = _all;
  String _tagSub = _all;
  String _selectedHashtag = '';

  late final Stream? _userPrefStream = currentUserId.isNotEmpty
      ? FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .snapshots()
      : null;
  late final Stream _postsStream = FirebaseFirestore.instance
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_updateScrollToTopVisibility);
    _recommendScrollCtrl.addListener(_updateScrollToTopVisibility);
    _followingScrollCtrl.addListener(_updateScrollToTopVisibility);
    _tagScrollCtrl.addListener(_updateScrollToTopVisibility);
  }

  @override
  void dispose() {
    _tabController.removeListener(_updateScrollToTopVisibility);
    _recommendScrollCtrl.removeListener(_updateScrollToTopVisibility);
    _followingScrollCtrl.removeListener(_updateScrollToTopVisibility);
    _tagScrollCtrl.removeListener(_updateScrollToTopVisibility);
    _tabController.dispose();
    _recommendScrollCtrl.dispose();
    _followingScrollCtrl.dispose();
    _tagScrollCtrl.dispose();
    super.dispose();
  }

  ScrollController get _activeScrollController {
    switch (_tabController.index) {
      case 1:
        return _followingScrollCtrl;
      case 2:
        return _tagScrollCtrl;
      default:
        return _recommendScrollCtrl;
    }
  }

  void _updateScrollToTopVisibility() {
    final ctrl = _activeScrollController;
    final bool shouldShow = ctrl.hasClients && ctrl.offset > 300;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }

  void _scrollToTop() {
    final ctrl = _activeScrollController;
    if (ctrl.hasClients) {
      ctrl.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  int _extractCreatedAtMillis(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      return raw.millisecondsSinceEpoch;
    }
    if (raw is DateTime) {
      return raw.millisecondsSinceEpoch;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    if (doc.metadata.hasPendingWrites) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    return 0;
  }

  List _sortByNewest(List docs) {
    final List sorted = List.from(docs);
    sorted.sort((a, b) {
      final docA = a as QueryDocumentSnapshot;
      final docB = b as QueryDocumentSnapshot;
      final timeA = _extractCreatedAtMillis(docA);
      final timeB = _extractCreatedAtMillis(docB);
      if (timeB != timeA) {
        return timeB.compareTo(timeA);
      }
      return docB.id.compareTo(docA.id);
    });
    return sorted;
  }

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

  void _selectHashtagAndJump(String tag) {
    final cleaned = tag.trim().replaceFirst(RegExp(r'^[#＃]+'), '').trim();
    if (cleaned.isEmpty) return;
    setState(() {
      _tagMain = _all;
      _tagSub = _all;
      _selectedHashtag = cleaned;
    });
    if (_tabController.index != 2) {
      _tabController.animateTo(2);
    }
    if (_tagScrollCtrl.hasClients) {
      _tagScrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
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

  void _recordImpressionOnce(
    String docId,
    int likes,
    int helpfuls,
    int saves,
    int replies,
    int currentImpressions,
  ) {
    if (docId.isEmpty || _viewedPostIds.contains(docId)) return;
    _viewedPostIds.add(docId);

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
        .doc(docId)
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

  List _extractPostImages(String docId, dynamic post) {
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
    required List allergies,
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
      } catch (e) {}
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

  Future _sendReactionNotification({
    required String targetUserId,
    required String postId,
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
        'postId': postId,
        'postSummary': postSummary,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {}
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
    required String postOwnerUid,
    required String postSummary,
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

      if (!isAdded && (countField == 'likes' || countField == 'helpfuls')) {
        _sendReactionNotification(
          targetUserId: postOwnerUid,
          postId: docId,
          postSummary: postSummary,
          type: countField == 'likes' ? 'like' : 'helpful',
        );
      }
    } catch (e) {}
  }

  Future _runBackfillDialog() async {
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: Colors.deepPurple),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '過去投稿のAIタグ＆スコア一括整理',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          '既存のすべての投稿をAIで解析し、検索用タグ（aiTags）・価格帯（priceTier）・評価スコア（valueScore）を一括更新します。実行しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('一括整理を実行'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final ValueNotifier progressText = ValueNotifier('準備中...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder(
          valueListenable: progressText,
          builder: (_, val, __) {
            return Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(val.toString())),
              ],
            );
          },
        ),
      ),
    );

    try {
      final count = await AiKnowledgeService.backfillAllExistingPosts(
        onProgress: (current, total) {
          progressText.value = 'AI解析＆DB整理中... ($current / $total 件)';
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('🛠️ $count 件の投稿をAI検索対応へ整理しました！')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('一括整理に失敗しました: $e')));
    }
  }

  Future _showDeveloperEditCountsDialog({
    required String docId,
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
                  '対象投稿ID: $docId',
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
        await FirebaseFirestore.instance.collection('posts').doc(docId).update({
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

  void _openPostInAiChat(String docId, Map post, String displayUserName) {
    final title = (post['title'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final preview = title.isNotEmpty ? title : content;
    final shortPreview = preview.length > 36
        ? '${preview.substring(0, 36)}...'
        : preview;

    final Map lightweightContext = {
      'docId': docId,
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

  void _showPostOptions({
    required String docId,
    required bool isMyPost,
    required String topicKey,
    required bool isTopicDemoted,
    required String targetUserKey,
    required String displayUserName,
    required int currentLikes,
    required int currentHelpfuls,
    required int currentSaves,
    required int currentReplies,
    required int currentImpressions,
    required double currentValueScore,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              if (_isDeveloper)
                ListTile(
                  leading: const Icon(
                    Icons.build_circle_outlined,
                    color: Colors.deepPurple,
                  ),
                  title: const Text(
                    '🛠️ [開発者専用] 数値・インプ・スコアを変更する',
                    style: TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '♥$currentLikes / 💡$currentHelpfuls / 🔖$currentSaves / 👁$currentImpressions / Score:${currentValueScore.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDeveloperEditCountsDialog(
                      docId: docId,
                      currentLikes: currentLikes,
                      currentHelpfuls: currentHelpfuls,
                      currentSaves: currentSaves,
                      currentReplies: currentReplies,
                      currentImpressions: currentImpressions,
                    );
                  },
                ),
              if (isMyPost || _isDeveloper)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    isMyPost ? 'この投稿を削除する' : '🛠️ [開発者専用] この投稿を削除する',
                    style: const TextStyle(color: Colors.red),
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

  Widget _buildNotificationButton() {
    if (currentUserId.isEmpty) {
      return IconButton(
        tooltip: '通知',
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () {},
      );
    }

    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('targetUserId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snap) {
        int unreadCount = 0;
        if (snap.hasData && snap.data != null) {
          final docs = (snap.data as QuerySnapshot).docs;
          for (final d in docs) {
            final data = d.data() as Map;
            if (data['isRead'] != true) {
              unreadCount++;
            }
          }
        }

        return IconButton(
          tooltip: '通知一覧',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              if (unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      floatingActionButton: FloatingActionButton(
        heroTag: 'postBtn',
        onPressed: () => openPostScreen(context),
        tooltip: '投稿する',
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined, size: 26),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),
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
            'タイムライン',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          if (_isDeveloper)
            IconButton(
              tooltip: '過去投稿のAIタグ＆スコア一括整理',
              icon: const Icon(Icons.auto_fix_high, color: Colors.deepPurple),
              onPressed: _runBackfillDialog,
            ),
          _buildNotificationButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          tabs: const [
            Tab(text: 'おすすめ'),
            Tab(text: 'フォロー中'),
            Tab(text: 'タグ別'),
          ],
        ),
      ),
      body: Stack(
        children: [
          StreamBuilder(
            stream: _userPrefStream,
            builder: (context, userPrefSnap) {
              List interestedTags = [];
              List lessInterestedTopics = [];
              List blockedUsers = [];
              List missingAppliances = [];
              List allergies = [];
              final Set<String> followingSet = {};

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
                  if (uData['allergies'] is List) {
                    allergies = List.from(uData['allergies'])
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                  }
                  if (uData[_followingField] is List) {
                    for (final item in List.from(uData[_followingField])) {
                      final idStr = item?.toString().trim() ?? '';
                      if (idStr.isNotEmpty) followingSet.add(idStr);
                    }
                  }
                  if (uData['followingUsers'] is List) {
                    for (final item in List.from(uData['followingUsers'])) {
                      final idStr = item?.toString().trim() ?? '';
                      if (idStr.isNotEmpty) followingSet.add(idStr);
                    }
                  }
                }
              }

              final List followingUsers = followingSet.toList();

              return StreamBuilder(
                stream: _postsStream,
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
                    if ((postUid.isNotEmpty &&
                            blockedUsers.contains(postUid)) ||
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
                    if (scoreB != scoreA) {
                      return scoreB.compareTo(scoreA);
                    }
                    final valA = dataA['valueScore'] is num
                        ? (dataA['valueScore'] as num).toDouble()
                        : 0.0;
                    final valB = dataB['valueScore'] is num
                        ? (dataB['valueScore'] as num).toDouble()
                        : 0.0;
                    return valB.compareTo(valA);
                  });

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFeedList(
                        docs: recommendedDocs,
                        controller: _recommendScrollCtrl,
                        isRecommendedTab: true,
                        interestedTags: interestedTags,
                        lessInterestedTopics: lessInterestedTopics,
                        missingAppliances: missingAppliances,
                        allergies: allergies,
                      ),
                      _buildFollowingFeed(
                        docs: visibleDocs,
                        followingUsers: followingUsers,
                        interestedTags: interestedTags,
                        lessInterestedTopics: lessInterestedTopics,
                        missingAppliances: missingAppliances,
                        allergies: allergies,
                      ),
                      _buildTagFeed(
                        docs: visibleDocs,
                        interestedTags: interestedTags,
                        lessInterestedTopics: lessInterestedTopics,
                        missingAppliances: missingAppliances,
                        allergies: allergies,
                      ),
                    ],
                  );
                },
              );
            },
          ),
          if (_showScrollToTop)
            Positioned(
              right: 24,
              bottom: 88,
              child: FloatingActionButton.small(
                heroTag: 'scrollToTopBtn',
                tooltip: '一番上へ戻る',
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFollowingFeed({
    required List docs,
    required List followingUsers,
    required List interestedTags,
    required List lessInterestedTopics,
    required List missingAppliances,
    required List allergies,
  }) {
    if (followingUsers.isEmpty) {
      return _buildFollowingEmpty(
        icon: Icons.person_add_alt_1_outlined,
        title: 'まだ誰もフォローしていません',
        message: '気になる投稿者をフォローすると、\nその人の投稿だけがここに並びます',
      );
    }

    final filtered = _sortByNewest(
      docs.where((d) {
        final post = (d as QueryDocumentSnapshot).data() as Map;
        final uid = post['userId']?.toString().trim() ?? '';
        return uid.isNotEmpty && followingUsers.contains(uid);
      }).toList(),
    );

    if (filtered.isEmpty) {
      return _buildFollowingEmpty(
        icon: Icons.forum_outlined,
        title: 'フォロー中の人の投稿はまだありません',
        message: '新しい投稿があるとここに表示されます',
      );
    }

    return _buildFeedList(
      docs: filtered,
      controller: _followingScrollCtrl,
      isRecommendedTab: false,
      interestedTags: interestedTags,
      lessInterestedTopics: lessInterestedTopics,
      missingAppliances: missingAppliances,
      allergies: allergies,
    );
  }

  Widget _buildFollowingEmpty({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('おすすめから探す'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesCategory(Map post, String main, String sub) {
    if (main == _all) return true;
    final postMain = post['mainCategory']?.toString() ?? '';
    if (postMain != main) return false;
    if (sub == _all) return true;
    return (post['subCategory']?.toString() ?? '') == sub;
  }

  int _countCategory(List docs, String main, String sub) {
    int count = 0;
    for (final d in docs) {
      final post = (d as QueryDocumentSnapshot).data() as Map;
      if (_matchesCategory(post, main, sub)) count++;
    }
    return count;
  }

  Widget _buildTagFeed({
    required List docs,
    required List interestedTags,
    required List lessInterestedTopics,
    required List missingAppliances,
    required List allergies,
  }) {
    final categoryDocs = docs.where((d) {
      final post = (d as QueryDocumentSnapshot).data() as Map;
      return _matchesCategory(post, _tagMain, _tagSub);
    }).toList();

    final Map hashtagCounts = {};
    for (final d in categoryDocs) {
      final post = (d as QueryDocumentSnapshot).data() as Map;
      final tags = SnsScreen.extractHashtagsFromPost(post);
      for (final rawTag in tags) {
        final t = rawTag.toString();
        hashtagCounts[t] = ((hashtagCounts[t] as int?) ?? 0) + 1;
      }
    }

    final List sortedHashtags = hashtagCounts.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    final List topHashtags = sortedHashtags
        .take(15)
        .map((e) => {'tag': e.key.toString(), 'count': e.value as int})
        .toList();

    if (_selectedHashtag.isNotEmpty &&
        !topHashtags.any((e) => (e as Map)['tag'] == _selectedHashtag)) {
      topHashtags.insert(0, {
        'tag': _selectedHashtag,
        'count': (hashtagCounts[_selectedHashtag] as int?) ?? 0,
      });
    }

    final filtered = _sortByNewest(
      _selectedHashtag.isEmpty
          ? categoryDocs
          : categoryDocs.where((d) {
              final post = (d as QueryDocumentSnapshot).data() as Map;
              final tags = SnsScreen.extractHashtagsFromPost(post);
              return tags.contains(_selectedHashtag);
            }).toList(),
    );

    final List mainList = [_all, ..._tagCategories.keys];
    final List subList = _tagMain == _all
        ? []
        : List.from(_tagCategories[_tagMain] ?? []);

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: mainList.map((rawMain) {
                    final main = rawMain.toString();
                    final selected = _tagMain == main;
                    final count = _countCategory(docs, main, _all);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(
                          (_tagIcons[main] as IconData?) ?? Icons.label_outline,
                          size: 18,
                          color: selected ? Colors.white : Colors.black54,
                        ),
                        label: Text('$main  $count'),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: Colors.blue,
                        backgroundColor: Colors.grey.shade100,
                        side: BorderSide(
                          color: selected ? Colors.blue : Colors.grey.shade300,
                        ),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        shape: const StadiumBorder(),
                        onSelected: (_) {
                          setState(() {
                            _tagMain = main;
                            _tagSub = _all;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: subList.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [_all, ...subList].map((rawSub) {
                              final sub = rawSub.toString();
                              final selected = _tagSub == sub;
                              final count = _countCategory(docs, _tagMain, sub);
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text('$sub $count'),
                                  selected: selected,
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  selectedColor: Colors.blue.shade50,
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                    color: selected
                                        ? Colors.blue
                                        : Colors.grey.shade300,
                                  ),
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? Colors.blue.shade800
                                        : Colors.black54,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  shape: const StadiumBorder(),
                                  onSelected: (_) {
                                    setState(() => _tagSub = sub);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),
              if (topHashtags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (_selectedHashtag.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
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
                                padding: const EdgeInsets.only(right: 6),
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
                                      _selectedHashtag = selected ? '' : tag;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedHashtag.isNotEmpty
                            ? Icons.tag
                            : ((_tagIcons[_tagMain] as IconData?) ??
                                  Icons.label_outline),
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedHashtag.isNotEmpty
                            ? '「#$_selectedHashtag」に一致する投稿はありません'
                            : (_tagSub == _all
                                  ? '「$_tagMain」の投稿はまだありません'
                                  : '「$_tagMain・$_tagSub」の投稿はまだありません'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (_selectedHashtag.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _selectedHashtag = '');
                          },
                          child: const Text('ハッシュタグ絞り込みを解除'),
                        ),
                      ],
                    ],
                  ),
                )
              : _buildFeedList(
                  docs: filtered,
                  controller: _tagScrollCtrl,
                  isRecommendedTab: false,
                  interestedTags: interestedTags,
                  lessInterestedTopics: lessInterestedTopics,
                  missingAppliances: missingAppliances,
                  allergies: allergies,
                ),
        ),
      ],
    );
  }

  Widget _buildFeedList({
    required List docs,
    required ScrollController controller,
    required bool isRecommendedTab,
    required List interestedTags,
    required List lessInterestedTopics,
    required List missingAppliances,
    required List allergies,
  }) {
    if (docs.isEmpty) {
      return const Center(
        child: Text('表示できる投稿がありません', style: TextStyle(color: Colors.grey)),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            if (isRecommendedTab && interestedTags.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                      for (final t in interestedTags)
                        Padding(
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
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: controller,
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

                  return KeyedSubtree(
                    key: ValueKey(doc.id),
                    child: _buildPostCard(
                      post: post,
                      docId: doc.id,
                      context: context,
                      topicKey: topicKey,
                      isTopicDemoted: isTopicDemoted,
                      isMatchedInterest: isMatchedInterest,
                      missingAppliances: missingAppliances,
                      allergies: allergies,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard({
    required Map post,
    required String docId,
    required BuildContext context,
    required String topicKey,
    required bool isTopicDemoted,
    required bool isMatchedInterest,
    required List missingAppliances,
    required List allergies,
  }) {
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
    final double valueScore = post['valueScore'] is num
        ? (post['valueScore'] as num).toDouble()
        : AiKnowledgeService.calculateValueScore(
            likes: likesCount,
            helpfuls: helpfulsCount,
            saves: savesCount,
            replies: replies,
            impressions: impressionsCount,
          );

    _recordImpressionOnce(
      docId,
      likesCount,
      helpfulsCount,
      savesCount,
      replies,
      impressionsCount,
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

    final String postSummary = (post['title']?.toString().isNotEmpty == true)
        ? post['title'].toString()
        : (post['content']?.toString() ?? '');

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

        List matchedAllergens = [];
        if (isRecipePost && allergies.isNotEmpty) {
          final ingText = recipeIngredients
              .where((e) => e is Map)
              .map((e) => '${(e as Map)['name'] ?? ''} ${e['amount'] ?? ''}')
              .join('\n');
          matchedAllergens = AiChatScreen.findMatchedAllergens(
            '${post['title'] ?? ''}\n$ingText\n$recipeSteps',
            allergies,
          );
        }

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
                left: BorderSide(color: Colors.grey.shade200, width: 0.5),
                right: BorderSide(color: Colors.grey.shade200, width: 0.5),
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
                    GestureDetector(
                      onTap: () => _openUserProfile(
                        context,
                        userId: targetLookupUid,
                        userName: displayUserName,
                        iconBase64: displayIconBase64,
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue.shade100,
                        backgroundImage: userIconBytes != null
                            ? MemoryImage(userIconBytes)
                            : null,
                        child: userIconBytes == null
                            ? const Icon(Icons.person, color: Colors.blue)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          GestureDetector(
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
                                fontSize: 15,
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
                        currentLikes: likesCount,
                        currentHelpfuls: helpfulsCount,
                        currentSaves: savesCount,
                        currentReplies: replies,
                        currentImpressions: impressionsCount,
                        currentValueScore: valueScore,
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
                            onTap: () =>
                                _selectHashtagAndJump(rawTag.toString()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.indigo.shade100,
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
                        if (matchedAllergens.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
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
                        for (final rawIng in recipeIngredients)
                          Builder(
                            builder: (_) {
                              final ingMap = rawIng as Map;
                              final name = ingMap['name']?.toString() ?? '';
                              final rawAmt = ingMap['amount']?.toString() ?? '';
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
                                      onPressed: () =>
                                          _askAiIngredientSubstitution(
                                            dishTitle:
                                                post['title']?.toString() ??
                                                'レシピ',
                                            targetIngredient: name,
                                            allIngredients: recipeIngredients,
                                            missingAppliances:
                                                missingAppliances,
                                            allergies: allergies,
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
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (postImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: PostImageCarousel(
                      imagesList: postImages,
                      keyPrefix: 'tl_$docId',
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
                        postOwnerUid: postUserId,
                        postSummary: postSummary,
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
                        postOwnerUid: postUserId,
                        postSummary: postSummary,
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
                        postOwnerUid: postUserId,
                        postSummary: postSummary,
                      ),
                    ),
                    _buildActionButton(
                      icon: Icons.auto_awesome_outlined,
                      color: Colors.teal,
                      count: 0,
                      onTap: () =>
                          _openPostInAiChat(docId, post, displayUserName),
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

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  Future _markAllAsRead(String uid) async {
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('targetUserId', isEqualTo: uid)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isRead'] != true) {
          batch.update(d.reference, {'isRead': true});
        }
      }
      await batch.commit();
    } catch (e) {}
  }

  String _formatTimestamp(dynamic rawTs) {
    if (rawTs is Timestamp) {
      final dt = rawTs.toDate();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$m/$d $hh:$mm';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => _markAllAsRead(uid),
            child: const Text('すべて既読'),
          ),
        ],
      ),
      body: uid.isEmpty
          ? const Center(child: Text('ログインすると通知が表示されます'))
          : StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('targetUserId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data == null) {
                  return const Center(child: Text('まだ通知はありません'));
                }

                final docs = List.from((snap.data as QuerySnapshot).docs);
                docs.sort((a, b) {
                  final da = (a as QueryDocumentSnapshot).data() as Map;
                  final db = (b as QueryDocumentSnapshot).data() as Map;
                  final ta = da['createdAt'] is Timestamp
                      ? (da['createdAt'] as Timestamp).millisecondsSinceEpoch
                      : 0;
                  final tb = db['createdAt'] is Timestamp
                      ? (db['createdAt'] as Timestamp).millisecondsSinceEpoch
                      : 0;
                  return tb.compareTo(ta);
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'まだ通知はありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final doc = docs[idx] as QueryDocumentSnapshot;
                        final data = doc.data() as Map;
                        final bool isRead = data['isRead'] == true;
                        final String type = (data['type'] ?? '').toString();
                        final String fromName = (data['fromUserName'] ?? 'ユーザー')
                            .toString();
                        final String summary = (data['postSummary'] ?? '')
                            .toString();
                        final String replyText = (data['replyText'] ?? '')
                            .toString();
                        final String postId = (data['postId'] ?? '').toString();
                        final String timeStr = _formatTimestamp(
                          data['createdAt'],
                        );

                        IconData leadingIcon = Icons.notifications;
                        Color iconColor = Colors.blue;
                        String message = '$fromName さんからアクションがありました';

                        if (type == 'like') {
                          leadingIcon = Icons.favorite;
                          iconColor = Colors.pink;
                          message = '$fromName さんがあなたの投稿にいいねしました';
                        } else if (type == 'helpful') {
                          leadingIcon = Icons.lightbulb;
                          iconColor = Colors.orange;
                          message = '$fromName さんがあなたの投稿を「参考になった」と評価しました';
                        } else if (type == 'reply') {
                          leadingIcon = Icons.chat_bubble;
                          iconColor = Colors.blue;
                          message = '$fromName さんがあなたの投稿に返信しました';
                        } else if (type == 'follow') {
                          leadingIcon = Icons.person_add;
                          iconColor = Colors.teal;
                          message = '$fromName さんにフォローされました';
                        }

                        return ListTile(
                          tileColor: isRead
                              ? Colors.white
                              : Colors.blue.shade50,
                          leading: CircleAvatar(
                            backgroundColor: iconColor.withValues(alpha: 0.12),
                            child: Icon(leadingIcon, color: iconColor),
                          ),
                          title: Text(
                            message,
                            style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (replyText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '「$replyText」',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              if (summary.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              if (timeStr.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            if (!isRead) {
                              doc.reference.update({'isRead': true});
                            }
                            if (postId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SnsDetailScreen(postId: postId),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class PostImageCarousel extends StatefulWidget {
  final List imagesList;
  final String keyPrefix;

  const PostImageCarousel({
    super.key,
    required this.imagesList,
    required this.keyPrefix,
  });

  @override
  State createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  List get _images => (widget as PostImageCarousel).imagesList;
  String get _prefix => (widget as PostImageCarousel).keyPrefix;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreenGallery(int initialIndex) {
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
                    title: _images.length > 1
                        ? Text(
                            '${currentFullIdx + 1} / ${_images.length}',
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
                          itemCount: _images.length,
                          onPageChanged: (idx) {
                            setModalState(() {
                              currentFullIdx = idx;
                            });
                          },
                          itemBuilder: (_, idx) {
                            final bytes = _images[idx] as Uint8List;
                            return InteractiveViewer(
                              panEnabled: true,
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: Center(
                                child: Image.memory(
                                  bytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_images.length > 1 && currentFullIdx > 0)
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
                      if (_images.length > 1 &&
                          currentFullIdx < _images.length - 1)
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
    if (_images.isEmpty) return const SizedBox.shrink();
    final int total = _images.length;
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
                      final bytes = _images[idx] as Uint8List;
                      return GestureDetector(
                        onTap: () => _openFullScreenGallery(idx),
                        child: Image.memory(
                          bytes,
                          key: ValueKey('${_prefix}_$idx'),
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
