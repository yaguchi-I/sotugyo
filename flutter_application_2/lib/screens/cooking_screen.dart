import 'package:flutter/material.dart';

class CookingScreen extends StatelessWidget {
  const CookingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('料理サポート')),
      body: const Center(child: Text('料理サポート画面')),
    );
  }
}