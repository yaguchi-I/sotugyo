import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SnsReplyScreen extends StatefulWidget {
  final String postId;
  final dynamic originalPost;

  const SnsReplyScreen({
    super.key,
    required this.postId,
    this.originalPost,
  });

  @override
  State createState() => _SnsReplyScreenState();
}

class _SnsReplyScreenState extends State {
  String get _postId => (widget as SnsReplyScreen).postId;
  dynamic get _originalPost => (widget as SnsReplyScreen).originalPost;

  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.trim().isEmpty) return null;
    try {
      final cleaned = base64String.contains(',')
          ? base64String.split(',').last.replaceAll(RegExp(r'\s+'), '')
          : base64String.replaceAll(RegExp(r'\s+'), '');
      if (cleaned.isEmpty) return null;
      return base64Decode(cleaned);
    } catch (e) {
      return null;
    }
  }

  List _extractPostImages(dynamic postData) {
    if (postData == null) return [];
    final List result = [];
    if (postData['imagesBase64'] != null && postData['imagesBase64'] is List) {
      for (final item in List.from(postData['imagesBase64'])) {
        final decoded = _decodeBase64(item?.toString());
        if (decoded != null) result.add(decoded);
      }
    }
    if (result.isEmpty && postData['imageBase64'] != null) {
      final decoded = _decodeBase64(postData['imageBase64']?.toString());
      if (decoded != null) result.add(decoded);
    }
    return result;
  }

  void _openFullScreenImage(Uint8List imageBytes) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (pageContext, animation, _) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(pageContext).pop(),
                child: Center(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
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
      String userName = user?.displayName ?? '';
      if (userName.isEmpty) {
        userName = (user?.email ?? '名無し').split('@').first;
      }
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

      final postRef =
          FirebaseFirestore.instance.collection('posts').doc(_postId);

      await postRef.collection('replies').add({
        'userId': uid,
        'userName': userName,
        'userIconBase64': userIconBase64,
        'content': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await postRef.update({
        'replies': FieldValue.increment(1),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('返信の送信に失敗しました')),
      );
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
    final post = _originalPost;
    final String postUserId = post != null ? (post['userId']?.toString() ?? '') : '';
    final String rawName = post != null ? (post['userName']?.toString() ?? '名無し') : '名無し';
    final String rawIcon = post != null ? (post['userIconBase64']?.toString() ?? '') : '';
    final List postImages = _extractPostImages(post);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '返信する',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton(
              onPressed: _isSending ? null : _submitReply,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('返信を送信'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post != null)
              StreamBuilder(
                stream: postUserId.isNotEmpty
                    ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(postUserId)
                        .snapshots()
                    : null,
                builder: (context, userSnap) {
                  String displayUserName = rawName;
                  String displayIconBase64 = rawIcon;

                  if (userSnap.hasData && userSnap.data != null) {
                    final uDoc = userSnap.data as DocumentSnapshot;
                    if (uDoc.exists && uDoc.data() != null) {
                      final uData = uDoc.data() as Map;
                      if (uData['userName'] != null &&
                          uData['userName'].toString().trim().isNotEmpty) {
                        displayUserName = uData['userName'].toString();
                      }
                      if (uData['iconBase64'] != null &&
                          uData['iconBase64'].toString().isNotEmpty) {
                        displayIconBase64 = uData['iconBase64'].toString();
                      }
                    }
                  }

                  final Uint8List? iconBytes = _decodeBase64(displayIconBase64);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blue.shade100,
                              backgroundImage: iconBytes != null
                                  ? MemoryImage(iconBytes)
                                  : null,
                              child: iconBytes == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 20,
                                      color: Colors.blue,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                displayUserName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (post['title'] != null &&
                            post['title'].toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            post['title'].toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                        if (post['content'] != null &&
                            post['content'].toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            post['content'].toString(),
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ],
                        if (postImages.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ...List.generate(postImages.length, (idx) {
                            final imgBytes = postImages[idx] as Uint8List;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: GestureDetector(
                                onTap: () => _openFullScreenImage(imgBytes),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    imgBytes,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _replyController,
              autofocus: true,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '返信を入力してください...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}