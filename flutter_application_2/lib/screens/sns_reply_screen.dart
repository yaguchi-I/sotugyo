import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SnsReplyScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> originalPost;

  const SnsReplyScreen({
    super.key,
    required this.postId,
    required this.originalPost,
  });

  @override
  State<SnsReplyScreen> createState() => _SnsReplyScreenState();
}

class _SnsReplyScreenState extends State<SnsReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isReplying = false;

  Future<void> _sendReply() async {
    if (_replyController.text.isEmpty) return;

    setState(() {
      _isReplying = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@')[0] ?? '名無しユーザー';

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies')
          .add({
            'userName': userName,
            'content': _replyController.text,
            'createdAt': FieldValue.serverTimestamp(),
          });

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'replies': FieldValue.increment(1)});

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('エラーが発生しました')));
      setState(() {
        _isReplying = false;
      });
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ポストを返信',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            child: ElevatedButton(
              onPressed: _isReplying ? null : _sendReply,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isReplying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '返信',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Container(width: 2, height: 50, color: Colors.grey),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.originalPost['userName'] ?? '名無し',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.originalPost['content'] ?? '',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      maxLines: null,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '返信をポスト',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
