import 'package:cloud_firestore/cloud_firestore.dart';

/// 大きな支出データを定義するモデルクラス
class LargeExpenseModel {
  final String id; // FirestoreのドキュメントID
  final String userId; // ユーザーUID
  final String name; // 支出名（例: 車検、旅行など）
  final int amount; // 金額
  final DateTime? dueDate; // 支払い予定日（任意。未設定の古いデータは null）
  final DateTime? createdAt; // 作成日時

  LargeExpenseModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.amount,
    this.dueDate,
    this.createdAt,
  });

  /// FirestoreのドキュメントスナップショットからLargeExpenseModelを生成
  factory LargeExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LargeExpenseModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      amount: data['amount'] ?? 0,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Firestoreへ保存するためにMap形式へ変換
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'amount': amount,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
