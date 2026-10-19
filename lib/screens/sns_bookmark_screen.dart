import 'package:flutter/material.dart';

class SnsBookmarkScreen extends StatelessWidget {
  const SnsBookmarkScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('保存済み')),
      body: const Center(child: Text('保存済み画面')),
    );
  }
}