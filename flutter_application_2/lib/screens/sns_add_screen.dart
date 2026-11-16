import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart';

class SnsAddScreen extends StatefulWidget {
  const SnsAddScreen({super.key});

  @override
  State createState() => _SnsAddScreenState();
}

class _SnsAddScreenState extends State {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _recipeTitleController = TextEditingController();
  final TextEditingController _recipeCostController = TextEditingController();
  final TextEditingController _recipeTimeController = TextEditingController();
  final TextEditingController _recipeStepsController = TextEditingController();

  int _baseServings = 1;
  final List _ingredientRows = [
    {'name': TextEditingController(), 'amount': TextEditingController()},
    {'name': TextEditingController(), 'amount': TextEditingController()},
  ];

  bool _isUploading = false;
  bool _isPickingImage = false;
  bool _isRecipeMode = false;
  Uint8List? _imageBytes;

  final List _mainCategories = ['指定なし', '料理', '掃除', '収納', 'その他'];
  final Map _subCategories = {
    '指定なし': ['指定なし'],
    '料理': ['野菜', '肉類', '麺類', '作り置き', 'その他'],
    '掃除': ['キッチン', 'お風呂', 'トイレ', 'リビング', 'その他'],
    '収納': ['クローゼット', 'デスク周り', '小物', 'その他'],
    'その他': ['その他'],
  };

  final List _ngWords = [
    '死ね',
    'しね',
    '殺す',
    'ころす',
    '消えろ',
    'きえろ',
    'ゴミ人間',
    'クズ人間',
    'バカ野郎',
  ];

  String _selectedMainCategory = '指定なし';
  String _selectedSubCategory = '指定なし';

  @override
  void dispose() {
    _contentController.dispose();
    _recipeTitleController.dispose();
    _recipeCostController.dispose();
    _recipeTimeController.dispose();
    _recipeStepsController.dispose();
    for (final row in _ingredientRows) {
      final mapRow = row as Map;
      (mapRow['name'] as TextEditingController).dispose();
      (mapRow['amount'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _addIngredientRow() {
    setState(() {
      _ingredientRows.add({
        'name': TextEditingController(),
        'amount': TextEditingController(),
      });
    });
  }

  void _removeIngredientRow(int index) {
    if (_ingredientRows.length <= 1) return;
    setState(() {
      final mapRow = _ingredientRows.removeAt(index) as Map;
      (mapRow['name'] as TextEditingController).dispose();
      (mapRow['amount'] as TextEditingController).dispose();
    });
  }

  Future _pickImage(ImageSource source) async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('画像の読み込みに失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  bool _containsLocalNgWord(String text) {
    final lower = text.toLowerCase();
    for (final w in _ngWords) {
      if (lower.contains(w.toString())) return true;
    }
    return false;
  }

  Future _runBackgroundModeration(String docId, String combinedText) async {
    final currentKey = AiChatScreen.apiKey.trim();
    if (currentKey.isEmpty || currentKey.contains('ここに')) return;

    final prompt =
        '以下のSNS投稿テキストに、他者への深刻な誹謗中傷、暴力予告、違法行為の助長が含まれているか判定してください。\n'
        '問題がある場合は「NG」、問題がない日常の投稿であれば「SAFE」とだけ出力してください。\n'
        '投稿内容：$combinedText';

    for (final modelItem in AiChatScreen.fallbackModels) {
      try {
        final model = GenerativeModel(
          model: modelItem.toString(),
          apiKey: currentKey,
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 15));
        final result = (res.text ?? '').trim().toUpperCase();
        if (result.contains('NG')) {
          await FirebaseFirestore.instance
              .collection('posts')
              .doc(docId)
              .delete();
        }
        break;
      } catch (e) {}
    }
  }

  Future _submitPost() async {
    final messenger = ScaffoldMessenger.of(context);
    final content = _contentController.text.trim();
    final recipeTitle = _recipeTitleController.text.trim();

    if (!_isRecipeMode && content.isEmpty && _imageBytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('投稿内容または画像を入力してください')),
      );
      return;
    }

    if (_isRecipeMode && recipeTitle.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('料理名を入力してください')));
      return;
    }

