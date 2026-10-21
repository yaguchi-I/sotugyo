/// レシートをOCR（Gemini）で読み取った結果。
/// 家計簿処理・DB保存など、他の担当に渡すときはこのクラスでやり取りする。
class ReceiptItem {
  final String name;
  final int price;

  const ReceiptItem({required this.name, required this.price});

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      name: (json['name'] ?? '').toString(),
      price: _toInt(json['price']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'price': price};
}

class ReceiptData {
  final bool isReceipt;
  final String? store;
  final DateTime? date;
  final List<ReceiptItem> items;
  final int? total;
  final String? category;

  const ReceiptData({
    required this.isReceipt,
    this.store,
    this.date,
    this.items = const [],
    this.total,
    this.category,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ReceiptData(
      isReceipt: json['isReceipt'] == true,
      store: _emptyToNull(json['store']),
      date: DateTime.tryParse((json['date'] ?? '').toString()),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => ReceiptItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total: _toInt(json['total']),
      category: _emptyToNull(json['category']),
    );
  }

  /// 合計が読めなかったときは品目の合計で代用
  int get totalOrSum =>
      total ?? items.fold(0, (sum, item) => sum + item.price);

  /// Firestore などにそのまま保存できる形
  Map<String, dynamic> toMap() => {
        'store': store,
        'date': date?.toIso8601String(),
        'items': items.map((e) => e.toMap()).toList(),
        'total': totalOrSum,
        'category': category,
      };

  /// AIとの相談で前提として渡すための文章
  String toPromptText() {
    final buffer = StringBuffer()
      ..writeln('店名: ${store ?? '不明'}')
      ..writeln('日付: ${date != null ? _formatDate(date!) : '不明'}')
      ..writeln('カテゴリ: ${category ?? '不明'}')
      ..writeln('品目:');
    for (final item in items) {
      buffer.writeln('- ${item.name} ${item.price}円');
    }
    buffer.writeln('合計: $totalOrSum円');
    return buffer.toString();
  }
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.round();
  final digits = value.toString().replaceAll(RegExp(r'[^0-9\-]'), '');
  return int.tryParse(digits);
}

String? _emptyToNull(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

String _formatDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
