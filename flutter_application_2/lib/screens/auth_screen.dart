import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  static const List availableInterestTags = [
    {'key': '料理:野菜', 'label': '🥬 料理：野菜'},
    {'key': '料理:肉類', 'label': '🍖 料理：肉類'},
    {'key': '料理:麺類', 'label': '🍜 料理：麺類'},
    {'key': '料理:作り置き', 'label': '🍱 料理：作り置き'},
    {'key': '料理:その他', 'label': '🍳 料理：その他'},
    {'key': '掃除:キッチン', 'label': '🧽 掃除：キッチン'},
    {'key': '掃除:お風呂', 'label': '🛁 掃除：お風呂'},
    {'key': '掃除:トイレ', 'label': '🚽 掃除：トイレ'},
    {'key': '掃除:リビング', 'label': '🧹 掃除：リビング'},
    {'key': '収納:クローゼット', 'label': '👕 収納：クローゼット'},
    {'key': '収納:デスク周り', 'label': '💻 収納：デスク周り'},
    {'key': '収納:小物', 'label': '📦 収納：小物'},
  ];

  static Future<DateTime?> showJapaneseBirthdayPicker(
    BuildContext context, {
    DateTime? initialDate,
  }) {
    final now = DateTime.now();
    final fallback = DateTime(now.year - 20, 1, 1);
    final base = initialDate ?? fallback;
    final clampedYear = base.year.clamp(1920, now.year);
    final maxMonth = clampedYear == now.year ? now.month : 12;
    final clampedMonth = base.month.clamp(1, maxMonth);
    final maxDay = (clampedYear == now.year && clampedMonth == now.month)
        ? now.day
        : DateTime(clampedYear, clampedMonth + 1, 0).day;
    final clampedDay = base.day.clamp(1, maxDay);

    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _JapaneseBirthdayPickerSheet(
        initialYear: clampedYear,
        initialMonth: clampedMonth,
        initialDay: clampedDay,
        maxDate: now,
      ),
    );
  }

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _JapaneseBirthdayPickerSheet extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final int initialDay;
  final DateTime maxDate;

  const _JapaneseBirthdayPickerSheet({
    required this.initialYear,
    required this.initialMonth,
    required this.initialDay,
    required this.maxDate,
  });

  @override
  State<_JapaneseBirthdayPickerSheet> createState() =>
      _JapaneseBirthdayPickerSheetState();
}

