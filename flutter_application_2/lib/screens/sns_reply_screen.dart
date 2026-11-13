import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SnsReplyScreen extends StatefulWidget {
  final String postId;
  final dynamic originalPost;

  const SnsReplyScreen({super.key, required this.postId, this.originalPost});

  @override
  State createState() => _SnsReplyScreenState();
}

class _SnsReplyScreenState extends State {
  String get _postId => (widget as SnsReplyScreen).postId;
  dynamic get _originalPost => (widget as SnsReplyScreen).originalPost;

  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
  }

  void _openFullScreenImage(
    BuildContext context,
    Uint8List imageBytes,
    String heroTag,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        pageBuilder: (pageContext, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(pageContext).pop(),
                ),
              ),
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(pageContext).pop(),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Hero(
                      tag: heroTag,
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      String userName =
          user?.displayName ?? user?.email?.split('@')[0] ?? '名無しユーザー';
      String userIconBase64 = '';

      if (uid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          final uData = userDoc.data()!;
          if (uData['userName'] != null &&
              uData['userName'].toString().trim().isNotEmpty) {
            userName = uData['userName'].toString().trim();
          }
          if (uData['iconBase64'] != null) {
            userIconBase64 = uData['iconBase64'].toString();
          }
        }
      }

      final postRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(_postId);

      await postRef.collection('replies').add({
        'userId': uid,
        'userName': userName,
        'userIconBase64': userIconBase64,
        'content': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await postRef.update({'replies': FieldValue.increment(1)});

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('返信の送信に失敗しました')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dynamic post = _originalPost;
    final String origName = post != null
        ? (post['userName']?.toString() ?? '投稿者')
        : '投稿者';
    final String origContent = post != null
        ? (post['content']?.toString() ?? '')
        : '';
    final Uint8List? origIconBytes = post != null
        ? _decodeBase64(post['userIconBase64']?.toString())
        : null;
    final Uint8List? origImageBytes = post != null
        ? _decodeBase64(post['imageBase64']?.toString())
        : null;
    final String heroTag = 'reply_img_$_postId';

    return Scaffold(
      appBar: AppBar(
        title: const Text('返信を投稿'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            child: ElevatedButton(
              onPressed: _isSending ? null : _submitReply,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey,
                    backgroundImage: origIconBytes != null
                        ? MemoryImage(origIconBytes)
                        : null,
                    child: origIconBytes == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          origName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          origContent,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        if (origImageBytes != null) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _openFullScreenImage(
                              context,
                              origImageBytes,
                              heroTag,
                            ),
                            child: Hero(
                              tag: heroTag,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 180,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    origImageBytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
            ],
            TextField(
              controller: _replyController,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '返信を入力...',
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
