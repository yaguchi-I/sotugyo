import 'package:flutter/material.dart';

class SnsAddScreen extends StatelessWidget {
  const SnsAddScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新規登録')),
      body: const Center(child: Text('新規登録画面')),
    );
  }
}