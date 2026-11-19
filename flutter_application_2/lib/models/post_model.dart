import 'package:cloud_firestore/cloud_firestore.dart';

//　要はぁぁ投稿データの構造を定義するモデルクラス
class PostModel {
  final String id; // FirestoreのドキュメントID
  final String userName; // 投稿者名
  final String content; // 本文
  final bool hasImage; // 画像が含まれているかどうか
  final String mainCategory; // メインカテゴリ　料理、掃除、収納、その他など
  final String subCategory; // サブカテゴリ
  final int replies; // 返信数
  final int likes; // いいね数
  final int helpfuls; // お役立ち数（仮案です）
  final List<String> likedUsers; // いいねしたユーザーのUID一覧
  final List<String> helpfulUsers; // お役立ち（仮案）を押したユーザーのUID一覧
  final List<String> savedUsers; // ブックマークしたユーザーのUID一覧
  final DateTime? createdAt; // 投稿日時

  PostModel({
    required this.id,
    required this.userName,
    required this.content,
    required this.hasImage,
    required this.mainCategory,
    required this.subCategory,
    required this.replies,
    required this.likes,
    required this.helpfuls,
    required this.likedUsers,
    required this.helpfulUsers,
    required this.savedUsers,
    this.createdAt,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      userName: data['userName'] ?? '名無し',
      content: data['content'] ?? '',
      hasImage: data['hasImage'] ?? false,
      mainCategory: data['mainCategory'] ?? '指定なし',
      subCategory: data['subCategory'] ?? '指定なし',
      replies: data['replies'] ?? 0,
      likes: data['likes'] ?? 0,
      helpfuls: data['helpfuls'] ?? 0,
      likedUsers: List<String>.from(data['likedUsers'] ?? []),
      helpfulUsers: List<String>.from(data['helpfulUsers'] ?? []),
      savedUsers: List<String>.from(data['savedUsers'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userName': userName,
      'content': content,
      'hasImage': hasImage,
      'mainCategory': mainCategory,
      'subCategory': subCategory,
      'replies': replies,
      'likes': likes,
      'helpfuls': helpfuls,
      'likedUsers': likedUsers,
      'helpfulUsers': helpfulUsers,
      'savedUsers': savedUsers,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