    final combinedCheckText =
        '$recipeTitle $content ${_recipeStepsController.text}';
    if (_containsLocalNgWord(combinedCheckText)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('不適切な表現が含まれているため投稿できません'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final uid = currentUser?.uid ?? '';
      String userName = currentUser?.displayName ?? '';
      String userIconBase64 = '';

      if (uid.isNotEmpty) {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (uDoc.exists && uDoc.data() != null) {
          final uData = uDoc.data()!;
          if (uData['userName'] != null &&
              uData['userName'].toString().trim().isNotEmpty) {
            userName = uData['userName'].toString().trim();
          }
          if (uData['iconBase64'] != null) {
            userIconBase64 = uData['iconBase64'].toString();
          }
        }
      }

      if (userName.isEmpty) {
        userName = (currentUser?.email ?? '名無し').split('@').first;
      }

      final List ingredientsData = [];
      if (_isRecipeMode) {
        for (final row in _ingredientRows) {
          final mapRow = row as Map;
          final n = (mapRow['name'] as TextEditingController).text.trim();
          final a = (mapRow['amount'] as TextEditingController).text.trim();
          if (n.isNotEmpty) {
            ingredientsData.add({'name': n, 'amount': a.isEmpty ? '適量' : a});
          }
        }
      }

      final String imageBase64 = _imageBytes != null
          ? base64Encode(_imageBytes!)
          : '';

      final docRef = await FirebaseFirestore.instance.collection('posts').add({
        'userId': uid,
        'userName': userName,
        'userIconBase64': userIconBase64,
        'mainCategory': _isRecipeMode ? '料理' : _selectedMainCategory,
        'subCategory': _selectedSubCategory,
        'title': _isRecipeMode ? recipeTitle : '',
        'content': content,
        'hasImage': _imageBytes != null,
        'imageBase64': imageBase64,
        'isRecipePost': _isRecipeMode,
        'recipeCost': _isRecipeMode ? _recipeCostController.text.trim() : '',
        'recipeTime': _isRecipeMode ? _recipeTimeController.text.trim() : '',
        'recipeServings': _isRecipeMode ? _baseServings : 1,
        'recipeIngredients': ingredientsData,
        'recipeSteps': _isRecipeMode ? _recipeStepsController.text.trim() : '',
        'likes': 0,
        'helpfuls': 0,
        'saves': 0,
        'replies': 0,
        'likedUsers': [],
        'helpfulUsers': [],
        'savedUsers': [],
        'hiddenUsers': [],
        'reportedUsers': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      _runBackgroundModeration(docRef.id, combinedCheckText);

      if (!mounted) return;

      setState(() {
        _contentController.clear();
        _recipeTitleController.clear();
        _recipeCostController.clear();
        _recipeTimeController.clear();
        _recipeStepsController.clear();
        for (final row in _ingredientRows) {
          final mapRow = row as Map;
          (mapRow['name'] as TextEditingController).clear();
          (mapRow['amount'] as TextEditingController).clear();
        }
        _imageBytes = null;
        _isUploading = false;
      });

      messenger.showSnackBar(const SnackBar(content: Text('タイムラインに投稿しました！')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('投稿に失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List currentSubList = List.from(
      _subCategories[_selectedMainCategory] ?? ['指定なし'],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text(
          '新規投稿',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _submitPost,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 16),
              label: const Text('投稿する'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '🍳 料理レシピとして投稿する（分量・金額計算対応）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                'ONにすると材料や人数・金額を入力でき、他の人が人数変更やAI代用案を使えるようになります',
                style: TextStyle(fontSize: 12),
              ),
              value: _isRecipeMode,
              onChanged: (val) {
                setState(() {
                  _isRecipeMode = val;
                  if (val) {
                    _selectedMainCategory = '料理';
                    _selectedSubCategory = '野菜';
                  }
                });
              },
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField(
                    value: _selectedMainCategory,
                    decoration: const InputDecoration(
                      labelText: 'メインカテゴリ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _mainCategories.map((c) {
                      final str = c.toString();
                      return DropdownMenuItem(value: str, child: Text(str));
                    }).toList(),
                    onChanged: _isRecipeMode
                        ? null
                        : (val) {
                            if (val != null) {
                              final nextMain = val.toString();
                              final nextSubs = List.from(
                                _subCategories[nextMain] ?? ['指定なし'],
                              );
                              setState(() {
                                _selectedMainCategory = nextMain;
                                _selectedSubCategory = nextSubs.first
                                    .toString();
                              });
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField(
                    value: currentSubList.contains(_selectedSubCategory)
                        ? _selectedSubCategory
                        : currentSubList.first.toString(),
                    decoration: const InputDecoration(
                      labelText: 'サブカテゴリ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: currentSubList.map((s) {
                      final str = s.toString();
                      return DropdownMenuItem(value: str, child: Text(str));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSubCategory = val.toString();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isRecipeMode) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _recipeTitleController,
                      decoration: const InputDecoration(
                        labelText: '料理名（必須）',
                        hintText: '例：豚バラとキャベツの旨塩炒め',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _recipeCostController,
                            decoration: const InputDecoration(
                              labelText: '目安費用',
                              hintText: '例：約180円',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _recipeTimeController,
                            decoration: const InputDecoration(
                              labelText: '調理時間',
                              hintText: '例：約10分',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '基準の人数（何人分の分量か）',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _baseServings > 1
                                  ? () {
                                      setState(() {
                                        _baseServings--;
                                      });
                                    }
                                  : null,
                            ),
                            Text(
                              '$_baseServings人分',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _baseServings < 6
                                  ? () {
                                      setState(() {
                                        _baseServings++;
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    const Text(
                      '材料リスト（数値を入れると自動で人数計算されます）',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_ingredientRows.length, (idx) {
                      final mapRow = _ingredientRows[idx] as Map;
                      final nameCtrl = mapRow['name'] as TextEditingController;
                      final amountCtrl =
                          mapRow['amount'] as TextEditingController;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(
                                  hintText: '材料名（例：豚肉）',
                                  filled: true,
                                  fillColor: Colors.white,
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: amountCtrl,
                                decoration: const InputDecoration(
                                  hintText: '分量（例：100g）',
                                  filled: true,
                                  fillColor: Colors.white,
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _removeIngredientRow(idx),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: _addIngredientRow,
                      icon: const Icon(Icons.add),
                      label: const Text('材料を追加する'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _recipeStepsController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '作り方・手順',
                        hintText: '1. 野菜を切る\n2. フライパンで炒める...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _isRecipeMode ? 'ひとことコメント・コツなど（任意）' : '投稿内容（必須）',
                hintText: '一人暮らしの知恵や今日のご飯、質問などを自由に書こう！',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('スクショ・画像を選択'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('カメラ'),
                ),
              ],
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 12),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                    ),
                  ),
                  IconButton(
                    icon: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                    onPressed: () {
                      setState(() {
                        _imageBytes = null;
                      });
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
