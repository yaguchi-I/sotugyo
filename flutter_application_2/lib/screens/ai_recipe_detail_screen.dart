import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AiRecipeDetailScreen extends StatelessWidget {
  final String postId;

  const AiRecipeDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('データが見つかりません'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final content = data['content'] ?? '';
          final subCategory = data['subCategory'] ?? 'レシピ';

          final bool isRecipe = subCategory == 'レシピ';

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 200,
                  color: isRecipe
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  child: Icon(
                    isRecipe ? Icons.restaurant_menu : Icons.lightbulb_outline,
                    size: 80,
                    color: isRecipe ? Colors.orange : Colors.green,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: isRecipe ? Colors.purple : Colors.teal,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRecipe ? 'AIが考えたあなた専用レシピ' : 'AIからの生活アドバイス',
                            style: TextStyle(
                              color: isRecipe
                                  ? Colors.purple.shade700
                                  : Colors.teal.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
