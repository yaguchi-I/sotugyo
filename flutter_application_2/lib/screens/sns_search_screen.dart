import 'package:flutter/material.dart';

class SnsSearchScreen extends StatelessWidget {
  const SnsSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('検索'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '検索...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildTag('トレンド'),
                _buildTag('タグ'),
                _buildTag('節約'),
                _buildTag('レシピ'),
                _buildTag('家計簿'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '人気のとうこう',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade300,
                  ),
                  title: Text('人気の投稿タイトル ${index + 1}'),
                  subtitle: const Text('投稿の本文がここに入ります...'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Chip(
        label: Text(text),
        backgroundColor: Colors.grey.shade200,
        side: BorderSide.none,
      ),
    );
  }
}