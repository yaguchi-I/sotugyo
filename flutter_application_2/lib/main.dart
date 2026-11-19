import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/sns_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/sns_search_screen.dart';
import 'screens/sns_bookmark_screen.dart';
import 'screens/cooking_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

/// アプリ全体の配色。ここを変えるだけで全画面のテーマ色が変わる
const Color kBrandColor = Color(0xFF2F80ED);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: kBrandColor);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ソロナンデス',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const MainScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}

/// 画面1つ分の情報（アイコン・名前・説明）
class _AppPage {
  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String description;

  const _AppPage({
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.description,
  });
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ---- 画面の番号（_pages の並び順と一致させる） ----
  // ※投稿画面はタブではなく、タイムラインの右下ボタンから開く
  static const int _home = 0;
  static const int _search = 1;
  static const int _budget = 2;
  static const int _ai = 3;
  static const int _bookmark = 4;
  static const int _cooking = 5;

  static const List<_AppPage> _pages = [
    _AppPage(
      screen: SnsScreen(),
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'ホーム',
      description: 'みんなの節約術・裏技を見る',
    ),
    _AppPage(
      screen: SnsSearchScreen(),
      icon: Icons.search,
      selectedIcon: Icons.search,
      label: 'さがす',
      description: 'キーワードやタグで投稿を探す',
    ),
    _AppPage(
      screen: BudgetScreen(),
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: '家計簿',
      description: '家計簿・支出の管理',
    ),
    _AppPage(
      screen: AiChatScreen(),
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: 'AI相談',
      description: '暮らしの悩みをAIに相談',
    ),
    _AppPage(
      screen: SnsBookmarkScreen(),
      icon: Icons.bookmark_border,
      selectedIcon: Icons.bookmark,
      label: '保存',
      description: '保存した投稿・フォルダ',
    ),
    _AppPage(
      screen: CookingScreen(),
      icon: Icons.restaurant_menu_outlined,
      selectedIcon: Icons.restaurant_menu,
      label: 'AI自炊',
      description: 'AIが冷蔵庫の中身からレシピ提案',
    ),
  ];

  /// 下のバーに常に出すタブ（ここに番号を足せばタブが増える）
  static const List<int> _tabIndexes = [
    _home,
    _search,
    _budget,
    _cooking,
    _ai,
  ];

  int _currentIndex = _home;

  /// 一度開いた画面だけ作る（起動時に全画面の通信が走らないように）
  final Set<int> _loadedIndexes = {_home};

