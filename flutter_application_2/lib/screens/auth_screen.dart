import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State createState() => _AuthScreenState();
}

class _AuthScreenState extends State {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();

  DateTime? _selectedBirthday;
  File? _selectedIconFile;
  String? _iconBase64;

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
      if (picked != null) {
        final file = File(picked.path);
        final bytes = await file.readAsBytes();
        setState(() {
          _selectedIconFile = file;
          _iconBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {}
  }

  void _showIconSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'プロフィールアイコンを設定',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('カメラで撮影する'),
                onTap: () {
                  Navigator.pop(context);
                  _pickIconImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('アルバムから選択する'),
                onTap: () {
                  Navigator.pop(context);
                  _pickIconImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future _selectBirthday() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1940, 1, 1),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}年$m月$d日';
  }

  Future _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final userName = _userNameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('メールアドレスとパスワードを入力してください');
      return;
    }

    if (!_isLogin) {
      if (userName.isEmpty) {
        _showMessage('ユーザー名を入力してください');
        return;
      }
      if (_selectedBirthday == null) {
        _showMessage('生年月日を選択してください');
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        final uid = credential.user?.uid;
        if (uid != null) {
          await credential.user?.updateDisplayName(userName);
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'userName': userName,
            'email': email,
            'birthday': _selectedBirthday != null
                ? _formatDate(_selectedBirthday!)
                : '',
            'iconBase64': _iconBase64 ?? '',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      String msg = '認証エラーが発生しました';
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        msg = 'メールアドレスまたはパスワードが正しくありません';
      } else if (e.code == 'email-already-in-use') {
        msg = 'このメールアドレスは既に登録されています';
      } else if (e.code == 'weak-password') {
        msg = 'パスワードは6文字以上で入力してください';
      } else if (e.code == 'invalid-email') {
        msg = 'メールアドレスの形式が正しくありません';
      }
      _showMessage(msg);
    } catch (e) {
      _showMessage('通信エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
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
                      Text(
                        _isLogin ? 'ログイン' : '新規アカウント登録',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_isLogin) ...[
                        GestureDetector(
                          onTap: _showIconSourceSheet,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: Colors.blue.shade50,
                                backgroundImage: _selectedIconFile != null
                                    ? FileImage(_selectedIconFile!)
                                    : null,
                                child: _selectedIconFile == null
                                    ? const Icon(
                                        Icons.person_outline,
                                        size: 44,
                                        color: Colors.blue,
                                      )
                                    : null,
                              ),
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: Colors.blue,
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'タップしてアイコンを設定',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _userNameController,
                          decoration: InputDecoration(
                            labelText: 'ユーザー名',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _selectBirthday,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '生年月日',
                              prefixIcon: const Icon(Icons.cake_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _selectedBirthday != null
                                  ? _formatDate(_selectedBirthday!)
                                  : 'タップして生年月日を選択',
                              style: TextStyle(
                                color: _selectedBirthday != null
                                    ? Colors.black87
                                    : Colors.grey.shade600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'メールアドレス',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'パスワード（6文字以上）',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isLogin ? 'ログインする' : 'アカウントを作成する',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin = !_isLogin;
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
        ),
      ),
    );
  }
}
