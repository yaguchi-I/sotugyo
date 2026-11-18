import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'dart:io';

import '../models/money_record_model.dart';
import '../models/large_expense_model.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool isCalendarView = true;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  double _amountFontSize = 13.0;

  int _monthlyIncome = 0;
  int _payday = 25;
  List<LargeExpenseModel> _largeExpenses = [];

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.japanese,
  );

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _loadUserSettings() async {
    if (currentUserId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _monthlyIncome = data['monthlyIncome'] ?? 0;
          _payday = data['payday'] ?? 25;
        });
      }
    } catch (e) {}
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _getDateKey(int year, int month, int day) {
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  void _onDayTap(
    int year,
    int month,
    int day,
    List<MoneyRecordModel> dayExpenses,
  ) {
    if (dayExpenses.isEmpty) {
      _showInputModal(year, month, day);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$month月$day日の操作'),
          content: const Text('行いたい操作を選んでください'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showInputModal(year, month, day);
              },
              child: const Text('新しく支出を追加'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showDetailAndEditModal(year, month, day, dayExpenses);
              },
              child: const Text('明細を確認・編集する'),
            ),
          ],
        ),
      );
    }
  }

  void _showDetailAndEditModal(
    int year,
    int month,
    int day,
    List<MoneyRecordModel> expenses,
  ) {
    final total = expenses.fold<int>(0, (sum, item) => sum + item.amount);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$month月$day日の明細 (合計: ¥${_formatCurrency(total)})'),
        content: SizedBox(
          width: double.maxFinite,
          child: expenses.isEmpty
              ? const Text('登録されている明細はありません')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final item = expenses[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('カテゴリ: ${item.category}'),
                        subtitle: Text('金額: ¥${_formatCurrency(item.amount)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditItemModal(item);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                Navigator.pop(context);
                                await FirebaseFirestore.instance
                                    .collection('money_record')
                                    .doc(item.id)
                                    .delete();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showInputModal(year, month, day);
            },
            child: const Text('追加する'),
          ),
        ],
      ),
    );
  }

  void _showEditItemModal(MoneyRecordModel item) {
    final controller = TextEditingController(text: item.amount.toString());
    String selectedCategory = item.category;

    final dateParts = item.date.split('-');
    int targetYear = int.parse(dateParts[0]);
    int targetMonth = int.parse(dateParts[1]);
    int targetDay = int.parse(dateParts[2]);

    final categories = ['食費', '日用品', '交通費', '交際費', '趣味', '雑費', 'その他'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('支出の編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '日付: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime(
                              targetYear,
                              targetMonth,
                              targetDay,
                            ),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (pickedDate != null) {
                            setDialogState(() {
                              targetYear = pickedDate.year;
                              targetMonth = pickedDate.month;
                              targetDay = pickedDate.day;
                            });
                          }
                        },
                        child: Text('$targetYear年$targetMonth月$targetDay日'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                onPressed: () async {
                  final amount = int.tryParse(controller.text) ?? 0;
                  if (amount > 0) {
                    final newDateStr = _getDateKey(
                      targetYear,
                      targetMonth,
                      targetDay,
                    );
                    await FirebaseFirestore.instance
                        .collection('money_record')
                        .doc(item.id)
                        .update({
                          'amount': amount,
                          'category': selectedCategory,
                          'date': newDateStr,
                        });
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('更新する'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showInputModal(int year, int month, int day, {int? initialAmount}) {
    final controller = TextEditingController(
      text: initialAmount != null ? initialAmount.toString() : '',
    );
    String selectedCategory = '食費';
    final categories = ['食費', '日用品', '交通費', '交際費', '趣味', '雑費', 'その他'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('$month月$day日の支出追加'),
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
                onPressed: () async {
                  final amount = int.tryParse(controller.text) ?? 0;
                  if (amount > 0 && currentUserId.isNotEmpty) {
                    final dateStr = _getDateKey(year, month, day);
                    final newRecord = MoneyRecordModel(
                      id: '',
                      userId: currentUserId,
                      amount: amount,
                      category: selectedCategory,
                      date: dateStr,
                    );
                    await FirebaseFirestore.instance
                        .collection('money_record')
                        .add(newRecord.toMap());
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('記録する'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _scanReceiptAndInput() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('レシートを解析中...')));

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final text = recognizedText.text;

      final dateRegExp = RegExp(r'\d{4}[年/]\d{1,2}[月/](\d{1,2})[日]?');
      final amountRegExp = RegExp(r'(?:合計|小計|¥|￥)\s*([0-9,]+)');

      int? extractedDay = DateTime.now().day;
      int? extractedAmount;

      final dateMatch = dateRegExp.firstMatch(text);
      if (dateMatch != null) {
        extractedDay = int.tryParse(dateMatch.group(1) ?? '');
      }

      final amountMatch = amountRegExp.firstMatch(text);
      if (amountMatch != null) {
        final amountStr = amountMatch.group(1)?.replaceAll(',', '') ?? '';
        extractedAmount = int.tryParse(amountStr);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showInputModal(
        _selectedYear,
        _selectedMonth,
        extractedDay ?? DateTime.now().day,
        initialAmount: extractedAmount,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('読み取りに失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お金の管理'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.text_format),
            tooltip: '文字サイズ変更',
            onSelected: (size) {
              setState(() {
                _amountFontSize = size;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 11.0, child: Text('小')),
              const PopupMenuItem(value: 13.0, child: Text('中（標準）')),
              const PopupMenuItem(value: 16.0, child: Text('大')),
            ],
          ),
        ],
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
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('money_record')
                      .where('userId', isEqualTo: currentUserId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final allRecords = docs
                        .map((doc) => MoneyRecordModel.fromFirestore(doc))
                        .toList();

                    return isCalendarView
                        ? _buildCalendar(allRecords)
                        : _buildSavingsNote();
                  },
                ),
              ),
            ],
          ),
          if (isCalendarView)
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

  Widget _buildCalendar(List<MoneyRecordModel> allRecords) {
    final Map<String, List<MoneyRecordModel>> dailyMap = {};
    for (var tx in allRecords) {
      if (dailyMap[tx.date] == null) {
        dailyMap[tx.date] = [];
      }
      dailyMap[tx.date]!.add(tx);
    }

    int monthlyTotal = 0;
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      final key = _getDateKey(_selectedYear, _selectedMonth, day);
      final dayData = dailyMap[key] ?? [];
      for (var item in dayData) {
        monthlyTotal += item.amount;
      }
    }

    final firstDayOfWeek = DateTime(_selectedYear, _selectedMonth, 1).weekday;
    final leadingSpaces = firstDayOfWeek % 7;
    final totalDaysNeeded = leadingSpaces + daysInMonth;
    final totalCells = totalDaysNeeded <= 35 ? 35 : 42;

    final weekDays = ['日', '月', '火', '水', '木', '金', '土'];
    final now = DateTime.now();

    final prevMonthLastDay = DateTime(_selectedYear, _selectedMonth, 0).day;
    int prevYear = _selectedYear;
    int prevMonth = _selectedMonth - 1;
    if (prevMonth < 1) {
      prevMonth = 12;
      prevYear--;
    }

    int nextYear = _selectedYear;
    int nextMonth = _selectedMonth + 1;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear++;
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_selectedYear年$_selectedMonth月の総支出',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              Text(
                '¥${_formatCurrency(monthlyTotal)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    if (_selectedMonth > 1) {
                      _selectedMonth--;
                    } else {
                      _selectedMonth = 12;
                      _selectedYear--;
                    }
                  });
                },
              ),
              DropdownButton<int>(
                value: _selectedMonth,
                items: List.generate(12, (index) {
                  return DropdownMenuItem(
                    value: index + 1,
                    child: Text(
                      '$_selectedYear年 ${index + 1}月',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedMonth = value;
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    if (_selectedMonth < 12) {
                      _selectedMonth++;
                    } else {
                      _selectedMonth = 1;
                      _selectedYear++;
                    }
                  });
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekDays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: w == '日'
                              ? Colors.red
                              : (w == '土' ? Colors.blue : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 4.0,
              bottom: 180.0,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.45,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              int year;
              int month;
              int day;
              bool isCurrentMonth = false;

              if (index < leadingSpaces) {
                year = prevYear;
                month = prevMonth;
                day = prevMonthLastDay - leadingSpaces + index + 1;
              } else if (index < leadingSpaces + daysInMonth) {
                year = _selectedYear;
                month = _selectedMonth;
                day = index - leadingSpaces + 1;
                isCurrentMonth = true;
              } else {
                year = nextYear;
                month = nextMonth;
                day = index - (leadingSpaces + daysInMonth) + 1;
              }

              final key = _getDateKey(year, month, day);
              final dayData = dailyMap[key] ?? [];

              final totalAmount = dayData.fold<int>(
                0,
                (sum, item) => sum + item.amount,
              );

              final isToday =
                  (now.year == year && now.month == month && now.day == day);

              return GestureDetector(
                onTap: () => _onDayTap(year, month, day, dayData),
                child: Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isToday ? Colors.blue : Colors.grey.shade300,
                      width: isToday ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: isToday
                        ? Colors.blue.shade50
                        : (isCurrentMonth ? Colors.white : Colors.grey.shade50),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: dayData.isEmpty ? 32 : 18,
                          color: isToday
                              ? Colors.blue.shade700
                              : (isCurrentMonth
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF333333)
                                          .withOpacity(0.35)),
                        ),
                      ),
                      if (dayData.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        ...dayData
                            .take(5)
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${item.category}: ¥${_formatCurrency(item.amount)}',
                                    style: TextStyle(
                                      fontSize: _amountFontSize,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                        if (dayData.length > 5)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '他 ${dayData.length - 5}件...',
                              style: TextStyle(
                                fontSize: _amountFontSize - 2,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const Divider(height: 6, thickness: 1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '計 ¥${_formatCurrency(totalAmount)}',
                            style: TextStyle(
                              fontSize: _amountFontSize + 1,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSavingsNote() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('large_expenses')
          .where('userId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        _largeExpenses = docs
            .map((doc) => LargeExpenseModel.fromFirestore(doc))
            .toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 180.0, left: 16, right: 16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.green,
                ),
                title: const Text('毎月の収入設定'),
                subtitle: Text(
                  '月収: ¥${_formatCurrency(_monthlyIncome)}\n給料日: 毎月$_payday日',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _showIncomeDialog,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.blue,
                          ),
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
                        title: Text(expense.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '¥${_formatCurrency(expense.amount)}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.redAccent,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 20,
                                color: Colors.grey,
                              ),
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection('large_expenses')
                                    .doc(expense.id)
                                    .delete();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

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
            onPressed: () async {
              final newIncome = int.tryParse(incomeController.text) ?? 0;
              final newPayday = int.tryParse(paydayController.text) ?? 25;

              setState(() {
                _monthlyIncome = newIncome;
                _payday = newPayday;
              });

              if (currentUserId.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUserId)
                    .set({
                      'monthlyIncome': newIncome,
                      'payday': newPayday,
                    }, SetOptions(merge: true));
              }

              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

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
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  amountController.text.isNotEmpty &&
                  currentUserId.isNotEmpty) {
                final newExpense = LargeExpenseModel(
                  id: '',
                  userId: currentUserId,
                  name: nameController.text,
                  amount: int.tryParse(amountController.text) ?? 0,
                );
                await FirebaseFirestore.instance
                    .collection('large_expenses')
                    .add(newExpense.toMap());
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }
}
