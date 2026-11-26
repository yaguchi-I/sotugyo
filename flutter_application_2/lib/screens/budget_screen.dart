import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/money_record_model.dart' show MoneyRecordModel;
import '../models/large_expense_model.dart' show LargeExpenseModel;
import 'ai_chat_screen.dart' show AiChatScreen;
import 'receipt_scanner_screen.dart' show ReceiptScannerScreen;
import '../widgets/top_toast.dart' show showTopToast;

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State {
  static const List _categories = [
    '食費',
    '日用品',
    '交通費',
    '交際費',
    '趣味',
    '雑費',
    'その他',
  ];

  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool isCalendarView = true;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  double _amountFontSize = 13.0;

  int _monthlyIncome = 0;
  int _payday = 25;
  List _latestRecords = [];
  Map _memoByDocId = {};
  List _largeExpenses = [];

  late final Stream _recordsStream = FirebaseFirestore.instance
      .collection('money_record')
      .where('userId', isEqualTo: currentUserId)
      .snapshots();

  late final Stream _largeExpensesStream = FirebaseFirestore.instance
      .collection('large_expenses')
      .where('userId', isEqualTo: currentUserId)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future _loadUserSettings() async {
    if (currentUserId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (doc.exists && doc.data() != null && mounted) {
        final data = doc.data()!;
        setState(() {
          _monthlyIncome = (data['monthlyIncome'] is num)
              ? (data['monthlyIncome'] as num).toInt()
              : (int.tryParse(data['monthlyIncome']?.toString() ?? '0') ?? 0);
          _payday = (data['payday'] is num)
              ? (data['payday'] as num).toInt()
              : (int.tryParse(data['payday']?.toString() ?? '25') ?? 25);
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

  void _onDayTap(int year, int month, int day, List dayExpenses) {
    if (dayExpenses.isEmpty) {
      _showInputModal(year, month, day);
    } else {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$month月$day日の操作'),
          content: const Text('行いたい操作を選んでください'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showInputModal(year, month, day);
              },
              child: const Text('新しく支出を追加'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showDetailAndEditModal(year, month, day, dayExpenses);
              },
              child: const Text('明細を確認・編集する'),
            ),
          ],
        ),
      );
    }
  }

  void _showDetailAndEditModal(int year, int month, int day, List expenses) {
    int total = 0;
    for (final raw in expenses) {
      total += (raw as MoneyRecordModel).amount;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$month月$day日の明細 (合計: ¥${_formatCurrency(total)})'),
        content: SizedBox(
          width: double.maxFinite,
          child: expenses.isEmpty
              ? const Text('登録されている明細はありません')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final item = expenses[index] as MoneyRecordModel;
                    final memo = (_memoByDocId[item.id] ?? '').toString();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          memo.isNotEmpty
                              ? '${item.category}（$memo）'
                              : 'カテゴリ: ${item.category}',
                        ),
                        subtitle: Text('金額: ¥${_formatCurrency(item.amount)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _showEditItemModal(item);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                Navigator.pop(dialogContext);
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
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
    final memoController = TextEditingController(
      text: (_memoByDocId[item.id] ?? '').toString(),
    );
    String selectedCategory = item.category;

    final dateParts = item.date.split('-');
    int targetYear = dateParts.isNotEmpty
        ? (int.tryParse(dateParts[0]) ?? DateTime.now().year)
        : DateTime.now().year;
    int targetMonth = dateParts.length > 1
        ? (int.tryParse(dateParts[1]) ?? DateTime.now().month)
        : DateTime.now().month;
    int targetDay = dateParts.length > 2
        ? (int.tryParse(dateParts[2]) ?? DateTime.now().day)
        : DateTime.now().day;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
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
                            context: ctx,
                            initialDate: DateTime(
                              targetYear,
                              targetMonth,
                              targetDay,
                            ),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: memoController,
                    decoration: const InputDecoration(
                      labelText: '詳細・メモ（任意）',
                      hintText: '例：スーパーで豚肉と卵、コンビニなど',
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
                    children: _categories.map((rawCategory) {
                      final category = rawCategory.toString();
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
                onPressed: () => Navigator.pop(dialogContext),
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
                          'memo': memoController.text.trim(),
                        });
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('更新する'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      controller.dispose();
      memoController.dispose();
    });
  }

  void _showInputModal(int year, int month, int day, {int? initialAmount}) {
    final List rows = [];
    if (initialAmount != null && initialAmount > 0) {
      rows.add({
        'category': '食費',
        'amountCtrl': TextEditingController(text: initialAmount.toString()),
        'memoCtrl': TextEditingController(),
        'focusNode': FocusNode(),
      });
    }
    bool isSaving = false;

    int calcValidCount() {
      int count = 0;
      for (final raw in rows) {
        final m = raw as Map;
        final amt =
            int.tryParse(
              (m['amountCtrl'] as TextEditingController).text
                  .replaceAll(',', '')
                  .trim(),
            ) ??
            0;
        if (amt > 0) count++;
      }
      return count;
    }

    int calcValidTotal() {
      int total = 0;
      for (final raw in rows) {
        final m = raw as Map;
        final amt =
            int.tryParse(
              (m['amountCtrl'] as TextEditingController).text
                  .replaceAll(',', '')
                  .trim(),
            ) ??
            0;
        if (amt > 0) total += amt;
      }
      return total;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void addRow(String category) {
            final focusNode = FocusNode();
            setDialogState(() {
              rows.add({
                'category': category,
                'amountCtrl': TextEditingController(),
                'memoCtrl': TextEditingController(),
                'focusNode': focusNode,
              });
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              focusNode.requestFocus();
            });
          }

          void removeRow(int index) {
            setDialogState(() {
              final removed = rows.removeAt(index) as Map;
              (removed['amountCtrl'] as TextEditingController).dispose();
              (removed['memoCtrl'] as TextEditingController).dispose();
              (removed['focusNode'] as FocusNode).dispose();
            });
          }

          final validCount = calcValidCount();
          final validTotal = calcValidTotal();
          final isWide = MediaQuery.of(ctx).size.width >= 560;

          return AlertDialog(
            title: Text('$month月$day日の支出追加'),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.58,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'タグをタップして項目を1個ずつ追加',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final rawCat in _categories)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              avatar: const Icon(
                                Icons.add,
                                size: 15,
                                color: Colors.blue,
                              ),
                              label: Text(
                                rawCat.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                              backgroundColor: Colors.blue.shade50,
                              side: BorderSide(color: Colors.blue.shade200),
                              onPressed: isSaving
                                  ? null
                                  : () => addRow(rawCat.toString()),
                            ),
                        ],
                      ),
                      const Divider(height: 20),
                      if (rows.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Text(
                            '上のカテゴリタグを押すと\nここに入力欄が1個ずつ増えます',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              height: 1.5,
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < rows.length; i++)
                          Builder(
                            builder: (_) {
                              final row = rows[i] as Map;
                              final selectedCat = row['category'].toString();
                              final ctrl =
                                  row['amountCtrl'] as TextEditingController;
                              final memoCtrl =
                                  row['memoCtrl'] as TextEditingController;
                              final focusNode = row['focusNode'] as FocusNode;

                              final categoryDropdown = Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton(
                                    value: selectedCat,
                                    isDense: true,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                    items: _categories.map((c) {
                                      final str = c.toString();
                                      return DropdownMenuItem(
                                        value: str,
                                        child: Text(str),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setDialogState(() {
                                          row['category'] = val.toString();
                                        });
                                      }
                                    },
                                  ),
                                ),
                              );

                              final amountField = TextField(
                                controller: ctrl,
                                focusNode: focusNode,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: const InputDecoration(
                                  hintText: '金額',
                                  prefixText: '¥ ',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              );

                              final memoField = TextField(
                                controller: memoCtrl,
                                decoration: const InputDecoration(
                                  hintText: '詳細・メモ（任意 例：スーパー、カフェ）',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              );

                              final deleteBtn = IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.redAccent,
                                  size: 22,
                                ),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.only(left: 6),
                                onPressed: isSaving ? null : () => removeRow(i),
                              );

                              if (isWide) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    children: [
                                      categoryDropdown,
                                      const SizedBox(width: 8),
                                      Expanded(flex: 2, child: amountField),
                                      const SizedBox(width: 8),
                                      Expanded(flex: 3, child: memoField),
                                      deleteBtn,
                                    ],
                                  ),
                                );
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8.0),
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        categoryDropdown,
                                        const SizedBox(width: 8),
                                        Expanded(child: amountField),
                                        deleteBtn,
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    memoField,
                                  ],
                                ),
                              );
                            },
                          ),
                      if (validCount > 0) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '合計 $validCount件 / ¥${_formatCurrency(validTotal)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: isSaving || validCount == 0
                    ? null
                    : () async {
                        if (currentUserId.isEmpty) return;
                        setDialogState(() => isSaving = true);
                        final dateStr = _getDateKey(year, month, day);
                        try {
                          final batch = FirebaseFirestore.instance.batch();
                          final col = FirebaseFirestore.instance.collection(
                            'money_record',
                          );
                          int savedCount = 0;
                          int savedTotal = 0;

                          for (final raw in rows) {
                            final m = raw as Map;
                            final amt =
                                int.tryParse(
                                  (m['amountCtrl'] as TextEditingController)
                                      .text
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                0;
                            final memo =
                                (m['memoCtrl'] as TextEditingController).text
                                    .trim();
                            if (amt > 0) {
                              savedCount++;
                              savedTotal += amt;
                              final newRecord = MoneyRecordModel(
                                id: '',
                                userId: currentUserId,
                                amount: amt,
                                category: m['category'].toString(),
                                date: dateStr,
                              );
                              final Map<String, dynamic> data =
                                  Map<String, dynamic>.from(newRecord.toMap());
                              if (memo.isNotEmpty) {
                                data['memo'] = memo;
                              }
                              batch.set(col.doc(), data);
                            }
                          }

                          if (savedCount > 0) {
                            await batch.commit();
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted && savedCount > 0) {
                            showTopToast(
                              context,
                              '$savedCount件（合計 ¥${_formatCurrency(savedTotal)}）を記録しました',
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                        }
                      },
                child: Text(validCount > 1 ? '$validCount件を記録する' : '記録する'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      for (final raw in rows) {
        final m = raw as Map;
        (m['amountCtrl'] as TextEditingController).dispose();
        (m['memoCtrl'] as TextEditingController).dispose();
        (m['focusNode'] as FocusNode).dispose();
      }
    });
  }

  Future _openReceiptScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScannerScreen(
          initialYear: _selectedYear,
          initialMonth: _selectedMonth,
        ),
      ),
    );

    if (!mounted) return;
    if (result is Map && result['saved'] == true) {
      final dateStr = (result['date'] ?? '').toString();
      final parts = dateStr.split('-');
      if (parts.length >= 2) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y != null && m != null && m >= 1 && m <= 12) {
          setState(() {
            _selectedYear = y;
            _selectedMonth = m;
          });
        }
      }
    }
  }

  void _openAiBudgetAssistant({int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetAiAssistantSheet(
        currentUserId: currentUserId,
        monthlyIncome: _monthlyIncome,
        payday: _payday,
        selectedYear: _selectedYear,
        selectedMonth: _selectedMonth,
        allRecords: List.from(_latestRecords),
        memoByDocId: Map.from(_memoByDocId),
        largeExpenses: List.from(_largeExpenses),
        initialTab: initialTab,
        onSavedDate: (year, month) {
          if (mounted) {
            setState(() {
              _selectedYear = year;
              _selectedMonth = month;
            });
          }
        },
      ),
    );
  }

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

  Widget _buildViewToggle(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
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
          PopupMenuButton(
            icon: const Icon(Icons.text_format),
            tooltip: '文字サイズ変更',
            onSelected: (size) {
              if (size is num) {
                setState(() {
                  _amountFontSize = size.toDouble();
                });
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 11.0, child: Text('小')),
              PopupMenuItem(value: 13.0, child: Text('中（標準）')),
              PopupMenuItem(value: 16.0, child: Text('大')),
            ],
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _recordsStream,
        builder: (context, recordSnap) {
          final recordDocs = recordSnap.hasData && recordSnap.data != null
              ? (recordSnap.data as QuerySnapshot).docs
              : const [];
          final List allRecords = [];
          final Map memoMap = {};
          for (final doc in recordDocs) {
            allRecords.add(MoneyRecordModel.fromFirestore(doc));
            final rawData = doc.data();
            if (rawData is Map && rawData['memo'] != null) {
              final m = rawData['memo'].toString().trim();
              if (m.isNotEmpty) {
                memoMap[doc.id] = m;
              }
            }
          }
          _latestRecords = allRecords;
          _memoByDocId = memoMap;

          return StreamBuilder(
            stream: _largeExpensesStream,
            builder: (context, largeSnap) {
              final largeDocs = largeSnap.hasData && largeSnap.data != null
                  ? (largeSnap.data as QuerySnapshot).docs
                  : const [];
              final List loadedLarge = largeDocs
                  .map((doc) => LargeExpenseModel.fromFirestore(doc))
                  .toList();
              loadedLarge.sort((a, b) {
                final ea = a as LargeExpenseModel;
                final eb = b as LargeExpenseModel;
                if (ea.dueDate == null && eb.dueDate == null) return 0;
                if (ea.dueDate == null) return 1;
                if (eb.dueDate == null) return -1;
                return ea.dueDate!.compareTo(eb.dueDate!);
              });
              _largeExpenses = loadedLarge;

              return Stack(
                children: [
                  Column(
                    children: [
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
                        child:
                            recordSnap.connectionState ==
                                ConnectionState.waiting
                            ? const Center(child: CircularProgressIndicator())
                            : (isCalendarView
                                  ? _buildCalendar(allRecords)
                                  : _buildSavingsNote(allRecords)),
                      ),
                    ],
                  ),
                  if (isCalendarView)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: FloatingActionButton(
                        heroTag: 'camera_btn',
                        onPressed: _openReceiptScanner,
                        tooltip: 'AIレシート読み取り',
                        backgroundColor: Colors.white,
                        shape: const CircleBorder(),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      heroTag: 'ai_btn',
                      onPressed: () => _openAiBudgetAssistant(
                        initialTab: isCalendarView ? 0 : 1,
                      ),
                      tooltip: 'AI家計簿アシスタント',
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, size: 18),
                          Text(
                            'AI',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              height: 1.0,
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
        },
      ),
    );
  }

  Widget _buildCalendar(List allRecords) {
    final Map dailyMap = {};
    for (final rawTx in allRecords) {
      final tx = rawTx as MoneyRecordModel;
      if (dailyMap[tx.date] == null) {
        dailyMap[tx.date] = [];
      }
      (dailyMap[tx.date] as List).add(tx);
    }

    int monthlyTotal = 0;
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      final key = _getDateKey(_selectedYear, _selectedMonth, day);
      final List dayData = (dailyMap[key] as List?) ?? [];
      for (final rawItem in dayData) {
        monthlyTotal += (rawItem as MoneyRecordModel).amount;
      }
    }

    final firstDayOfWeek = DateTime(_selectedYear, _selectedMonth, 1).weekday;
    final leadingSpaces = firstDayOfWeek % 7;
    final totalDaysNeeded = leadingSpaces + daysInMonth;
    final totalCells = totalDaysNeeded <= 35 ? 35 : 42;

    const weekDays = ['日', '月', '火', '水', '木', '金', '土'];
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
                child: DropdownButton(
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
                    if (value is int) {
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double spacing = 4;
              const double sidePadding = 16;
              const double bottomSpace = 84;
              final rows = totalCells ~/ 7;

              final cellWidth =
                  (constraints.maxWidth - sidePadding * 2 - spacing * 6) / 7;
              final fitHeight =
                  (constraints.maxHeight - bottomSpace - spacing * (rows - 1)) /
                  rows;
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
                  final List dayData = (dailyMap[key] as List?) ?? [];
                  int totalAmount = 0;
                  for (final rawItem in dayData) {
                    totalAmount += (rawItem as MoneyRecordModel).amount;
                  }
                  final isToday =
                      (now.year == year &&
                      now.month == month &&
                      now.day == day);
                  final weekday = index % 7;

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
                                              color: Colors.deepOrange.shade700,
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

  int _daysUntilPayday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int clampDay(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return _payday > last ? last : (_payday < 1 ? 1 : _payday);
    }

    var next = DateTime(now.year, now.month, clampDay(now.year, now.month));
    if (next.isBefore(today)) {
      next = DateTime(
        now.year,
        now.month + 1,
        clampDay(now.year, now.month + 1),
      );
    }
    return next.difference(today).inDays;
  }

  int _monthsUntil(DateTime due) {
    final now = DateTime.now();
    return (due.year - now.year) * 12 + (due.month - now.month) + 1;
  }

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

  Widget _buildSavingsNote(List allRecords) {
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}-';
    int spentThisMonth = 0;
    for (final raw in allRecords) {
      final r = raw as MoneyRecordModel;
      if (r.date.startsWith(monthPrefix)) {
        spentThisMonth += r.amount;
      }
    }

    final remaining = _monthlyIncome - spentThisMonth;
    int monthlySavingTotal = 0;
    int plannedTotal = 0;
    for (final raw in _largeExpenses) {
      final e = raw as LargeExpenseModel;
      monthlySavingTotal += _monthlySavingFor(e) ?? 0;
      plannedTotal += e.amount;
    }

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
  }

  Widget _buildForecastCard({
    required int month,
    required int spent,
    required int remaining,
    required int monthlySavingTotal,
  }) {
    final hasIncome = _monthlyIncome > 0;
    final double ratio = hasIncome
        ? (spent / _monthlyIncome).clamp(0.0, 1.0).toDouble()
        : 0.0;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openAiBudgetAssistant(initialTab: 1),
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('AIで今月の貯金・使いすぎを診断する'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
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
              ? '¥${_formatCurrency(_monthlyIncome)} ・ 給料日 $_payday日'
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
                    Icon(
                      Icons.event_note_outlined,
                      size: 40,
                      color: Colors.grey.shade300,
                    ),
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
          for (final rawE in _largeExpenses)
            _buildLargeExpenseRow(rawE as LargeExpenseModel),
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

  Future _confirmDeleteLargeExpense(LargeExpenseModel e) async {
    final ok = await showDialog(
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
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
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

              if (dialogContext.mounted) Navigator.pop(dialogContext);
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
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('大きな支出を追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '支出名 (例: 車検, 旅行)'),
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
                    context: ctx,
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

class _BudgetAiAssistantSheet extends StatefulWidget {
  final String currentUserId;
  final int monthlyIncome;
  final int payday;
  final int selectedYear;
  final int selectedMonth;
  final List allRecords;
  final Map memoByDocId;
  final List largeExpenses;
  final int initialTab;
  final void Function(int year, int month) onSavedDate;

  const _BudgetAiAssistantSheet({
    required this.currentUserId,
    required this.monthlyIncome,
    required this.payday,
    required this.selectedYear,
    required this.selectedMonth,
    required this.allRecords,
    required this.memoByDocId,
    required this.largeExpenses,
    required this.initialTab,
    required this.onSavedDate,
  });

  @override
  State createState() => _BudgetAiAssistantSheetState();
}

class _BudgetAiAssistantSheetState extends State {
  _BudgetAiAssistantSheet get _w => widget as _BudgetAiAssistantSheet;

  static const List _categories = [
    '食費',
    '日用品',
    '交通費',
    '交際費',
    '趣味',
    '雑費',
    'その他',
  ];

  late int _activeTab;

  final TextEditingController _inputPromptCtrl = TextEditingController();
  final List _draftRecords = [];
  final List _draftLargeExpenses = [];
  bool _isExtracting = false;
  bool _isSavingDrafts = false;
  String _extractNotice = '';

  final TextEditingController _analysisQuestionCtrl = TextEditingController();
  bool _isAnalyzing = false;
  String _analysisReply = '';

  @override
  void initState() {
    super.initState();
    _activeTab = _w.initialTab;
  }

  @override
  void dispose() {
    _inputPromptCtrl.dispose();
    _analysisQuestionCtrl.dispose();
    _disposeDraftControllers();
    super.dispose();
  }

  void _disposeDraftControllers() {
    for (final raw in _draftRecords) {
      final m = raw as Map;
      (m['amountCtrl'] as TextEditingController).dispose();
      (m['memoCtrl'] as TextEditingController).dispose();
      (m['focusNode'] as FocusNode).dispose();
    }
    for (final raw in _draftLargeExpenses) {
      final m = raw as Map;
      (m['nameCtrl'] as TextEditingController).dispose();
      (m['amountCtrl'] as TextEditingController).dispose();
      (m['focusNode'] as FocusNode).dispose();
    }
    _draftRecords.clear();
    _draftLargeExpenses.clear();
  }

  DateTime _defaultEntryDate() {
    final now = DateTime.now();
    if (_w.selectedYear == now.year && _w.selectedMonth == now.month) {
      return DateTime(now.year, now.month, now.day);
    }
    final maxDay = DateTime(_w.selectedYear, _w.selectedMonth + 1, 0).day;
    final d = now.day > maxDay ? maxDay : now.day;
    return DateTime(_w.selectedYear, _w.selectedMonth, d);
  }

  void _addDraftRecordRow(String category) {
    final focusNode = FocusNode();
    setState(() {
      _draftRecords.add({
        'date': _defaultEntryDate(),
        'category': category,
        'amountCtrl': TextEditingController(),
        'memoCtrl': TextEditingController(),
        'focusNode': focusNode,
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });
  }

  void _addDraftLargeExpenseRow() {
    final focusNode = FocusNode();
    setState(() {
      _draftLargeExpenses.add({
        'nameCtrl': TextEditingController(),
        'amountCtrl': TextEditingController(),
        'dueDate': null,
        'focusNode': focusNode,
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });
  }

  int _countValidDrafts() {
    int count = 0;
    for (final raw in _draftRecords) {
      final m = raw as Map;
      final amt =
          int.tryParse(
            (m['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (amt > 0) count++;
    }
    for (final raw in _draftLargeExpenses) {
      final m = raw as Map;
      final name = (m['nameCtrl'] as TextEditingController).text.trim();
      final amt =
          int.tryParse(
            (m['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (name.isNotEmpty && amt > 0) count++;
    }
    return count;
  }

  int _sumValidDraftRecords() {
    int total = 0;
    for (final raw in _draftRecords) {
      final m = raw as Map;
      final amt =
          int.tryParse(
            (m['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (amt > 0) total += amt;
    }
    return total;
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
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

  DateTime? _parseDate(String raw) {
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

  int _daysUntilPayday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int clampDay(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return _w.payday > last ? last : (_w.payday < 1 ? 1 : _w.payday);
    }

    var next = DateTime(now.year, now.month, clampDay(now.year, now.month));
    if (next.isBefore(today)) {
      next = DateTime(
        now.year,
        now.month + 1,
        clampDay(now.year, now.month + 1),
      );
    }
    final diff = next.difference(today).inDays;
    return diff <= 0 ? 1 : diff;
  }

  Map _buildBudgetSummary() {
    final now = DateTime.now();
    final currentPrefix =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-';
    final prevMonthDate = DateTime(now.year, now.month - 1, 1);
    final prevPrefix =
        '${prevMonthDate.year}-${prevMonthDate.month.toString().padLeft(2, '0')}-';

    int currentSpent = 0;
    int prevSpent = 0;
    final Map currentByCategory = {};
    final Map prevByCategory = {};
    final List currentDetails = [];

    for (final raw in _w.allRecords) {
      final r = raw as MoneyRecordModel;
      if (r.date.startsWith(currentPrefix)) {
        currentSpent += r.amount;
        currentByCategory[r.category] =
            ((currentByCategory[r.category] as int?) ?? 0) + r.amount;
        final memo = (_w.memoByDocId[r.id] ?? '').toString();
        currentDetails.add(
          memo.isNotEmpty
              ? '${r.date} ${r.category} ${r.amount}円 ($memo)'
              : '${r.date} ${r.category} ${r.amount}円',
        );
      } else if (r.date.startsWith(prevPrefix)) {
        prevSpent += r.amount;
        prevByCategory[r.category] =
            ((prevByCategory[r.category] as int?) ?? 0) + r.amount;
      }
    }

    currentDetails.sort();

    int monthlySavingRequired = 0;
    int largeExpenseTotal = 0;
    final List largeSummaryLines = [];

    for (final raw in _w.largeExpenses) {
      final e = raw as LargeExpenseModel;
      largeExpenseTotal += e.amount;
      String dueStr = '時期未定';
      if (e.dueDate != null) {
        final months =
            (e.dueDate!.year - now.year) * 12 +
            (e.dueDate!.month - now.month) +
            1;
        dueStr = '${e.dueDate!.year}/${e.dueDate!.month}/${e.dueDate!.day}';
        if (months > 0) {
          monthlySavingRequired += (e.amount / months).ceil();
        }
      }
      largeSummaryLines.add('${e.name}: ${e.amount}円 ($dueStr)');
    }

    final int daysLeft = _daysUntilPayday();
    final int remaining = _w.monthlyIncome > 0
        ? _w.monthlyIncome - currentSpent
        : 0;
    final int usableAfterSaving = _w.monthlyIncome > 0
        ? remaining - monthlySavingRequired
        : 0;
    final int dailyAllowance = (_w.monthlyIncome > 0 && remaining > 0)
        ? (remaining / daysLeft).floor()
        : 0;

    return {
      'year': now.year,
      'month': now.month,
      'currentSpent': currentSpent,
      'prevSpent': prevSpent,
      'currentByCategory': currentByCategory,
      'prevByCategory': prevByCategory,
      'currentDetails': currentDetails,
      'monthlyIncome': _w.monthlyIncome,
      'remaining': remaining,
      'daysLeft': daysLeft,
      'dailyAllowance': dailyAllowance,
      'monthlySavingRequired': monthlySavingRequired,
      'usableAfterSaving': usableAfterSaving,
      'largeExpenseTotal': largeExpenseTotal,
      'largeSummaryLines': largeSummaryLines,
    };
  }

  Future _extractEntriesFromText() async {
    final text = _inputPromptCtrl.text.trim();
    if (text.isEmpty || _isExtracting) return;

    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      setState(() {
        _extractNotice = 'ai_chat_screen.dart にAPIキーを設定してください。';
      });
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractNotice = 'AIが文章から金額・日付・カテゴリを抽出しています...';
    });

    final now = DateTime.now();
    final todayKey = _formatDateKey(now);
    final prompt =
        'あなたは日本の家計簿アプリの自然文入力パーサーです。\n'
        '基準日（今日）は $todayKey です。\n'
        'ユーザーの文章から「日々の支出（records）」と「今後の大きな支出予定（largeExpenses）」をすべて抽出し、JSON形式のみで出力してください。\n\n'
        '【使用可能カテゴリ（records用・この7つ以外は使わないこと）】\n'
        '食費, 日用品, 交通費, 交際費, 趣味, 雑費, その他\n\n'
        '【抽出ルール】\n'
        '1. 「昨日」「一昨日」「3日前」などの相対表現は基準日 $todayKey から正確に YYYY-MM-DD に変換すること。日付指定がなければ $todayKey。\n'
        '2. 「大きな予定」「来月の車検に8万円」「12月に旅行3万円予定」のような将来の大きな出費予定は largeExpenses に入れること。\n'
        '3. すでに使った買い物はすべて records に入れ、カテゴリ別に分けること。\n\n'
        '【ユーザー入力】\n$text\n\n'
        '【出力JSONフォーマット（説明文なし・JSONのみ）】\n'
        '{\n'
        '  "records": [{"date": "YYYY-MM-DD", "category": "食費", "amount": 680, "memo": "豚肉と卵"}],\n'
        '  "largeExpenses": [{"name": "旅行", "amount": 30000, "dueDate": "YYYY-MM-DD"}]\n'
        '}';

    Map? parsed;
    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
          generationConfig: GenerationConfig(temperature: 0.0),
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 20));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          parsed = _extractJsonObject(res.text!);
          if (parsed != null) break;
        }
      } catch (e) {}
    }

    if (!mounted) return;

    if (parsed == null) {
      setState(() {
        _isExtracting = false;
        _extractNotice = '抽出に失敗しました。金額と内容を含めてもう一度お試しください。';
      });
      return;
    }

    final List rawRecords = parsed['records'] is List
        ? List.from(parsed['records'])
        : [];
    final List rawLarge = parsed['largeExpenses'] is List
        ? List.from(parsed['largeExpenses'])
        : [];

    int addedCount = 0;

    setState(() {
      for (final item in rawRecords) {
        if (item is! Map) continue;
        final amt =
            int.tryParse(
              (item['amount'] ?? '0').toString().replaceAll(',', ''),
            ) ??
            0;
        if (amt <= 0) continue;
        final dt = _parseDate((item['date'] ?? '').toString()) ?? now;
        _draftRecords.add({
          'date': dt,
          'category': _normalizeCategory((item['category'] ?? '食費').toString()),
          'amountCtrl': TextEditingController(text: amt.toString()),
          'memoCtrl': TextEditingController(
            text: (item['memo'] ?? '').toString().trim(),
          ),
          'focusNode': FocusNode(),
        });
        addedCount++;
      }

      for (final item in rawLarge) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().trim();
        final amt =
            int.tryParse(
              (item['amount'] ?? '0').toString().replaceAll(',', ''),
            ) ??
            0;
        if (name.isEmpty || amt <= 0) continue;
        final due = _parseDate((item['dueDate'] ?? '').toString());
        _draftLargeExpenses.add({
          'nameCtrl': TextEditingController(text: name),
          'amountCtrl': TextEditingController(text: amt.toString()),
          'dueDate': due,
          'focusNode': FocusNode(),
        });
        addedCount++;
      }

      if (addedCount > 0) {
        _inputPromptCtrl.clear();
      }
      _isExtracting = false;
      _extractNotice = addedCount == 0
          ? '登録できる金額が見つかりませんでした。タグから追加するか金額を含めて入力してください。'
          : 'AIが$addedCount件をリストに追加しました！内容を確認して登録してください。';
    });
  }

  Future _saveExtractedDrafts() async {
    if (_isSavingDrafts) return;
    if (_w.currentUserId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登録するにはログインが必要です')));
      return;
    }

    final List validRecordMaps = [];
    final List validLarge = [];
    DateTime? latestRecordDate;

    for (final raw in _draftRecords) {
      final m = raw as Map;
      final amt =
          int.tryParse(
            (m['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      final memo = (m['memoCtrl'] as TextEditingController).text.trim();
      if (amt > 0) {
        final dt = m['date'] as DateTime;
        latestRecordDate = dt;
        final rec = MoneyRecordModel(
          id: '',
          userId: _w.currentUserId,
          amount: amt,
          category: m['category'].toString(),
          date: _formatDateKey(dt),
        );
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          rec.toMap(),
        );
        if (memo.isNotEmpty) {
          data['memo'] = memo;
        }
        validRecordMaps.add(data);
      }
    }

    for (final raw in _draftLargeExpenses) {
      final m = raw as Map;
      final name = (m['nameCtrl'] as TextEditingController).text.trim();
      final amt =
          int.tryParse(
            (m['amountCtrl'] as TextEditingController).text
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      if (name.isNotEmpty && amt > 0) {
        validLarge.add(
          LargeExpenseModel(
            id: '',
            userId: _w.currentUserId,
            name: name,
            amount: amt,
            dueDate: m['dueDate'] as DateTime?,
          ),
        );
      }
    }

    final totalCount = validRecordMaps.length + validLarge.length;
    if (totalCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登録できる明細がありません')));
      return;
    }

    setState(() {
      _isSavingDrafts = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final recordCol = FirebaseFirestore.instance.collection('money_record');
      final largeCol = FirebaseFirestore.instance.collection('large_expenses');

      for (final data in validRecordMaps) {
        batch.set(recordCol.doc(), data as Map<String, dynamic>);
      }
      for (final exp in validLarge) {
        batch.set(largeCol.doc(), (exp as LargeExpenseModel).toMap());
      }

      await batch.commit();

      if (latestRecordDate != null) {
        _w.onSavedDate(latestRecordDate.year, latestRecordDate.month);
      }

      if (!mounted) return;
      Navigator.pop(context);
      showTopToast(context, '$totalCount件を家計簿に登録しました');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSavingDrafts = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
    }
  }

  Future _runBudgetAnalysis([String? presetQuestion]) async {
    final question = (presetQuestion ?? _analysisQuestionCtrl.text).trim();
    if (question.isEmpty || _isAnalyzing) return;
    if (presetQuestion != null) {
      _analysisQuestionCtrl.text = presetQuestion;
    }

    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) {
      setState(() {
        _analysisReply = 'ai_chat_screen.dart にAPIキーを設定してください。';
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisReply = '';
    });

    final summary = _buildBudgetSummary();
    final Map curCats = summary['currentByCategory'] as Map;
    final Map prevCats = summary['prevByCategory'] as Map;
    final List details = summary['currentDetails'] as List;
    final List largeLines = summary['largeSummaryLines'] as List;

    final curCatText = curCats.isEmpty
        ? '記録なし'
        : curCats.entries.map((e) => '${e.key}: ${e.value}円').join(' / ');
    final prevCatText = prevCats.isEmpty
        ? '記録なし'
        : prevCats.entries.map((e) => '${e.key}: ${e.value}円').join(' / ');
    final recentText = details.isEmpty
        ? '記録なし'
        : details.reversed.take(25).join('\n');
    final largeText = largeLines.isEmpty ? '登録なし' : largeLines.join(' / ');

    final prompt =
        'あなたは一人暮らし向けの現実的で頼れるAI家計簿アドバイザーです。\n'
        '以下の実際の家計簿データから必要な数値を正確に抽出し、ユーザーの質問へ分かりやすく具体的に答えてください。\n\n'
        '【家計簿データ（${summary['year']}年${summary['month']}月）】\n'
        '・毎月の収入設定: ${summary['monthlyIncome']}円（0円は未設定）\n'
        '・今月の支出合計: ${summary['currentSpent']}円\n'
        '・先月の支出合計: ${summary['prevSpent']}円\n'
        '・今月の残り予算（収入−支出）: ${summary['remaining']}円\n'
        '・給料日までの残り日数: あと${summary['daysLeft']}日（1日あたり使える目安: ${summary['dailyAllowance']}円）\n'
        '・今月のカテゴリ別支出: $curCatText\n'
        '・先月のカテゴリ別支出: $prevCatText\n'
        '・大きな支出の予定: $largeText（必要な月積立目安: 毎月${summary['monthlySavingRequired']}円）\n'
        '・今月の明細一覧（最新25件）:\n$recentText\n\n'
        '【ユーザーの質問】\n$question\n\n'
        '【回答ルール】\n'
        '・データにある数字をそのまま正確に引用して答えること（存在しない出費は捏造しない）。\n'
        '・硬い教科書調は避け、親しみやすく具体的な改善アクションまで300文字前後でまとめること。\n'
        '・Markdown記号（** や ##）は使わないこと。';

    String reply = '分析結果を取得できませんでした。少し待ってからもう一度お試しください。';
    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
          generationConfig: GenerationConfig(temperature: 0.4),
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 22));
        if (res.text != null && res.text!.trim().isNotEmpty) {
          reply = res.text!.replaceAll('**', '').replaceAll('##', '').trim();
          break;
        }
      } catch (e) {}
    }

    if (!mounted) return;
    setState(() {
      _isAnalyzing = false;
      _analysisReply = reply;
    });
  }

  void _openAiChatWithRemainingBudget() {
    final summary = _buildBudgetSummary();
    final int income = summary['monthlyIncome'] as int;
    final int remaining = summary['remaining'] as int;
    final int daysLeft = summary['daysLeft'] as int;
    final int daily = summary['dailyAllowance'] as int;
    final Map curCats = summary['currentByCategory'] as Map;
    final int foodSpent = (curCats['食費'] as int?) ?? 0;

    final String prompt = income > 0
        ? '今月の家計簿で、給料日まであと$daysLeft日、残り予算は${_formatCurrency(remaining)}円（1日あたり約${_formatCurrency(daily)}円、今月の食費はすでに${_formatCurrency(foodSpent)}円）です。この予算内で乗り切れる節約レシピを提案して！'
        : '今月の食費が${_formatCurrency(foodSpent)}円、給料日まであと$daysLeft日です。ここから食費を抑えて乗り切れるコスパ最強の節約レシピを教えて！';

    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(builder: (_) => AiChatScreen(initialPrompt: prompt)),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final selected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
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
                size: 17,
                color: selected ? Colors.blue.shade700 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.blue.shade800 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoInputTab(ScrollController scrollCtrl) {
    final validCount = _countValidDrafts();
    final recordSum = _sumValidDraftRecords();
    final isWide = MediaQuery.of(context).size.width >= 560;

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        const Text(
          'タグをタップして1個ずつ追加（金額・詳細入力）',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final rawCat in _categories)
              ActionChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: const Icon(Icons.add, size: 15, color: Colors.blue),
                label: Text(
                  rawCat.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
                onPressed: _isSavingDrafts
                    ? null
                    : () => _addDraftRecordRow(rawCat.toString()),
              ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: const Icon(Icons.add, size: 15, color: Colors.teal),
              label: Text(
                '大きな予定',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade900,
                ),
              ),
              backgroundColor: Colors.teal.shade50,
              side: BorderSide(color: Colors.teal.shade200),
              onPressed: _isSavingDrafts ? null : _addDraftLargeExpenseRow,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '文章からAIでまとめて追加',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputPromptCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '例：昨日スーパー680円と日用品420円',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _extractEntriesFromText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isExtracting ? null : _extractEntriesFromText,
                    icon: _isExtracting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('AI抽出'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_extractNotice.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _extractNotice,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (_draftRecords.isEmpty && _draftLargeExpenses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text(
              '上のタグをタップするか、文章をAI抽出すると\nここに項目が1個ずつ追加されます',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
            ),
          ),
        if (_draftRecords.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '支出リスト（${_draftRecords.length}件）',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (recordSum > 0)
                Text(
                  '小計 ¥${_formatCurrency(recordSum)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < _draftRecords.length; i++)
            Builder(
              builder: (_) {
                final item = _draftRecords[i] as Map;
                final dt = item['date'] as DateTime;
                final ctrl = item['amountCtrl'] as TextEditingController;
                final memoCtrl = item['memoCtrl'] as TextEditingController;
                final focusNode = item['focusNode'] as FocusNode;
                final selectedCat = item['category'].toString();

                final dateChip = InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => item['date'] = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${dt.month}/${dt.day}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );

                final catDropdown = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton(
                      value: selectedCat,
                      isDense: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                      items: _categories.map((c) {
                        final str = c.toString();
                        return DropdownMenuItem(value: str, child: Text(str));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            item['category'] = val.toString();
                          });
                        }
                      },
                    ),
                  ),
                );

                final amountField = TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '金額',
                    prefixText: '¥ ',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                );

                final memoField = TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(
                    hintText: '詳細・メモ（任意）',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                );

                final removeBtn = IconButton(
                  icon: const Icon(
                    Icons.remove_circle,
                    size: 21,
                    color: Colors.redAccent,
                  ),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.only(left: 6),
                  onPressed: () {
                    setState(() {
                      final removed = _draftRecords.removeAt(i) as Map;
                      (removed['amountCtrl'] as TextEditingController)
                          .dispose();
                      (removed['memoCtrl'] as TextEditingController).dispose();
                      (removed['focusNode'] as FocusNode).dispose();
                    });
                  },
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: isWide
                      ? Row(
                          children: [
                            dateChip,
                            const SizedBox(width: 6),
                            catDropdown,
                            const SizedBox(width: 6),
                            Expanded(flex: 2, child: amountField),
                            const SizedBox(width: 6),
                            Expanded(flex: 3, child: memoField),
                            removeBtn,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                dateChip,
                                const SizedBox(width: 6),
                                catDropdown,
                                const SizedBox(width: 6),
                                Expanded(child: amountField),
                                removeBtn,
                              ],
                            ),
                            const SizedBox(height: 6),
                            memoField,
                          ],
                        ),
                );
              },
            ),
        ],
        if (_draftLargeExpenses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '大きな支出の予定（${_draftLargeExpenses.length}件）',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < _draftLargeExpenses.length; i++)
            Builder(
              builder: (_) {
                final item = _draftLargeExpenses[i] as Map;
                final nameCtrl = item['nameCtrl'] as TextEditingController;
                final amountCtrl = item['amountCtrl'] as TextEditingController;
                final focusNode = item['focusNode'] as FocusNode;
                final due = item['dueDate'] as DateTime?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nameCtrl,
                              focusNode: focusNode,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '予定名（例：旅行）',
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 108,
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '金額',
                                prefixText: '¥',
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle,
                              size: 21,
                              color: Colors.redAccent,
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.only(left: 6),
                            onPressed: () {
                              setState(() {
                                final removed =
                                    _draftLargeExpenses.removeAt(i) as Map;
                                (removed['nameCtrl'] as TextEditingController)
                                    .dispose();
                                (removed['amountCtrl'] as TextEditingController)
                                    .dispose();
                                (removed['focusNode'] as FocusNode).dispose();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  due ?? DateTime(now.year, now.month + 1),
                              firstDate: DateTime(now.year, now.month, 1),
                              lastDate: DateTime(now.year + 5, 12, 31),
                            );
                            if (picked != null) {
                              setState(() => item['dueDate'] = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined, size: 14),
                          label: Text(
                            due == null
                                ? '予定日を選択（任意）'
                                : '予定日: ${due.year}/${due.month}/${due.day}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
        if (_draftRecords.isNotEmpty || _draftLargeExpenses.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isSavingDrafts || validCount == 0
                  ? null
                  : _saveExtractedDrafts,
              icon: _isSavingDrafts
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
                'まとめて家計簿に登録する（$validCount件）',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnalysisTab(ScrollController scrollCtrl) {
    final summary = _buildBudgetSummary();
    final int currentSpent = summary['currentSpent'] as int;
    final int prevSpent = summary['prevSpent'] as int;
    final int income = summary['monthlyIncome'] as int;
    final int remaining = summary['remaining'] as int;
    final int daysLeft = summary['daysLeft'] as int;
    final int daily = summary['dailyAllowance'] as int;
    final int monthlySaving = summary['monthlySavingRequired'] as int;
    final Map curCats = summary['currentByCategory'] as Map;

    final List sortedCats = curCats.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    const quickQuestions = [
      {
        'label': '📊 今月の貯金・使いすぎ診断',
        'q': '今月の支出状況と収入・大きな予定を踏まえて、貯金見込みと使いすぎているポイントを診断して！',
      },
      {'label': '🔍 先月より増えた費目を抽出', 'q': '先月と比べて増えているカテゴリを抽出して、今月抑えるべき費目を教えて！'},
      {
        'label': '💰 給料日までのやりくり計画',
        'q': '給料日まであと何日で1日いくら使える？無理なく黒字で乗り切る具体策を教えて！',
      },
      {
        'label': '🎯 大きな支出の積立チェック',
        'q': '登録してある大きな支出予定に向けて、今のペースで貯められそうかチェックして！',
      },
    ];

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${summary['month']}月の家計サマリー',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  Text(
                    '給料日まであと$daysLeft日',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  Text(
                    '今月支出: ¥${_formatCurrency(currentSpent)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '先月比: ${currentSpent - prevSpent >= 0 ? "+" : ""}¥${_formatCurrency(currentSpent - prevSpent)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: currentSpent > prevSpent
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  if (income > 0)
                    Text(
                      '残り: ¥${_formatCurrency(remaining)} (1日約¥${_formatCurrency(daily)})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: remaining < 0
                            ? Colors.red.shade700
                            : Colors.blue.shade900,
                      ),
                    ),
                  if (monthlySaving > 0)
                    Text(
                      '積立目安: 月¥${_formatCurrency(monthlySaving)}',
                      style: const TextStyle(fontSize: 13, color: Colors.teal),
                    ),
                ],
              ),
              if (sortedCats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in sortedCats.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${entry.key}: ¥${_formatCurrency(entry.value as int)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in quickQuestions)
              ActionChip(
                label: Text(
                  item['label'].toString(),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.grey.shade100,
                onPressed: _isAnalyzing
                    ? null
                    : () => _runBudgetAnalysis(item['q'].toString()),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _analysisQuestionCtrl,
                decoration: InputDecoration(
                  hintText: '家計簿から抽出・質問（例：今月の食費は？）',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => _runBudgetAnalysis(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isAnalyzing ? null : () => _runBudgetAnalysis(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              child: const Text('診断'),
            ),
          ],
        ),
        if (_isAnalyzing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('家計簿データを集計・分析しています...'),
                ],
              ),
            ),
          )
        else if (_analysisReply.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI家計簿アドバイザー',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _analysisReply,
                  style: const TextStyle(fontSize: 14, height: 1.55),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _openAiChatWithRemainingBudget,
            icon: const Icon(Icons.restaurant_menu, color: Colors.orange),
            label: const Text(
              '残り予算を引き継いでAIに節約献立を相談する',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.orange),
              foregroundColor: Colors.orange.shade800,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'AI家計簿アシスタント',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildTabButton(0, 'AIで自動入力', Icons.edit_note),
                      _buildTabButton(1, '家計診断・抽出', Icons.analytics_outlined),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              Expanded(
                child: _activeTab == 0
                    ? _buildAutoInputTab(scrollCtrl)
                    : _buildAnalysisTab(scrollCtrl),
              ),
            ],
          ),
        );
      },
    );
  }
}