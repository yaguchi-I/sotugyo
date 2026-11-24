import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import 'ai_chat_screen.dart' show AiChatScreen;
import 'sns_detail_screen.dart' show SnsDetailScreen;
import '../widgets/top_toast.dart' show showTopToast;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String _currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _customAllergyController =
      TextEditingController();
  final TextEditingController _incomeController = TextEditingController();
  final TextEditingController _paydayController = TextEditingController();

  static const List<String> _cookingAppliances = [
    '電子レンジ',
    'オーブン',
    '炊飯器',
    'トースター',
    'コンロ(2口以上)',
    'ミキサー',
    '冷蔵庫',
  ];

  final List<String> _missingAppliances = [];
  final List<String> _allergies = [];
  final List<String> _blockedUsers = [];
  final List<String> _lessInterestedTopics = [];
  final List<String> _followingUsers = [];

  String _iconBase64 = '';
  Uint8List? _iconBytes;
  bool _isLoading = true;
  bool _isSaving = false;

  late final Stream<QuerySnapshot>? _myPostsStream = _currentUserId.isNotEmpty
      ? FirebaseFirestore.instance
            .collection('posts')
            .where('userId', isEqualTo: _currentUserId)
            .snapshots()
      : null;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _customAllergyController.dispose();
    _incomeController.dispose();
    _paydayController.dispose();
    super.dispose();
  }

  Uint8List? _decodeBase64(String raw) {
    if (raw.trim().isEmpty) return null;
    final cleaned = raw.contains(',')
        ? raw.split(',').last.replaceAll(RegExp(r'\s+'), '')
        : raw.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    try {
      final decoded = base64Decode(cleaned);
      return decoded.isEmpty ? null : decoded;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadProfile() async {
    if (_currentUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();

      final user = FirebaseAuth.instance.currentUser;
      String name = user?.displayName?.trim() ?? '';
      if (name.isEmpty && _currentEmail.isNotEmpty) {
        name = _currentEmail.split('@').first;
      }

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['userName'] != null &&
            data['userName'].toString().trim().isNotEmpty) {
          name = data['userName'].toString().trim();
        }
        final String area = (data['area'] ?? '').toString().trim();
        final String iconStr = (data['iconBase64'] ?? '').toString();
        final int income = data['monthlyIncome'] is num
            ? (data['monthlyIncome'] as num).toInt()
            : (int.tryParse(data['monthlyIncome']?.toString() ?? '0') ?? 0);
        final int payday = data['payday'] is num
            ? (data['payday'] as num).toInt()
            : (int.tryParse(data['payday']?.toString() ?? '25') ?? 25);

        final List<String> missing = data['missingAppliances'] is List
            ? List.from(data['missingAppliances'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [];
        final List<String> allergies = data['allergies'] is List
            ? List.from(data['allergies'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [];
        final List<String> blocked = data['blockedUsers'] is List
            ? List.from(data['blockedUsers'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [];
        final List<String> demoted = data['lessInterestedTopics'] is List
            ? List.from(data['lessInterestedTopics'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [];
        final List<String> following = data['following'] is List
            ? List.from(data['following'])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [];

        if (!mounted) return;
        setState(() {
          _nameController.text = name;
          _areaController.text = area;
          _incomeController.text = income > 0 ? income.toString() : '';
          _paydayController.text = payday.toString();
          _iconBase64 = iconStr;
          _iconBytes = _decodeBase64(iconStr);
          _missingAppliances
            ..clear()
            ..addAll(missing);
          _allergies
            ..clear()
            ..addAll(allergies);
          _blockedUsers
            ..clear()
            ..addAll(blocked);
          _lessInterestedTopics
            ..clear()
            ..addAll(demoted);
          _followingUsers
            ..clear()
            ..addAll(following);
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _nameController.text = name;
          _paydayController.text = '25';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickProfileIcon() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _iconBytes = bytes;
        _iconBase64 = base64Encode(bytes);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('画像の読み込みに失敗しました: $e')));
      }
    }
  }

  void _addCustomAllergy() {
    final raw = _customAllergyController.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(RegExp(r'[\s 、,・/]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    setState(() {
      for (final p in parts) {
        if (!_allergies.contains(p)) {
          _allergies.add(p);
        }
      }
      _customAllergyController.clear();
    });
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _currentUserId.isEmpty) return;

    if (_customAllergyController.text.trim().isNotEmpty) {
      _addCustomAllergy();
    }

    final userName = _nameController.text.trim();
    final area = _areaController.text.trim();
    final income =
        int.tryParse(_incomeController.text.replaceAll(',', '').trim()) ?? 0;
    final parsedPayday = int.tryParse(_paydayController.text.trim()) ?? 25;
    final payday = parsedPayday < 1
        ? 1
        : (parsedPayday > 31 ? 31 : parsedPayday);

    setState(() {
      _isSaving = true;
    });

    try {
      final Map<String, dynamic> payload = {
        'userName': userName.isNotEmpty ? userName : 'ユーザー',
        'iconBase64': _iconBase64,
        'area': area,
        'missingAppliances': _missingAppliances,
        'allergies': _allergies,
        'monthlyIncome': income,
        'payday': payday,
        'isAiSetupDone': area.isNotEmpty,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set(payload, SetOptions(merge: true));

      if (userName.isNotEmpty) {
        try {
          await FirebaseAuth.instance.currentUser?.updateDisplayName(userName);
        } catch (e) {}
      }

      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      showTopToast(context, 'プロフィールとアレルギー設定を保存しました');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    }
  }

  Future<void> _unblockUser(String userKey) async {
    if (_currentUserId.isEmpty) return;
    setState(() {
      _blockedUsers.remove(userKey);
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'blockedUsers': FieldValue.arrayRemove([userKey]),
          }, SetOptions(merge: true));
      if (mounted) {
        showTopToast(context, 'ブロックを解除しました');
      }
    } catch (e) {}
  }

  Future<void> _restoreTopic(String topicKey) async {
    if (_currentUserId.isEmpty) return;
    setState(() {
      _lessInterestedTopics.remove(topicKey);
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
            'lessInterestedTopics': FieldValue.arrayRemove([topicKey]),
          }, SetOptions(merge: true));
      if (mounted) {
        showTopToast(context, '「$topicKey」の表示制限を解除しました');
      }
    } catch (e) {}
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしてもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    final List<String> customAllergies = _allergies
        .where((a) => !AiChatScreen.presetAllergens.contains(a))
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        title: const Text(
          'マイページ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!_isLoading && _currentUserId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text(
                  '保存',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUserId.isEmpty
          ? const Center(child: Text('ログインするとマイページを編集できます'))
          : StreamBuilder<QuerySnapshot>(
              stream: _myPostsStream,
              builder: (context, postsSnap) {
                final List<QueryDocumentSnapshot> myPosts = [];
                int totalLikes = 0;
                int totalHelpfuls = 0;

                if (postsSnap.hasData && postsSnap.data != null) {
                  for (final doc in postsSnap.data!.docs) {
                    final data = doc.data() as Map;
                    if (data['mainCategory'] == 'AI') continue;
                    myPosts.add(doc);
                    final likes = data['likes'] is num
                        ? (data['likes'] as num).toInt()
                        : (data['likedUsers'] is List
                              ? (data['likedUsers'] as List).length
                              : 0);
                    final helpfuls = data['helpfuls'] is num
                        ? (data['helpfuls'] as num).toInt()
                        : (data['helpfulUsers'] is List
                              ? (data['helpfulUsers'] as List).length
                              : 0);
                    totalLikes += likes;
                    totalHelpfuls += helpfuls;
                  }
                  myPosts.sort((a, b) {
                    final da = a.data() as Map;
                    final db = b.data() as Map;
                    final ta = da['createdAt'] as Timestamp?;
                    final tb = db['createdAt'] as Timestamp?;
                    if (ta == null && tb == null) return 0;
                    if (ta == null) return 1;
                    if (tb == null) return -1;
                    return tb.compareTo(ta);
                  });
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _pickProfileIcon,
                                      child: Stack(
                                        alignment: Alignment.bottomRight,
                                        children: [
                                          CircleAvatar(
                                            radius: 34,
                                            backgroundColor:
                                                Colors.blue.shade100,
                                            backgroundImage: _iconBytes != null
                                                ? MemoryImage(_iconBytes!)
                                                : null,
                                            child: _iconBytes == null
                                                ? const Icon(
                                                    Icons.person,
                                                    size: 34,
                                                    color: Colors.blue,
                                                  )
                                                : null,
                                          ),
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          TextField(
                                            controller: _nameController,
                                            decoration: const InputDecoration(
                                              labelText: '表示名',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          if (_currentEmail.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              _currentEmail,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    _buildStatItem(
                                      '投稿',
                                      myPosts.length.toString(),
                                    ),
                                    _buildStatItem(
                                      'フォロー中',
                                      _followingUsers.length.toString(),
                                    ),
                                    _buildStatItem(
                                      'いいね獲得',
                                      totalLikes.toString(),
                                    ),
                                    _buildStatItem(
                                      '参考獲得',
                                      totalHelpfuls.toString(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _buildSectionCard(
                            icon: Icons.no_food_outlined,
                            iconColor: Colors.redAccent,
                            title: 'アレルギー・食べられない食材',
                            subtitle:
                                'ここで設定した食材は、AI相談・自炊レシピ提案・検索のすべてで自動除外・注意表示されます。',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final rawAllergen
                                        in AiChatScreen.presetAllergens)
                                      FilterChip(
                                        label: Text(rawAllergen.toString()),
                                        selected: _allergies.contains(
                                          rawAllergen.toString(),
                                        ),
                                        selectedColor: Colors.red.shade100,
                                        checkmarkColor: Colors.red.shade800,
                                        onSelected: (selected) {
                                          final a = rawAllergen.toString();
                                          setState(() {
                                            if (selected) {
                                              if (!_allergies.contains(a)) {
                                                _allergies.add(a);
                                              }
                                            } else {
                                              _allergies.remove(a);
                                            }
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _customAllergyController,
                                        decoration: const InputDecoration(
                                          hintText: 'その他の食材を追加（例：大豆、ごま、さば）',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) => _addCustomAllergy(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _addCustomAllergy,
                                      icon: const Icon(Icons.add, size: 17),
                                      label: const Text('追加'),
                                    ),
                                  ],
                                ),
                                if (customAllergies.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final item in customAllergies)
                                        InputChip(
                                          label: Text(
                                            item,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                          backgroundColor: Colors.red.shade50,
                                          deleteIconColor: Colors.red.shade700,
                                          onDeleted: () {
                                            setState(() {
                                              _allergies.remove(item);
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _buildSectionCard(
                            icon: Icons.kitchen_outlined,
                            iconColor: Colors.orange,
                            title: '住まい・調理環境の設定',
                            subtitle: 'AIのレシピ提案や暮らしアドバイスに自動で反映されます。',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _areaController,
                                  decoration: const InputDecoration(
                                    labelText: 'お住まいの地域（都道府県など）',
                                    hintText: '例：長野県、東京都など',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  '家に「ない」調理家電（チェックした家電を使わない提案になります）',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final app in _cookingAppliances)
                                      FilterChip(
                                        label: Text(app),
                                        selected: _missingAppliances.contains(
                                          app,
                                        ),
                                        selectedColor: Colors.orange.shade100,
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              if (!_missingAppliances.contains(
                                                app,
                                              )) {
                                                _missingAppliances.add(app);
                                              }
                                            } else {
                                              _missingAppliances.remove(app);
                                            }
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _buildSectionCard(
                            icon: Icons.payments_outlined,
                            iconColor: Colors.green,
                            title: '家計簿の基本設定',
                            subtitle: '家計簿の貯蓄ノート・AI家計診断と連動します。',
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _incomeController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '毎月の収入 (円)',
                                      prefixText: '¥ ',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _paydayController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '給料日 (日)',
                                      suffixText: '日',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveProfile,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text(
                                '設定を保存する',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_lessInterestedTopics.isNotEmpty ||
                              _blockedUsers.isNotEmpty)
                            _buildSectionCard(
                              icon: Icons.tune,
                              iconColor: Colors.blueGrey,
                              title: 'タイムライン表示・ブロック管理',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_lessInterestedTopics.isNotEmpty) ...[
                                    const Text(
                                      '表示を減らしている話題（×で解除）',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final topic
                                            in _lessInterestedTopics)
                                          InputChip(
                                            label: Text(
                                              topic,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            onDeleted: () =>
                                                _restoreTopic(topic),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_blockedUsers.isNotEmpty) ...[
                                    const Text(
                                      'ブロック中のユーザー（×で解除）',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final uKey in _blockedUsers)
                                          InputChip(
                                            label: Text(
                                              uKey.length > 12
                                                  ? '${uKey.substring(0, 12)}...'
                                                  : uKey,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            onDeleted: () => _unblockUser(uKey),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          _buildSectionCard(
                            icon: Icons.article_outlined,
                            iconColor: Colors.blue,
                            title: '自分の投稿 (${myPosts.length}件)',
                            child: myPosts.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: Text(
                                        'まだ投稿がありません',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      for (final doc in myPosts.take(10))
                                        Builder(
                                          builder: (_) {
                                            final data = doc.data() as Map;
                                            final title = (data['title'] ?? '')
                                                .toString()
                                                .trim();
                                            final content =
                                                (data['content'] ?? '')
                                                    .toString()
                                                    .trim();
                                            final mainCat =
                                                (data['mainCategory'] ?? '')
                                                    .toString();
                                            final likes = data['likes'] is num
                                                ? (data['likes'] as num).toInt()
                                                : (data['likedUsers'] is List
                                                      ? (data['likedUsers']
                                                                as List)
                                                            .length
                                                      : 0);
                                            final helpfuls =
                                                data['helpfuls'] is num
                                                ? (data['helpfuls'] as num)
                                                      .toInt()
                                                : (data['helpfulUsers'] is List
                                                      ? (data['helpfulUsers']
                                                                as List)
                                                            .length
                                                      : 0);

                                            return ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              dense: true,
                                              title: Text(
                                                title.isNotEmpty
                                                    ? title
                                                    : (content.isNotEmpty
                                                          ? content
                                                          : '（画像投稿）'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '${mainCat.isNotEmpty && mainCat != '指定なし' ? '$mainCat  ' : ''}♥$likes  💡$helpfuls',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              trailing: const Icon(
                                                Icons.chevron_right,
                                              ),
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
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _confirmSignOut,
                              icon: const Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                              ),
                              label: const Text(
                                'ログアウト',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.redAccent),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
