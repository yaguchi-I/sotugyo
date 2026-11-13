import 'dart:convert';
import 'dart:io';
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
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
  }

  Future _showEditProfileDialog(Map userData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController(
      text: userData['userName']?.toString() ?? '',
    );
    String birthdayText = userData['birthday']?.toString() ?? '';
    String currentIconBase64 = userData['iconBase64']?.toString() ?? '';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setDialogState) {
            final iconBytes = _decodeIcon(currentIconBase64);

            Future pickNewIcon(ImageSource source) async {
              try {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: source,
                  maxWidth: 300,
                  maxHeight: 300,
                  imageQuality: 70,
                );
                if (picked != null) {
                  final bytes = await File(picked.path).readAsBytes();
                  setDialogState(() {
                    currentIconBase64 = base64Encode(bytes);
                  });
                }
              } catch (e) {}
            }

            Future pickBirthday() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: stateContext,
                initialDate: DateTime(now.year - 20, 1, 1),
                firstDate: DateTime(1940, 1, 1),
                lastDate: now,
              );
              if (picked != null) {
                final m = picked.month.toString().padLeft(2, '0');
                final d = picked.day.toString().padLeft(2, '0');
                setDialogState(() {
                  birthdayText = '${picked.year}年$m月$d日';
                });
              }
            }

            return AlertDialog(
              title: const Text('プロフィール編集'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: stateContext,
                          builder: (sheetContext) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text('カメラで撮影'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    pickNewIcon(ImageSource.camera);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library),
                                  title: const Text('アルバムから選択'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    pickNewIcon(ImageSource.gallery);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.blue.shade50,
                            backgroundImage: iconBytes != null
                                ? MemoryImage(iconBytes)
                                : null,
                            child: iconBytes == null
                                ? const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Colors.blue,
                                  )
                                : null,
                          ),
                          const CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.blue,
                            child: Icon(
                              Icons.camera_alt,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ユーザー名',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: pickBirthday,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '生年月日',
                          prefixIcon: Icon(Icons.cake_outlined),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          birthdayText.isNotEmpty ? birthdayText : '生年月日を選択',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    if (newName.isEmpty) return;

                    Navigator.pop(dialogContext);

                    await FirebaseAuth.instance.currentUser?.updateDisplayName(
                      newName,
                    );
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({
                          'userName': newName,
                          'birthday': birthdayText,
                          'iconBase64': currentIconBase64,
                        }, SetOptions(merge: true));

                    messenger.showSnackBar(
                      const SnackBar(content: Text('プロフィールを更新しました')),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future _showSettingsDialog(Map userData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (uid.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final areaController = TextEditingController(
      text: userData['area']?.toString() ?? '',
    );
    final List appliances = [
      '電子レンジ',
      'オーブン',
      '炊飯器',
      'トースター',
      'コンロ(2口以上)',
      'ミキサー',
      '冷蔵庫',
    ];
    final List selectedMissing = List.from(userData['missingAppliances'] ?? []);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setDialogState) {
            return AlertDialog(
              title: const Text('設定'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'お住まいの地域',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: areaController,
                      decoration: const InputDecoration(
                        hintText: '例: 長野県、山梨県、東京都',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '持っていない調理家電',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 6.0,
                      children: appliances.map((item) {
                        final name = item.toString();
                        final isSelected = selectedMissing.contains(name);
                        return FilterChip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: isSelected,
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) {
                                selectedMissing.add(name);
                              } else {
                                selectedMissing.remove(name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (email.isNotEmpty) ...[
                      const Divider(height: 28),
                      const Text(
                        'アカウントセキュリティ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(
                              email: email,
                            );
                            messenger.showSnackBar(
                              SnackBar(content: Text('$email 宛に再設定メールを送信しました')),
                            );
                          } catch (e) {}
                        },
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('パスワード再設定メールを送る'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newArea = areaController.text.trim();
                    Navigator.pop(dialogContext);

                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({
                          'area': newArea,
                          'missingAppliances': selectedMissing,
                          'aiSetupComplete': true,
                        }, SetOptions(merge: true));

                    messenger.showSnackBar(
                      const SnackBar(content: Text('設定を保存しました')),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
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
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
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
                  leading: const Icon(Icons.person),
                  title: const Text('プロフィール編集'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditProfileDialog(userData);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('設定'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSettingsDialog(userData);
                  },
                ),
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
                      reverse: true,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: 220,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
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
                                      Icons.rice_bowl,
                                      color: Colors.black87,
                                    ),
                                    onPressed: () =>
                                        setState(() => _currentIndex = 6),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.home_outlined,
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
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
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
