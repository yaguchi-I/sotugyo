import 'package:flutter/material.dart';

class SnsSearchScreen extends StatelessWidget {
  const SnsSearchScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('検索')),
      body: const Center(child: Text('検索画面')),
    );
  }
}