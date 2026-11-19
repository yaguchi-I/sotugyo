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

  // 月を切り替えるたびに通信し直さないよう、ストリームは1回だけ作る
  late final Stream<QuerySnapshot> _recordsStream = FirebaseFirestore.instance
      .collection('money_record')
      .where('userId', isEqualTo: currentUserId)
      .snapshots();

  void _goPrevMonth() {
    setState(() {
      if (_selectedMonth > 1) {
        _selectedMonth--;
      } else {
        _selectedMonth = 12;
        _selectedYear--;
      }
    });
  }

  void _goNextMonth() {
    setState(() {
      if (_selectedMonth < 12) {
        _selectedMonth++;
      } else {
        _selectedMonth = 1;
        _selectedYear++;
      }
    });
  }

  /// 「カレンダー / 貯蓄ノート」の切り替えボタン1つ分
  Widget _buildViewToggle(String label, IconData icon, bool selected,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.blue : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? Colors.blue.shade800 : Colors.black54,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'メニュー',
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text('家計簿'),
        elevation: 0,
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
              // ---- 表示切り替え（iOS風のセグメント） ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildViewToggle(
                        'カレンダー',
                        Icons.calendar_month_outlined,
                        isCalendarView,
                        () => setState(() => isCalendarView = true),
                      ),
                      _buildViewToggle(
                        '貯蓄ノート',
                        Icons.savings_outlined,
                        !isCalendarView,
                        () => setState(() => isCalendarView = false),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _recordsStream,
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
                        : _buildSavingsNote(allRecords);
                  },
                ),
              ),
            ],
          ),
          // ---- 右下・左下のボタン（タブバーのすぐ上） ----
          if (isCalendarView)
            Positioned(
              left: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'camera_btn',
                onPressed: _scanReceiptAndInput,
                tooltip: 'レシートを読み取る',
                backgroundColor: Colors.white,
                shape: const CircleBorder(),
                child: const Icon(Icons.camera_alt, color: Colors.black87),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'ai_btn',
              onPressed: () {},
              tooltip: 'AIに相談',
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Text(
                'AI',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87,
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
        // ---- 月の切り替え ＋ 今月の合計（1枚のカードにまとめた） ----
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '前の月',
                onPressed: _goPrevMonth,
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedMonth,
                  isDense: true,
                  items: List.generate(12, (index) {
                    return DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                        '${index + 1}月',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedMonth = value);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '次の月',
                onPressed: _goNextMonth,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$_selectedYear年$_selectedMonth月の支出',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                  ),
                  Text(
                    '¥${_formatCurrency(monthlyTotal)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ---- 曜日 ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: weekDays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: w == '日'
                              ? Colors.red
                              : (w == '土' ? Colors.blue : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 6),

        // ---- カレンダー本体：画面の高さに合わせてマスの大きさを自動調整 ----
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double spacing = 4;
              const double sidePadding = 16;
              const double bottomSpace = 84; // 下のボタンと重ならない余白
              final rows = totalCells ~/ 7;

              final cellWidth =
                  (constraints.maxWidth - sidePadding * 2 - spacing * 6) / 7;
              final fitHeight =
                  (constraints.maxHeight - bottomSpace - spacing * (rows - 1)) /
                      rows;
              // 小さすぎる画面では最低56の高さを保ってスクロールさせる
              final cellHeight = fitHeight < 56 ? 56.0 : fitHeight;

              return GridView.builder(
                padding: const EdgeInsets.only(
                  left: sidePadding,
                  right: sidePadding,
                  bottom: bottomSpace,
                ),
                physics: fitHeight < 56
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: cellWidth / cellHeight,
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
                  final isToday = (now.year == year &&
                      now.month == month &&
                      now.day == day);
                  final weekday = index % 7; // 0=日 6=土

                  Color dayColor;
                  if (isToday) {
                    dayColor = Colors.white;
                  } else if (weekday == 0) {
                    dayColor = Colors.red.shade400;
                  } else if (weekday == 6) {
                    dayColor = Colors.blue.shade400;
                  } else {
                    dayColor = const Color(0xFF333333);
                  }
                  if (!isCurrentMonth) {
                    dayColor = dayColor.withValues(alpha: 0.35);
                  }

                  return GestureDetector(
                    onTap: () => _onDayTap(year, month, day, dayData),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrentMonth
                            ? (dayData.isNotEmpty
                                ? Colors.orange.shade50
                                : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isToday ? Colors.blue : Colors.grey.shade200,
                          width: isToday ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // 日付（今日は青い丸で囲む）
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: isToday
                                ? const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: dayColor,
                              ),
                            ),
                          ),
                          // その日の合計だけ表示（内訳はタップで見られる）
                          // 残りの高さに収まるよう自動で縮む
                          Expanded(
                            child: dayData.isEmpty
                                ? const SizedBox.shrink()
                                : Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '¥${_formatCurrency(totalAmount)}',
                                            style: TextStyle(
                                              fontSize: _amountFontSize - 1,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  Colors.deepOrange.shade700,
                                            ),
                                          ),
                                          if (dayData.length > 1)
                                            Text(
                                              '${dayData.length}件',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 貯蓄ノート用：大きな支出のストリームも1回だけ作る
  late final Stream<QuerySnapshot> _largeExpensesStream = FirebaseFirestore
      .instance
      .collection('large_expenses')
      .where('userId', isEqualTo: currentUserId)
      .snapshots();

  /// 今日から次の給料日までの日数
  int _daysUntilPayday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int clampDay(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return _payday > last ? last : (_payday < 1 ? 1 : _payday);
    }

    var next = DateTime(now.year, now.month, clampDay(now.year, now.month));
    if (next.isBefore(today)) {
      next = DateTime(now.year, now.month + 1,
          clampDay(now.year, now.month + 1));
    }
    return next.difference(today).inDays;
  }

  /// 予定日までの残り月数（今月なら1、過ぎていたら0）
  int _monthsUntil(DateTime due) {
    final now = DateTime.now();
    return (due.year - now.year) * 12 + (due.month - now.month) + 1;
  }

  /// 「毎月いくら積み立てればいいか」の目安（予定日が未設定なら null）
  int? _monthlySavingFor(LargeExpenseModel e) {
    if (e.dueDate == null) return null;
    final months = _monthsUntil(e.dueDate!);
    if (months <= 0) return null;
    return (e.amount / months).ceil();
  }

  String _dueLabel(DateTime? due) {
    if (due == null) return '時期未定';
    final months = _monthsUntil(due);
    final dateText = '${due.year}/${due.month}/${due.day}';
    if (months <= 0) return '$dateText（過ぎています）';
    if (months == 1) return '$dateText（今月）';
    return '$dateText（あと${months - 1}か月）';
  }

  Widget _buildSavingsNote(List<MoneyRecordModel> allRecords) {
    return StreamBuilder<QuerySnapshot>(
      stream: _largeExpensesStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        _largeExpenses = docs
            .map((doc) => LargeExpenseModel.fromFirestore(doc))
            .toList();

        // 予定日が近い順（未定は最後）
        _largeExpenses.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });

        // ---- 今月（実際のカレンダー上の今月）の支出 ----
        final now = DateTime.now();
        final monthPrefix =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-';
        final spentThisMonth = allRecords
            .where((r) => r.date.startsWith(monthPrefix))
            .fold<int>(0, (sum, r) => sum + r.amount);

        final remaining = _monthlyIncome - spentThisMonth;
        final monthlySavingTotal = _largeExpenses.fold<int>(
          0,
          (sum, e) => sum + (_monthlySavingFor(e) ?? 0),
        );
        final plannedTotal =
            _largeExpenses.fold<int>(0, (sum, e) => sum + e.amount);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            _buildForecastCard(
              month: now.month,
              spent: spentThisMonth,
              remaining: remaining,
              monthlySavingTotal: monthlySavingTotal,
            ),
            const SizedBox(height: 14),
            _buildIncomeCard(),
            const SizedBox(height: 14),
            _buildLargeExpenseCard(plannedTotal),
          ],
        );
      },
    );
  }

  // ===== ① 今月の見通し =====
  Widget _buildForecastCard({
    required int month,
    required int spent,
    required int remaining,
    required int monthlySavingTotal,
  }) {
    final hasIncome = _monthlyIncome > 0;
    final double ratio =
        hasIncome ? (spent / _monthlyIncome).clamp(0.0, 1.0).toDouble() : 0.0;
    final isOver = hasIncome && remaining < 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isOver ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.savings_outlined,
                size: 20,
                color: isOver ? Colors.red.shade700 : Colors.blue.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '$month月の見通し',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOver ? Colors.red.shade800 : Colors.blue.shade800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '給料日まであと${_daysUntilPayday()}日',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasIncome) ...[
            const Text(
              '収入を設定すると、今月あといくら残せそうかが分かります',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _showIncomeDialog,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('収入を設定する'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ] else ...[
            Text(
              isOver ? '今月は使いすぎています' : '今月あまりそうなお金',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              '¥${_formatCurrency(remaining)}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isOver ? Colors.red.shade700 : Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: Colors.white,
                color: ratio >= 0.9
                    ? Colors.red
                    : (ratio >= 0.7 ? Colors.orange : Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '使った額 ¥${_formatCurrency(spent)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
                const Spacer(),
                Text(
                  '収入 ¥${_formatCurrency(_monthlyIncome)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ],
            ),
          ],
          if (monthlySavingTotal > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, size: 18, color: Colors.teal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '大きな支出に向けた積立目安',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '毎月 ¥${_formatCurrency(monthlySavingTotal)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===== ② 収入 =====
  Widget _buildIncomeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: _showIncomeDialog,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Icon(Icons.payments_outlined, color: Colors.green.shade700),
        ),
        title: const Text('毎月の収入', style: TextStyle(fontSize: 13)),
        subtitle: Text(
          _monthlyIncome > 0
              ? '¥${_formatCurrency(_monthlyIncome)}　・　給料日 $_payday日'
              : '未設定',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, color: Colors.black45),
      ),
    );
  }

  // ===== ③ 大きな支出の予定 =====
  Widget _buildLargeExpenseCard(int plannedTotal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '大きな支出の予定',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_largeExpenses.isNotEmpty)
                Text(
                  '合計 ¥${_formatCurrency(plannedTotal)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_largeExpenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_note_outlined,
                        size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      '車検・旅行・家電の買い替えなど\n先の大きな出費を登録しておこう',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ..._largeExpenses.map(_buildLargeExpenseRow),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showLargeExpenseDialog,
              icon: const Icon(Icons.add),
              label: const Text('予定を追加'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeExpenseRow(LargeExpenseModel e) {
    final saving = _monthlySavingFor(e);
    final isPast = e.dueDate != null && _monthsUntil(e.dueDate!) <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: isPast ? Colors.red : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _dueLabel(e.dueDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: isPast ? Colors.red : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${_formatCurrency(e.amount)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (saving != null)
                Text(
                  '月 ¥${_formatCurrency(saving)}',
                  style: const TextStyle(fontSize: 11, color: Colors.teal),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.grey,
            tooltip: '削除',
            onPressed: () => _confirmDeleteLargeExpense(e),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLargeExpense(LargeExpenseModel e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${e.name}」を削除しますか？'),
        content: const Text('削除すると元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseFirestore.instance
        .collection('large_expenses')
        .doc(e.id)
        .delete();
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
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('大きな支出を追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:
                    const InputDecoration(labelText: '支出名 (例: 車検, 旅行)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '金額 (円)'),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: dueDate ?? DateTime(now.year, now.month + 1),
                    firstDate: DateTime(now.year, now.month, 1),
                    lastDate: DateTime(now.year + 5, 12, 31),
                  );
                  if (picked != null) {
                    setDialogState(() => dueDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '支払い予定日（任意）',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    dueDate == null
                        ? 'タップして選択'
                        : '${dueDate!.year}/${dueDate!.month}/${dueDate!.day}',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
                    dueDate: dueDate,
                  );
                  await FirebaseFirestore.instance
                      .collection('large_expenses')
                      .add(newExpense.toMap());
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }
}