  void _goTo(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _loadedIndexes.add(index);
    });
  }

  Uint8List? _decodeIcon(String? base64String) {
    if (base64String == null || base64String.trim().isEmpty) return null;
    try {
      final cleaned = base64String.contains(',')
          ? base64String.split(',').last.replaceAll(RegExp(r'\s+'), '')
          : base64String.replaceAll(RegExp(r'\s+'), '');
      if (cleaned.isEmpty) return null;
      return base64Decode(cleaned);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid ?? '';

    return StreamBuilder(
      stream: uid.isNotEmpty
          ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
          : null,
      builder: (context, snapshot) {
        Map userData = {};
        if (snapshot.hasData && snapshot.data != null) {
          final doc = snapshot.data as DocumentSnapshot;
          if (doc.exists && doc.data() != null) {
            userData = Map.from(doc.data() as Map);
          }
        }

        final userName = userData['userName']?.toString().isNotEmpty == true
            ? userData['userName'].toString()
            : (currentUser?.displayName ?? 'マイページ');
        final email = currentUser?.email ?? '';
        final iconBytes = _decodeIcon(userData['iconBase64']?.toString());

        // Androidの戻るボタン：ホーム以外ならホームへ戻す
        return PopScope(
          canPop: _currentIndex == _home,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _goTo(_home);
          },
          child: Scaffold(
            drawer: _buildDrawer(
              userName: userName,
              email: email,
              iconBytes: iconBytes,
              userData: userData,
            ),
            body: IndexedStack(
              index: _currentIndex,
              children: [
                for (int i = 0; i < _pages.length; i++)
                  _loadedIndexes.contains(i)
                      ? _pages[i].screen
                      : const SizedBox.shrink(),
              ],
            ),
            bottomNavigationBar: _buildBottomBar(context),
          ),
        );
      },
    );
  }

  // ===================== 下のタブバー =====================

  Widget _buildBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final index in _tabIndexes)
                Expanded(child: _buildTabItem(index, scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, ColorScheme scheme) {
    final page = _pages[index];
    final selected = _currentIndex == index;
    final color = selected ? scheme.primary : Colors.grey.shade600;

    return Semantics(
      selected: selected,
      button: true,
      label: page.label,
      child: InkWell(
        onTap: () => _goTo(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? page.selectedIcon : page.icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              page.label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== 左メニュー（ドロワー） =====================

  Widget _buildDrawer({
    required String userName,
    required String email,
    required Uint8List? iconBytes,
    required Map userData,
  }) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ---- プロフィール（タップで編集） ----
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AccountEditScreen(initialUserData: userData),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 12, 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.blue.shade50,
                      backgroundImage:
                          iconBytes != null ? MemoryImage(iconBytes) : null,
                      child: iconBytes == null
                          ? const Icon(Icons.person,
                              size: 30, color: kBrandColor)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'プロフィールを編集 ›',
                            style: TextStyle(
                              fontSize: 12,
                              color: kBrandColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // ---- 全機能の一覧（説明つき） ----
            _drawerSectionTitle('みんなとつながる'),
            _drawerPageTile(_home),
            _drawerPageTile(_search),
            _drawerPageTile(_bookmark),

            _drawerSectionTitle('じぶんの暮らし'),
            _drawerPageTile(_budget),
            _drawerPageTile(_ai),
            _drawerPageTile(_cooking),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('地域・調理家電の設定'),
              subtitle: const Text('お住まいの地域・持っていない家電'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AppSettingsScreen(initialUserData: userData),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'ログアウト',
                style: TextStyle(color: Colors.red),
              ),
              onTap: _confirmLogout,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _drawerPageTile(int index) {
    final page = _pages[index];
    final selected = _currentIndex == index;

    return ListTile(
      selected: selected,
      selectedTileColor: Colors.blue.shade50,
      leading: Icon(selected ? page.selectedIcon : page.icon),
      title: Text(page.label),
      subtitle: Text(page.description, style: const TextStyle(fontSize: 12)),
      onTap: () {
        Navigator.pop(context);
        _goTo(index);
      },
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (mounted) Navigator.pop(context); // ドロワーを閉じる
      await FirebaseAuth.instance.signOut();
    }
  }
}

class AccountEditScreen extends StatefulWidget {
  final Map initialUserData;

  const AccountEditScreen({super.key, required this.initialUserData});

  @override
  State createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late TextEditingController _nameController;
  String _birthdayStr = '';
  String _iconBase64 = '';
  Uint8List? _previewIconBytes;
  final List _selectedTags = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initName = widget.initialUserData['userName']?.toString() ??
        FirebaseAuth.instance.currentUser?.displayName ??
        '';
    _nameController = TextEditingController(text: initName);
    _birthdayStr = widget.initialUserData['birthday']?.toString() ?? '';
    _iconBase64 = widget.initialUserData['iconBase64']?.toString() ?? '';
    _previewIconBytes = _decodeIcon(_iconBase64);
    if (widget.initialUserData['interestedTags'] != null) {
      _selectedTags.addAll(
        List.from(widget.initialUserData['interestedTags']),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Uint8List? _decodeIcon(String base64Str) {
    if (base64Str.trim().isEmpty) return null;
    try {
      final cleaned = base64Str.contains(',')
          ? base64Str.split(',').last.replaceAll(RegExp(r'\s+'), '')
          : base64Str.replaceAll(RegExp(r'\s+'), '');
      if (cleaned.isEmpty) return null;
      return base64Decode(cleaned);
    } catch (e) {
      return null;
    }
  }

  Future _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (mounted) {
          setState(() {
            _previewIconBytes = bytes;
            _iconBase64 = base64Encode(bytes);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  Future _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (picked != null && mounted) {
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() {
        _birthdayStr = '${picked.year}/$m/$d';
      });
    }
  }

  Future _saveAccountChanges() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final newName = _nameController.text.trim();

    if (newName.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ユーザー名を入力してください')),
      );
      return;
    }
    if (newName.length > 15) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ユーザー名は15文字以内で入力してください')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('userName', isEqualTo: newName)
          .get();

      final isDuplicate = snap.docs.any((doc) => doc.id != _uid);
      if (isDuplicate) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('このユーザー名は既に使われています。別の名前を入力してください。'),
          ),
        );
        return;
      }

      if (_uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set({
          'userName': newName,
          'name': newName,
          'birthday': _birthdayStr,
          'iconBase64': _iconBase64,
          'interestedTags': _selectedTags,
        }, SetOptions(merge: true));

        await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('アカウント情報を更新しました！')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('更新に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'アカウント・プロフィール編集',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: Colors.blue.shade50,
                    backgroundImage: _previewIconBytes != null
                        ? MemoryImage(_previewIconBytes!)
                        : null,
                    child: _previewIconBytes == null
                        ? const Icon(Icons.person, size: 52, color: Colors.blue)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: const Text('アルバム'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('カメラ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'ユーザー名（15文字以内・重複不可）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              maxLength: 15,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '15文字以内で入力',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '生年月日',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickBirthday,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                child: Text(
                  _birthdayStr.isNotEmpty ? _birthdayStr : 'タップして選択',
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '興味のあるタグ（「おすすめ」タイムラインに優先表示）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AuthScreen.availableInterestTags.map((rawTag) {
                final tagMap = rawTag as Map;
                final key = tagMap['key'].toString();
                final label = tagMap['label'].toString();
                final isSelected = _selectedTags.contains(key);

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: Colors.blue.shade100,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(key);
                      } else {
                        _selectedTags.remove(key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveAccountChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '変更を保存する',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSettingsScreen extends StatefulWidget {
  final Map initialUserData;

  const AppSettingsScreen({super.key, required this.initialUserData});

  @override
  State createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late TextEditingController _areaController;
  final List _missingAppliances = [];
  bool _isSaving = false;

  final List _allAppliances = [
    '電子レンジ',
    'オーブン',
    '炊飯器',
    'トースター',
    'コンロ(2口以上)',
    'ミキサー',
    '冷蔵庫',
  ];

  @override
  void initState() {
    super.initState();
    _areaController = TextEditingController(
      text: widget.initialUserData['area']?.toString() ?? '',
    );
    if (widget.initialUserData['missingAppliances'] != null) {
      _missingAppliances.addAll(
        List.from(widget.initialUserData['missingAppliances']),
      );
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  Future _saveSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
    });

    try {
      if (_uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set({
          'area': _areaController.text.trim(),
          'missingAppliances': _missingAppliances,
          'isAiSetupDone': true,
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('設定を保存しました！')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '地域・調理家電の設定',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'お住まいの地域（都道府県など）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例：長野県、東京都など',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '家に「ない」調理家電',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allAppliances.map((rawApp) {
                final app = rawApp.toString();
                final isSelected = _missingAppliances.contains(app);
                return FilterChip(
                  label: Text(app),
                  selected: isSelected,
                  selectedColor: Colors.orange.shade100,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _missingAppliances.add(app);
                      } else {
                        _missingAppliances.remove(app);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  '設定を保存する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}