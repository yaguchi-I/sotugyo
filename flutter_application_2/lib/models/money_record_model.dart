import 'package:cloud_firestore/cloud_firestore.dart';

class MoneyRecordModel {
  final String id;
  final String userId;
  final int amount;
  final String category;
  final String date;
  final DateTime? createdAt;

  MoneyRecordModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.date,
    this.createdAt,
  });

  factory MoneyRecordModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MoneyRecordModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      amount: data['amount'] ?? 0,
      category: data['category'] ?? '食費',
      date: data['date'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'amount': amount,
      'category': category,
      'date': date,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
