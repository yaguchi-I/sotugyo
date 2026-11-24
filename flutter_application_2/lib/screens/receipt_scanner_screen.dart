import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/money_record_model.dart' show MoneyRecordModel;
import 'ai_chat_screen.dart' show AiChatScreen;
import '../widgets/top_toast.dart' show showTopToast;

class ReceiptScannerScreen extends StatefulWidget {
  final int? initialYear;
  final int? initialMonth;

  const ReceiptScannerScreen({super.key, this.initialYear, this.initialMonth});

  @override
  State createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State {
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final ImagePicker _picker = ImagePicker();
  TextRecognizer? _textRecognizer;

  static const List _categories = [
    '食費',
    '日用品',
    '交通費',
    '交際費',
    '趣味',
    '雑費',
    'その他',
  ];

  Uint8List? _imageBytes;
  String _storeName = '';
  String _rawOcrText = '';
  late DateTime _selectedDate;
  final List _extractedEntries = [];
  bool _isAnalyzing = false;
  bool _isSaving = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final w = widget as ReceiptScannerScreen;
    final y = w.initialYear ?? now.year;
    final m = w.initialMonth ?? now.month;
    final maxDay = DateTime(y, m + 1, 0).day;
    final d = now.day > maxDay ? maxDay : now.day;
    _selectedDate = DateTime(y, m, d);

    if (!kIsWeb) {
      try {
        _textRecognizer = TextRecognizer(
          script: TextRecognitionScript.japanese,
        );
      } catch (e) {
        _textRecognizer = null;
      }
    }
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    for (final raw in _extractedEntries) {
      final entry = raw as Map;
      (entry['amountCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _normalizeCategory(String raw) {
    final trimmed = raw.trim();
    if (_categories.contains(trimmed)) return trimmed;
    if (trimmed.contains('食') ||
        trimmed.contains('飲') ||
        trimmed.contains('カフェ')) {
      return '食費';
    }
    if (trimmed.contains('日用') ||
        trimmed.contains('薬') ||
        trimmed.contains('生活')) {
      return '日用品';
    }
    if (trimmed.contains('交通') ||
        trimmed.contains('電車') ||
        trimmed.contains('バス')) {
      return '交通費';
    }
    if (trimmed.contains('交際') || trimmed.contains('飲み')) {
      return '交際費';
    }
    if (trimmed.contains('趣味') ||
        trimmed.contains('娯楽') ||
        trimmed.contains('本')) {
      return '趣味';
    }
    if (trimmed.contains('雑')) return '雑費';
    return 'その他';
  }

  DateTime? _parseDateString(String raw) {
    final normalized = raw
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .trim();
    final match = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
    if (match != null) {
      final y = int.tryParse(match.group(1) ?? '');
      final m = int.tryParse(match.group(2) ?? '');
      final d = int.tryParse(match.group(3) ?? '');
      if (y != null &&
          m != null &&
          d != null &&
          y >= 2020 &&
          y <= 2035 &&
          m >= 1 &&
          m <= 12 &&
          d >= 1 &&
          d <= 31) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  Map? _extractJsonObject(String rawText) {
    final fence = String.fromCharCodes([96, 96, 96]);
    final cleaned = rawText
        .replaceAll('${fence}json', '')
        .replaceAll(fence, '')
        .trim();
    final startIdx = cleaned.indexOf('{');
    final endIdx = cleaned.lastIndexOf('}');
    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) return null;
    try {
      final decoded = jsonDecode(cleaned.substring(startIdx, endIdx + 1));
      if (decoded is Map) return Map.from(decoded);
    } catch (e) {}
    return null;
  }

  void _clearEntries() {
    for (final raw in _extractedEntries) {
      final entry = raw as Map;
      (entry['amountCtrl'] as TextEditingController).dispose();
    }
    _extractedEntries.clear();
  }

  void _addEntry({
    required int amount,
    required String category,
    String summary = '',
  }) {
    _extractedEntries.add({
      'amountCtrl': TextEditingController(
        text: amount > 0 ? amount.toString() : '',
      ),
      'category': _normalizeCategory(category),
      'summary': summary,
    });
  }

  void _removeEntry(int index) {
    setState(() {
      final entry = _extractedEntries.removeAt(index) as Map;
      (entry['amountCtrl'] as TextEditingController).dispose();
    });
  }

  int _calcTotalAmount() {
    int total = 0;
    for (final raw in _extractedEntries) {
      final entry = raw as Map;
      final val =
          int.tryParse(
            (entry['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (val > 0) total += val;
    }
    return total;
  }

  Future _pickAndAnalyzeReceipt(ImageSource source) async {
    if (_isAnalyzing) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('画像の取得に失敗しました: $e')));
      }
      return;
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _imageBytes = bytes;
      _isAnalyzing = true;
      _statusMessage = 'レシートの文字を読み取っています...';
      _storeName = '';
      _rawOcrText = '';
      _clearEntries();
    });

    String ocrText = '';
    if (!kIsWeb && _textRecognizer != null) {
      try {
        final inputImage = InputImage.fromFilePath(picked.path);
        final recognized = await _textRecognizer!.processImage(inputImage);
        ocrText = recognized.text.trim();
      } catch (e) {}
    }

    if (mounted) {
      setState(() {
        _rawOcrText = ocrText;
        _statusMessage = 'AIが品目・金額・カテゴリを自動仕分けしています...';
      });
    }

    Map? aiResult;
    final currentKey = AiChatScreen.apiKey.trim();

    if (currentKey.isNotEmpty && !currentKey.contains('ここに')) {
      final todayKey = _formatDateKey(DateTime.now());
      final prompt =
          'あなたは日本の家計簿アプリ専属の高精度レシートOCR＆自動仕分けエンジンです。\n'
          '添付したレシート画像（および補助OCRテキスト）を読み取り、日付・店舗名・カテゴリ別の金額合計をJSON形式のみで出力してください。\n\n'
          '【使用可能カテゴリ（この7つ以外は絶対に使わないこと）】\n'
          '食費, 日用品, 交通費, 交際費, 趣味, 雑費, その他\n\n'
          '【抽出ルール】\n'
          '1. 割引・クーポン・消費税を反映した「実際に支払った合計金額」に整合するように各カテゴリの金額を集計すること。\n'
          '2. 食品と日用品が混在している場合は、カテゴリごとに分けて複数要素にすること。同じカテゴリの商品は合算して1要素にまとめてよい。\n'
          '3. 日付が読み取れない場合は "$todayKey" にすること。\n'
          '4. レシートではない・金額が読み取れない場合は items を空配列 [] にすること。\n'
          '${ocrText.isNotEmpty ? "\n【補助OCRテキスト】\n$ocrText\n" : ""}\n'
          '【出力JSONフォーマット（説明文なし・JSONのみ）】\n'
          '{"storeName": "店舗名", "date": "YYYY-MM-DD", "items": [{"category": "食費", "amount": 840, "summary": "豚肉・キャベツ・卵"}]}';

      for (final modelItem in AiChatScreen.fallbackModels) {
        try {
          final model = GenerativeModel(
            model: modelItem.toString(),
            apiKey: currentKey,
            generationConfig: GenerationConfig(temperature: 0.0),
          );
          final response = await model
              .generateContent([
                Content.multi([
                  TextPart(prompt),
                  DataPart('image/jpeg', bytes),
                ]),
              ])
              .timeout(const Duration(seconds: 25));

          if (response.text != null && response.text!.trim().isNotEmpty) {
            final parsed = _extractJsonObject(response.text!);
            if (parsed != null) {
              aiResult = parsed;
              break;
            }
          }
        } catch (e) {}
      }
    }

    if (!mounted) return;

    if (aiResult != null) {
      final parsedDate = _parseDateString((aiResult['date'] ?? '').toString());
      final store = (aiResult['storeName'] ?? '').toString().trim();
      final List rawItems = aiResult['items'] is List
          ? List.from(aiResult['items'])
          : [];

      setState(() {
        if (parsedDate != null) _selectedDate = parsedDate;
        _storeName = store;
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final amt =
              int.tryParse(
                (rawItem['amount'] ?? '0').toString().replaceAll(',', ''),
              ) ??
              0;
          if (amt <= 0) continue;
          _addEntry(
            amount: amt,
            category: (rawItem['category'] ?? '食費').toString(),
            summary: (rawItem['summary'] ?? '').toString(),
          );
        }
        if (_extractedEntries.isEmpty) {
          _applyLocalOcrFallback(ocrText);
        }
        _isAnalyzing = false;
        _statusMessage = _extractedEntries.isEmpty
            ? '金額を自動抽出できませんでした。下のボタンから手動で追加できます。'
            : '解析が完了しました！内容を確認して登録してください。';
      });
    } else {
      setState(() {
        _applyLocalOcrFallback(ocrText);
        _isAnalyzing = false;
        _statusMessage = _extractedEntries.isEmpty
            ? 'AI解析または読み取りに失敗しました。手動で追加するか別の画像でお試しください。'
            : 'OCRテキストから金額を抽出しました。カテゴリと金額を確認してください。';
      });
    }
  }

  void _applyLocalOcrFallback(String text) {
    if (text.isEmpty) return;
    final dateMatch = RegExp(r'(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})')
        .firstMatch(text);
    if (dateMatch != null) {
      final parsed = _parseDateString(dateMatch.group(0) ?? '');
      if (parsed != null) _selectedDate = parsed;
    }

    final amountMatch = RegExp(r'(?:合計|お買上計|領収|税込合計|¥|￥)\s*([0-9,]+)')
        .firstMatch(text);
    if (amountMatch != null) {
      final amt =
          int.tryParse((amountMatch.group(1) ?? '').replaceAll(',', '')) ?? 0;
      if (amt > 0) {
        _addEntry(amount: amt, category: '食費', summary: 'OCR抽出');
      }
    }
  }

  Future _saveAllToFirestore() async {
    if (_isSaving) return;
    if (_currentUserId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('家計簿へ登録するにはログインが必要です')));
      return;
    }

