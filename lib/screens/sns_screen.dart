import 'package:flutter/material.dart';

class SnsScreen extends StatelessWidget {
  const SnsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('タイムライン')),
      body: const Center(child: Text('タイムライン画面')),
    );
  }
}