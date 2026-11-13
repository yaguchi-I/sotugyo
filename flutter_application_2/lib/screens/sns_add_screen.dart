import 'dart:convert';
import 'dart:io';
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
  File? _image;

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

  Uint8List? _decodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      return null;
    }
  }

  bool _containsNgWord(String text) {
    final normalized = text.replaceAll(' ', '').replaceAll(' ', '');
    for (final word in _ngWords) {
      if (normalized.contains(word.toString())) {
        return true;
      }
    }
    return false;
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
      final row = _ingredientRows.removeAt(index) as Map;
      (row['name'] as TextEditingController).dispose();
      (row['amount'] as TextEditingController).dispose();
    });
  }

  Future _moderatePostInBackground(String docId, String contentText) async {
    if (contentText.trim().isEmpty) return;
    final key = AiChatScreen.apiKey.trim();
    if (key.isEmpty || key.contains('ここに')) return;

    try {
      final model = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: key,
      );
      final prompt =
          '以下のSNS投稿文に、他者への深刻な誹謗中傷、脅迫、差別、または悪質な荒らし行為が含まれているか判定してください。\n'
          '日常の愚痴や少し強い表現程度であれば許容し、明確に有害な場合のみ UNSAFE と出力してください。\n'
          '回答は SAFE または UNSAFE のいずれか1単語のみで出力してください。\n\n'
          '投稿文：$contentText';

      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 15));
      final result = (response.text ?? '').trim().toUpperCase();

      if (result.contains('UNSAFE')) {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(docId)
            .delete();
      }
    } catch (e) {}
  }

  Future _pickImage({ImageSource source = ImageSource.gallery}) async {
    if (_isPickingImage) return;

    setState(() {
      _isPickingImage = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      if (pickedFile != null) {
        if (!mounted) return;
        setState(() {
          _image = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('画像選択エラー: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  Future _post() async {
    final text = _contentController.text.trim();
    final recipeTitle = _recipeTitleController.text.trim();
    final isRecipeMode =
        _selectedMainCategory == '料理' && recipeTitle.isNotEmpty;

    if (text.isEmpty && !isRecipeMode && _image == null) return;

    final combinedText =
        '$text $recipeTitle${_recipeStepsController.text.trim()}';
    if (_containsNgWord(combinedText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('相手を傷つける可能性のある禁止ワードが含まれているため投稿できません'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();

    setState(() {
      _isUploading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      String userName =
          user?.displayName ?? user?.email?.split('@')[0] ?? '名無しユーザー';
      String userIconBase64 = '';

      if (uid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          final uData = userDoc.data()!;
          if (uData['userName'] != null &&
              uData['userName'].toString().trim().isNotEmpty) {
            userName = uData['userName'].toString().trim();
          }
          if (uData['iconBase64'] != null) {
            userIconBase64 = uData['iconBase64'].toString();
          }
        }
      }

      String imageBase64 = '';
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      final List ingredientsData = [];
      if (isRecipeMode) {
        for (final item in _ingredientRows) {
          final row = item as Map;
          final iName = (row['name'] as TextEditingController).text.trim();
          final iAmount = (row['amount'] as TextEditingController).text.trim();
          if (iName.isNotEmpty) {
            ingredientsData.add({
              'name': iName,
              'amount': iAmount.isEmpty ? '適量' : iAmount,
            });
          }
        }
      }

      final int parsedCost =
          int.tryParse(
            _recipeCostController.text.trim().replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;
      final String timeText = _recipeTimeController.text.trim();
      final String stepsText = _recipeStepsController.text.trim();

      String displayContent = text;
      if (isRecipeMode && displayContent.isEmpty) {
        displayContent = '「$recipeTitle」のレシピを投稿しました！';
      }

      final docRef = await FirebaseFirestore.instance.collection('posts').add({
        'userId': uid,
        'userName': userName,
        'userIconBase64': userIconBase64,
        'content': displayContent,
        'hasImage': _image != null,
        'imageBase64': imageBase64,
        'mainCategory': _selectedMainCategory,
        'subCategory': _selectedSubCategory,
        'isRecipePost': isRecipeMode,
        'recipeTitle': isRecipeMode ? recipeTitle : '',
        'baseServings': isRecipeMode ? _baseServings : 1,
        'recipeCost': isRecipeMode ? parsedCost : 0,
        'recipeTime': isRecipeMode ? timeText : '',
        'recipeIngredients': isRecipeMode ? ingredientsData : [],
        'recipeSteps': isRecipeMode ? stepsText : '',
        'replies': 0,
        'likes': 0,
        'helpfuls': 0,
        'likedUsers': [],
        'helpfulUsers': [],
        'savedUsers': [],
        'hiddenUsers': [],
        'reportedUsers': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      _moderatePostInBackground(docRef.id, combinedText);

      _contentController.clear();
      _recipeTitleController.clear();
      _recipeCostController.clear();
      _recipeTimeController.clear();
      _recipeStepsController.clear();
      for (final item in _ingredientRows) {
        final row = item as Map;
        (row['name'] as TextEditingController).clear();
        (row['amount'] as TextEditingController).clear();
      }

      if (!mounted) return;
      setState(() {
        _image = null;
        _baseServings = 1;
        _selectedMainCategory = '指定なし';
        _selectedSubCategory = '指定なし';
      });

      messenger.showSnackBar(const SnackBar(content: Text('投稿しました！')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('エラーが発生しました')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _recipeTitleController.dispose();
    _recipeCostController.dispose();
    _recipeTimeController.dispose();
    _recipeStepsController.dispose();
    for (final item in _ingredientRows) {
      final row = item as Map;
      (row['name'] as TextEditingController).dispose();
      (row['amount'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Widget _buildRecipeInputSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text(
                'レシピ詳細を入力（任意）',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recipeTitleController,
            decoration: InputDecoration(
              labelText: '料理名（例: もやしと豚肉のレンジ蒸し）',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _recipeCostController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '費用目安(円)',
                    hintText: '例: 150',
                    suffixText: '円',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _recipeTimeController,
                  decoration: InputDecoration(
                    labelText: '調理時間',
                    hintText: '例: 10分',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                '基準の人数（分量計算の基準）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: _baseServings > 1
                          ? () => setState(() => _baseServings--)
                          : null,
                    ),
                    Text(
                      '$_baseServings人分',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _baseServings < 6
                          ? () => setState(() => _baseServings++)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text(
            '【材料と分量】',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            '※分量を「200g」「1/2個」「大さじ1」のように書くと保存後に人数変更で自動計算されます',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ...List.generate(_ingredientRows.length, (idx) {
            final row = _ingredientRows[idx] as Map;
            final nameCtrl = row['name'] as TextEditingController;
            final amountCtrl = row['amount'] as TextEditingController;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: '材料（例: もやし）',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amountCtrl,
                      decoration: InputDecoration(
                        hintText: '分量（例: 1袋）',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (_ingredientRows.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
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
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('材料を追加する'),
          ),
          const SizedBox(height: 8),
          const Text(
            '【作り方・手順】',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _recipeStepsController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '1. 耐熱皿にもやしと豚肉を並べる\n2. ラップをして600Wで4分加熱する...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid ?? '';

    return StreamBuilder(
      stream: uid.isNotEmpty
          ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
          : null,
      builder: (context, snapshot) {
        String currentName =
            currentUser?.displayName ??
            currentUser?.email?.split('@')[0] ??
            '名無しユーザー';
        String currentIconBase64 = '';

        if (snapshot.hasData && snapshot.data != null) {
          final doc = snapshot.data as DocumentSnapshot;
          if (doc.exists && doc.data() != null) {
            final data = Map.from(doc.data() as Map);
            if (data['userName'] != null &&
                data['userName'].toString().trim().isNotEmpty) {
              currentName = data['userName'].toString().trim();
            }
            if (data['iconBase64'] != null) {
              currentIconBase64 = data['iconBase64'].toString();
            }
          }
        }

        final iconBytes = _decodeBase64(currentIconBase64);
        final List currentSubList = List.from(
          _subCategories[_selectedMainCategory] ?? ['指定なし'],
        );

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            title: const Text(
              '新規投稿',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _post,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'ポスト',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.grey,
                            backgroundImage: iconBytes != null
                                ? MemoryImage(iconBytes)
                                : null,
                            child: iconBytes == null
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                TextField(
                                  controller: _contentController,
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    hintText: 'いまどうしてる？（レシピの一言メモや日常のつぶやき）',
                                    border: InputBorder.none,
                                  ),
                                ),
                                if (_image != null) const SizedBox(height: 12),
                                if (_image != null)
                                  Stack(
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxHeight: 280,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Image.file(
                                            _image!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _image = null;
                                            });
                                          },
                                          child: const CircleAvatar(
                                            backgroundColor: Colors.black54,
                                            radius: 14,
                                            child: Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'タグを選択（「料理」を選ぶとレシピ入力欄が開きます）',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _mainCategories.map((main) {
                            final mainStr = main.toString();
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(mainStr),
                                selected: _selectedMainCategory == mainStr,
                                selectedColor: Colors.blue.shade100,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedMainCategory = mainStr;
                                      final subs =
                                          _subCategories[mainStr] as List;
                                      _selectedSubCategory = subs.first
                                          .toString();
                                    });
                                    FocusScope.of(context).unfocus();
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedMainCategory != '指定なし')
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: currentSubList.map((sub) {
                              final subStr = sub.toString();
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ChoiceChip(
                                  label: Text(subStr),
                                  selected: _selectedSubCategory == subStr,
                                  selectedColor: Colors.green.shade100,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedSubCategory = subStr;
                                      });
                                      FocusScope.of(context).unfocus();
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      if (_selectedMainCategory == '料理')
                        _buildRecipeInputSection(),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.image_outlined,
                        color: Colors.blue,
                      ),
                      onPressed: () => _pickImage(source: ImageSource.gallery),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.blue,
                      ),
                      onPressed: () => _pickImage(source: ImageSource.camera),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }
}