class _JapaneseBirthdayPickerSheetState
    extends State<_JapaneseBirthdayPickerSheet> {
  static const int _minYear = 1920;

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
    _selectedDay = widget.initialDay;

    _yearController = FixedExtentScrollController(
      initialItem: _selectedYear - _minYear,
    );
    _monthController = FixedExtentScrollController(
      initialItem: _selectedMonth - 1,
    );
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  int get _yearCount => widget.maxDate.year - _minYear + 1;

  int get _maxMonthForSelectedYear =>
      _selectedYear == widget.maxDate.year ? widget.maxDate.month : 12;

  int get _maxDayForSelectedYearMonth {
    final monthLastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    if (_selectedYear == widget.maxDate.year &&
        _selectedMonth == widget.maxDate.month) {
      return widget.maxDate.day < monthLastDay
          ? widget.maxDate.day
          : monthLastDay;
    }
    return monthLastDay;
  }

  void _clampMonthAndDay() {
    final maxMonth = _maxMonthForSelectedYear;
    if (_selectedMonth > maxMonth) {
      _selectedMonth = maxMonth;
      if (_monthController.hasClients) {
        _monthController.jumpToItem(_selectedMonth - 1);
      }
    }
    final maxDay = _maxDayForSelectedYearMonth;
    if (_selectedDay > maxDay) {
      _selectedDay = maxDay;
      if (_dayController.hasClients) {
        _dayController.jumpToItem(_selectedDay - 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMonth = _maxMonthForSelectedYear;
    final maxDay = _maxDayForSelectedYearMonth;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                Text(
                  '$_selectedYear年$_selectedMonth月$_selectedDay日',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      DateTime(_selectedYear, _selectedMonth, _selectedDay),
                    );
                  },
                  child: const Text(
                    '決定',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 220,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: CupertinoPicker(
                      scrollController: _yearController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedYear = _minYear + index;
                          _clampMonthAndDay();
                        });
                      },
                      children: List.generate(_yearCount, (index) {
                        final year = _minYear + index;
                        return Center(
                          child: Text(
                            '$year年',
                            style: const TextStyle(fontSize: 18),
                          ),
                        );
                      }),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: CupertinoPicker(
                      scrollController: _monthController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedMonth = index + 1;
                          _clampMonthAndDay();
                        });
                      },
                      children: List.generate(maxMonth, (index) {
                        return Center(
                          child: Text(
                            '${index + 1}月',
                            style: const TextStyle(fontSize: 18),
                          ),
                        );
                      }),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: CupertinoPicker(
                      scrollController: _dayController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedDay = index + 1;
                        });
                      },
                      children: List.generate(maxDay, (index) {
                        return Center(
                          child: Text(
                            '${index + 1}日',
                            style: const TextStyle(fontSize: 18),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  int _signUpStep = 1;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();

  DateTime? _selectedBirthday;
  Uint8List? _selectedIconBytes;
  String? _iconBase64;
  final List _selectedInterestTags = [];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _userNameController.dispose();
    super.dispose();
  }

  Future _pickIconImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 70,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        if (mounted) {
          setState(() {
            _selectedIconBytes = bytes;
            _iconBase64 = base64Encode(bytes);
          });
        }
      }
    } catch (e) {}
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('アルバムから選択'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickIconImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickIconImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future _pickBirthday() async {
    final picked = await AuthScreen.showJapaneseBirthdayPicker(
      context,
      initialDate: _selectedBirthday,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  String _formatBirthdayForDb(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}/$m/$d';
  }

  String _formatBirthdayForDisplay(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  Future _isUserNameTaken(String name) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('userName', isEqualTo: name)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future _proceedToStep2() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final userName = _userNameController.text.trim();

    if (userName.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('ユーザー名を入力してください')));
      return;
    }
    if (userName.length > 15) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ユーザー名は15文字以内で入力してください')),
      );
      return;
    }
    if (_selectedBirthday == null) {
      messenger.showSnackBar(const SnackBar(content: Text('生年月日を選択してください')));
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('正しいメールアドレスを入力してください')),
      );
      return;
    }
    if (password.length < 6) {
      messenger.showSnackBar(
        const SnackBar(content: Text('パスワードは6文字以上で入力してください')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final taken = await _isUserNameTaken(userName);
      if (!mounted) return;
      if (taken) {
        setState(() {
          _isLoading = false;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('このユーザー名は既に使われています。別の名前を入力してください。')),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _signUpStep = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('確認中にエラーが発生しました: $e')));
    }
  }

  Future _submitAuth() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final userName = _userNameController.text.trim();

    if (_isLogin) {
      if (email.isEmpty || password.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('メールアドレスとパスワードを入力してください')),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final taken = await _isUserNameTaken(userName);
        if (taken) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _signUpStep = 1;
          });
          messenger.showSnackBar(
            const SnackBar(content: Text('このユーザー名は既に使われています。別の名前を入力してください。')),
          );
          return;
        }

        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = cred.user;
        if (user != null) {
          await user.updateDisplayName(userName);
          final birthdayStr = _selectedBirthday != null
              ? _formatBirthdayForDb(_selectedBirthday!)
              : '';
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'userName': userName,
                'name': userName,
                'email': email,
                'birthday': birthdayStr,
                'iconBase64': _iconBase64 ?? '',
                'interestedTags': _selectedInterestTags,
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = '認証エラーが発生しました';
      if (e.code == 'email-already-in-use') {
        msg = 'このメールアドレスは既に登録されています';
      } else if (e.code == 'invalid-email') {
        msg = 'メールアドレスの形式が正しくありません';
      } else if (e.code == 'weak-password') {
        msg = 'パスワードは6文字以上にしてください';
      } else if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        msg = 'メールアドレスまたはパスワードが間違っています';
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSignUpStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '新規アカウント作成 (1/2)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          '基本プロフィールを入力してください',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        Center(
          child: GestureDetector(
            onTap: _showImageSourceSheet,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.blue.shade50,
                  backgroundImage: _selectedIconBytes != null
                      ? MemoryImage(_selectedIconBytes!)
                      : null,
                  child: _selectedIconBytes == null
                      ? const Icon(Icons.person, size: 44, color: Colors.blue)
                      : null,
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.blue,
                    child: Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _userNameController,
          maxLength: 15,
          decoration: const InputDecoration(
            labelText: 'ユーザー名（15文字以内・重複不可）',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickBirthday,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: '生年月日',
              prefixIcon: Icon(Icons.cake_outlined),
              suffixIcon: Icon(Icons.arrow_drop_down),
              border: OutlineInputBorder(),
            ),
            child: Text(
              _selectedBirthday != null
                  ? _formatBirthdayForDisplay(_selectedBirthday!)
                  : 'タップして生年月日を選択',
              style: TextStyle(
                color: _selectedBirthday != null
                    ? Colors.black87
                    : Colors.grey.shade600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'メールアドレス',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'パスワード（6文字以上）',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _proceedToStep2,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Text(
              '次へ（興味のあるタグ選択へ）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpStep2() {
    final bool hasSelected = _selectedInterestTags.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '興味のあるタグを選択（任意） (2/2)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '選んだタグの投稿が「おすすめ」に優先表示されます。\n選ばずに進むと、偏りのない通常のタイムラインで始められます。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.45),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: AuthScreen.availableInterestTags.map((rawTag) {
            final tagMap = rawTag as Map;
            final key = tagMap['key'].toString();
            final label = tagMap['label'].toString();
            final isSelected = _selectedInterestTags.contains(key);

            return FilterChip(
              label: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.blue.shade100,
              checkmarkColor: Colors.blue.shade900,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedInterestTags.add(key);
                  } else {
                    _selectedInterestTags.remove(key);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _signUpStep = 1;
                        });
                      },
                icon: const Icon(Icons.arrow_back),
                label: const Text('戻る'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        hasSelected ? 'アカウントを作成する' : 'スキップして作成する',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.person_pin, size: 64, color: Colors.blue),
        const SizedBox(height: 12),
        const Text(
          'ログイン',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'メールアドレス',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'パスワード',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitAuth,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'ログインする',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLogin)
                    _buildLoginView()
                  else if (_signUpStep == 1)
                    _buildSignUpStep1()
                  else
                    _buildSignUpStep2(),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _signUpStep = 1;
                            });
                          },
                    child: Text(
                      _isLogin
                          ? 'アカウントをお持ちでない方はこちら（新規登録）'
                          : 'すでにアカウントをお持ちの方はこちら（ログイン）',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
