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
import 'screens/sns_add_screen.dart';
import 'screens/sns_bookmark_screen.dart';
import 'screens/cooking_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'アプリ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State createState() => _MainScreenState();
}

class _MainScreenState extends State {
  int _currentIndex = 0;
  bool _isSnsExpanded = false;
  bool _isSaExpanded = false;

  final List _screens = const [
    SnsScreen(),
    BudgetScreen(),
    AiChatScreen(),
    SnsSearchScreen(),
    SnsAddScreen(),
    SnsBookmarkScreen(),
    CookingScreen(),
  ];

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
        final birthday = userData['birthday']?.toString() ?? '';
        final iconBytes = _decodeIcon(userData['iconBase64']?.toString());

        return Scaffold(
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: Colors.blue),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            backgroundImage: iconBytes != null
                                ? MemoryImage(iconBytes)
                                : null,
                            child: iconBytes == null
                                ? const Icon(
                                    Icons.person,
                                    size: 34,
                                    color: Colors.blue,
                                  )
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
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (birthday.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '生年月日: $birthday',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('アカウント・プロフィール編集'),
                  subtitle: const Text('名前（15文字以内）・アイコン・興味タグ'),
                  trailing: const Icon(Icons.chevron_right),
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
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('地域・調理家電の設定'),
                  subtitle: const Text('お住まいの地域・持っていない家電'),
                  trailing: const Icon(Icons.chevron_right),
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
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'ログアウト',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              _screens[_currentIndex],
              Positioned(
                left: 16,
                bottom: 30,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentIndex = 0;
                      _isSnsExpanded = !_isSnsExpanded;
                      if (_isSnsExpanded) _isSaExpanded = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuart,
                    height: 60,
                    width: _isSnsExpanded ? 220 : 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.black87, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: 220,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const SizedBox(
                              width: 56,
                              child: Icon(
                                Icons.forum_outlined,
                                size: 28,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(
                              width: 160,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.search,
                                      color: Colors.black87,
                                    ),
                                    onPressed: () =>
                                        setState(() => _currentIndex = 3),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_box_outlined,
                                      color: Colors.black87,
                                    ),
                                    onPressed: () =>
                                        setState(() => _currentIndex = 4),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.bookmark_border,
                                      color: Colors.black87,
                                    ),
                                    onPressed: () =>
                                        setState(() => _currentIndex = 5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 30,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSaExpanded = !_isSaExpanded;
                      if (_isSaExpanded) _isSnsExpanded = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuart,
                    height: 60,
                    width: _isSaExpanded ? 220 : 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.black87, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: 220,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isSaExpanded)
                              SizedBox(
                                width: 160,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.auto_awesome,
                                        color: Colors.black87,
                                      ),
                                      onPressed: () =>
                                          setState(() => _currentIndex = 2),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.restaurant_menu,
                                        color: Colors.black87,
                                      ),
                                      onPressed: () =>
                                          setState(() => _currentIndex = 6),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.account_balance_wallet_outlined,
                                        color: Colors.black87,
                                      ),
                                      onPressed: () =>
                                          setState(() => _currentIndex = 1),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(
                              width: 56,
                              child: Center(
                                child: Text(
                                  'SA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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