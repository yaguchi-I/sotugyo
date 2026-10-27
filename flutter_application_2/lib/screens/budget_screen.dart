import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'dart:io';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool isCalendarView = true;

  // --- 家計簿データ (日ごとに複数の支出とカテゴリを保存) ---
  final Map<int, List<Map<String, dynamic>>> _dailyExpenses = {};

  // --- 貯蓄ノートデータ ---
  int _monthlyIncome = 0;
  int _payday = 25; // デフォルト25日
  final List<Map<String, dynamic>> _largeExpenses = [];
  bool _syncWithBudget = false; // 家計簿と連携するかどうかの設定

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.japanese,
  );

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // ==========================================
  // 家計簿：入力ダイアログ（タグ選択付き）
  // ==========================================
  void _showInputModal(int day, {int? initialAmount}) {
    final controller = TextEditingController(
      text: initialAmount != null ? initialAmount.toString() : '',
    );
    String selectedCategory = '食費'; // デフォルトのカテゴリ
    final categories = ['食費', '日用品', '交通費', '交際費', '趣味', '雑費', 'その他'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // ダイアログ内のUIを更新するために必要
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('10月$day日の支出'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '金額 (円)',
                      prefixText: '¥ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'カテゴリ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: categories.map((category) {
                      return ChoiceChip(
                        label: Text(category),
                        selected: selectedCategory == category,
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedCategory = category);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = int.tryParse(controller.text) ?? 0;
                  if (amount > 0) {
                    setState(() {
                      if (_dailyExpenses[day] == null) {
                        _dailyExpenses[day] = [];
                      }
                      _dailyExpenses[day]!.add({
                        'amount': amount,
                        'category': selectedCategory,
                      });
                    });
                  }
                  Navigator.pop(context);
                },
                child: const Text('記録する'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // 家計簿：レシート読み取り
  // ==========================================
  Future<void> _scanReceiptAndInput() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('レシートを解析中...')));

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final text = recognizedText.text;

      final dateRegExp = RegExp(r'\d{4}[年/]\d{1,2}[月/](\d{1,2})[日]?');
      final amountRegExp = RegExp(r'(?:合計|小計|¥|￥)\s*([0-9,]+)');

      int? extractedDay;
      int? extractedAmount;

      final dateMatch = dateRegExp.firstMatch(text);
      if (dateMatch != null)
        extractedDay = int.tryParse(dateMatch.group(1) ?? '');

      final amountMatch = amountRegExp.firstMatch(text);
      if (amountMatch != null) {
        final amountStr = amountMatch.group(1)?.replaceAll(',', '') ?? '';
        extractedAmount = int.tryParse(amountStr);
      }

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) {
        _showInputModal(
          extractedDay ?? DateTime.now().day,
          initialAmount: extractedAmount,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('読み取りに失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お金の管理'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => isCalendarView = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isCalendarView
                                  ? Colors.blue
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '家計簿',
                                style: TextStyle(
                                  color: isCalendarView
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => isCalendarView = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !isCalendarView
                                  ? Colors.blue
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '貯蓄ノート',
                                style: TextStyle(
                                  color: !isCalendarView
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: isCalendarView ? _buildCalendar() : _buildSavingsNote(),
              ),
            ],
          ),
          if (isCalendarView) // カメラボタンは家計簿の時だけ表示
            Positioned(
              left: 16,
              bottom: 110,
              child: FloatingActionButton(
                heroTag: 'camera_btn',
                onPressed: _scanReceiptAndInput,
                backgroundColor: Colors.white,
                shape: const CircleBorder(),
                child: const Icon(Icons.camera_alt, color: Colors.black),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 110,
            child: FloatingActionButton(
              heroTag: 'ai_btn',
              onPressed: () {},
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Text(
                'AI',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 家計簿：カレンダー画面
  // ==========================================
  Widget _buildCalendar() {
    return GridView.builder(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 180.0,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.6,
      ),
      itemCount: 31,
      itemBuilder: (context, index) {
        final day = index + 1;
        final dayData = _dailyExpenses[day] ?? [];
        // その日の支出合計を計算
        final totalAmount = dayData.fold<int>(
          0,
          (sum, item) => sum + (item['amount'] as int),
        );

        return GestureDetector(
          onTap: () => _showInputModal(day),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              color: Colors.white,
            ),
            child: Column(
              children: [
                Text('$day'),
                const Spacer(),
                if (totalAmount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: Text(
                      '¥$totalAmount',
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 貯蓄ノート画面
  // ==========================================
  Widget _buildSavingsNote() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 180.0, left: 16, right: 16),
      children: [
        // --- 収入・給料日設定 ---
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.account_balance_wallet,
              color: Colors.green,
            ),
            title: const Text('毎月の収入設定'),
            subtitle: Text('月収: ¥$_monthlyIncome\n給料日: 毎月$_payday日'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _showIncomeDialog,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // --- 大きな支出管理 ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '大きな支出管理',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.blue),
                      onPressed: _showLargeExpenseDialog,
                    ),
                  ],
                ),
                const Divider(),
                if (_largeExpenses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      '予定されている大きな支出はありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ..._largeExpenses.map(
                  (expense) => ListTile(
                    title: Text(expense['name']),
                    trailing: Text(
                      '¥${expense['amount']}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // --- 設定項目 ---
        Card(
          child: SwitchListTile(
            title: const Text('家計簿の収支と連携する'),
            subtitle: const Text('給料日の自動加算と支出を合算します'),
            value: _syncWithBudget,
            onChanged: (bool value) {
              setState(() {
                _syncWithBudget = value;
              });
            },
          ),
        ),
      ],
    );
  }

  // 収入と給料日を設定するダイアログ
  void _showIncomeDialog() {
    final incomeController = TextEditingController(
      text: _monthlyIncome.toString(),
    );
    final paydayController = TextEditingController(text: _payday.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('収入設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: incomeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '毎月の収入 (円)'),
            ),
            TextField(
              controller: paydayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '給料日 (日)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _monthlyIncome = int.tryParse(incomeController.text) ?? 0;
                _payday = int.tryParse(paydayController.text) ?? 25;
              });
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 大きな支出を追加するダイアログ
  void _showLargeExpenseDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('大きな支出を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '支出名 (例: 車検, 旅行)'),
            ),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金額 (円)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  amountController.text.isNotEmpty) {
                setState(() {
                  _largeExpenses.add({
                    'name': nameController.text,
                    'amount': int.tryParse(amountController.text) ?? 0,
                  });
                });
              }
              Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }
}
