import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/sns_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/sns_search_screen.dart';
import 'screens/sns_add_screen.dart';
import 'screens/sns_bookmark_screen.dart';
import 'screens/cooking_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 開発中は App Check をデバッグモードで動かす（AI相談室で使用）。
  // トークンはコードに書かず、実行時に --dart-define で渡す（GitHubに漏らさないため）
  if (kDebugMode) {
    const debugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');
    await FirebaseAppCheck.instance.activate(
      providerWeb: WebDebugProvider(
        debugToken: debugToken.isEmpty ? null : debugToken,
      ),
      providerAndroid: AndroidDebugProvider(
        debugToken: debugToken.isEmpty ? null : debugToken,
      ),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'アプリ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
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
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isSnsExpanded = false;
  bool _isSaExpanded = false;

  final List<Widget> _screens = [
    const SnsScreen(),
    const BudgetScreen(),
    const AiChatScreen(),
    const SnsSearchScreen(),
    const SnsAddScreen(),
    const SnsBookmarkScreen(),
    const CookingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'マイページ',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('プロフィール編集'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('設定'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('ログアウト', style: TextStyle(color: Colors.red)),
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
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
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
                          child: Icon(Icons.forum_outlined, size: 28, color: Colors.black87),
                        ),
                        SizedBox(
                          width: 160,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.search, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 3),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_box_outlined, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 4),
                              ),
                              IconButton(
                                icon: const Icon(Icons.bookmark_border, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 5),
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
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
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
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.auto_awesome, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 2),
                              ),
                              IconButton(
                                icon: const Icon(Icons.rice_bowl, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 6),
                              ),
                              IconButton(
                                icon: const Icon(Icons.home_outlined, color: Colors.black87),
                                onPressed: () => setState(() => _currentIndex = 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          width: 56,
                          child: Center(
                            child: Text(
                              'SA',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
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
  }
}