    final List validRecords = [];
    final dateStr = _formatDateKey(_selectedDate);

    for (final raw in _extractedEntries) {
      final entry = raw as Map;
      final amt =
          int.tryParse(
            (entry['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (amt > 0) {
        validRecords.add(
          MoneyRecordModel(
            id: '',
            userId: _currentUserId,
            amount: amt,
            category: entry['category'].toString(),
            date: dateStr,
          ),
        );
      }
    }

    if (validRecords.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('1円以上の明細を1件以上入力してください')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('money_record');
      for (final rec in validRecords) {
        final docRef = col.doc();
        batch.set(docRef, (rec as MoneyRecordModel).toMap());
      }
      await batch.commit();

      if (!mounted) return;
      showTopToast(
        context,
        '${validRecords.length}件（合計 ¥${_formatCurrency(_calcTotalAmount())}）を家計簿に登録しました',
      );
      Navigator.pop(context, {
        'saved': true,
        'date': dateStr,
        'count': validRecords.length,
        'total': _calcTotalAmount(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
    }
  }

  Future _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = _calcTotalAmount();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AIレシート読み取り',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'レシートを撮影・選択すると、AIが日付とカテゴリ別の金額を自動仕分けします',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isAnalyzing
                                  ? null
                                  : () => _pickAndAnalyzeReceipt(
                                      ImageSource.camera,
                                    ),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('カメラで撮影'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isAnalyzing
                                  ? null
                                  : () => _pickAndAnalyzeReceipt(
                                      ImageSource.gallery,
                                    ),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('画像を選択'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_imageBytes != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                  ),
                ],
                if (_isAnalyzing) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (_storeName.isNotEmpty)
                                Text(
                                  '店舗: $_storeName',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _pickDate,
                          child: const Text('日付を変更'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '抽出された明細（編集可能）',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _addEntry(amount: 0, category: '食費');
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('明細を追加'),
                      ),
                    ],
                  ),
                  if (_extractedEntries.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Text(
                        'レシートを読み取ると、ここにカテゴリ別の明細が並びます',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  for (int i = 0; i < _extractedEntries.length; i++)
                    Builder(
                      builder: (_) {
                        final entry = _extractedEntries[i] as Map;
                        final ctrl =
                            entry['amountCtrl'] as TextEditingController;
                        final selectedCat = entry['category'].toString();
                        final summary = (entry['summary'] ?? '').toString();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) => setState(() {}),
                                        decoration: const InputDecoration(
                                          labelText: '金額 (円)',
                                          prefixText: '¥ ',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => _removeEntry(i),
                                    ),
                                  ],
                                ),
                                if (summary.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text(
                                      '内容: $summary',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final rawCat in _categories)
                                      ChoiceChip(
                                        label: Text(
                                          rawCat.toString(),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        selected:
                                            selectedCat == rawCat.toString(),
                                        selectedColor: Colors.blue.shade100,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() {
                                              entry['category'] = rawCat
                                                  .toString();
                                            });
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  if (_extractedEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveAllToFirestore,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          '家計簿に登録する（合計 ¥${_formatCurrency(totalAmount)}）',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  if (_rawOcrText.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '読み取ったOCR生テキストを確認',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _rawOcrText,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
