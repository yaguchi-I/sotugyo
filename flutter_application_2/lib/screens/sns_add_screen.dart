import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'ai_chat_screen.dart' show AiChatScreen;
import '../services/ai_knowledge_service.dart' show AiKnowledgeService;
import '../widgets/top_toast.dart' show showTopToast;

Future openPostScreen(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SnsAddScreen(),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class SnsAddScreen extends StatefulWidget {
  final VoidCallback? onPostSuccess;

  const SnsAddScreen({super.key, this.onPostSuccess});

  @override
  State createState() => _SnsAddScreenState();
}

class _SnsAddScreenState extends State {
  VoidCallback? get _onPostSuccess => (widget as SnsAddScreen).onPostSuccess;

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
  final List _imageBytesList = [];

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

  Future _pickMultipleImages() async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(imageQuality: 85);
      if (pickedFiles.isNotEmpty) {
        final List loaded = [];
        for (final f in pickedFiles) {
          final b = await f.readAsBytes();
          loaded.add(b);
        }
        if (mounted) {
          setState(() {
            _imageBytesList.addAll(loaded);
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

  Future _pickCameraImage() async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (mounted) {
          setState(() {
            _imageBytesList.add(bytes);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('カメラ画像の読み込みに失敗しました: $e')));
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
    final recipeCost = _recipeCostController.text.trim();
    final recipeTime = _recipeTimeController.text.trim();
    final recipeSteps = _recipeStepsController.text.trim();

    if (!_isRecipeMode && content.isEmpty && _imageBytesList.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('投稿内容または画像を入力してください')),
      );
      return;
    }

    if (_isRecipeMode && recipeTitle.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('料理名を入力してください')));
      return;
    }

    final combinedCheckText = '$recipeTitle $content $recipeSteps';
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

      final List imageSnapshot = List.from(_imageBytesList);
      final List imagesBase64List = imageSnapshot
          .map((b) => base64Encode(b as Uint8List))
          .toList();
      final String firstImageBase64 = imagesBase64List.isNotEmpty
          ? imagesBase64List.first.toString()
          : '';

      final String finalMainCat = _isRecipeMode ? '料理' : _selectedMainCategory;
      final String finalSubCat = _selectedSubCategory;
      final String finalTitle = _isRecipeMode ? recipeTitle : '';
      final int initialCost = AiKnowledgeService.parseEstimatedCost(
        _isRecipeMode ? recipeCost : '',
      );
      final String initialPriceTier = AiKnowledgeService.inferPriceTierFromCost(
        initialCost,
      );
      final List initialTags = AiKnowledgeService.buildImmediateFallbackTags(
        mainCategory: finalMainCat,
        subCategory: finalSubCat,
        title: finalTitle,
        content: content,
        ingredients: ingredientsData,
        estimatedCost: initialCost,
      );

      final docRef = await FirebaseFirestore.instance.collection('posts').add({
        'userId': uid,
        'userName': userName,
        'userIconBase64': userIconBase64,
        'mainCategory': finalMainCat,
        'subCategory': finalSubCat,
        'title': finalTitle,
        'content': content,
        'hasImage': imagesBase64List.isNotEmpty,
        'imageBase64': firstImageBase64,
        'imagesBase64': imagesBase64List,
        'isRecipePost': _isRecipeMode,
        'recipeCost': _isRecipeMode ? recipeCost : '',
        'recipeTime': _isRecipeMode ? recipeTime : '',
        'recipeServings': _isRecipeMode ? _baseServings : 1,
        'recipeIngredients': ingredientsData,
        'recipeSteps': _isRecipeMode ? recipeSteps : '',
        'aiTags': initialTags,
        'priceTier': initialPriceTier,
        'estimatedCost': initialCost,
        'usedAppliances': [],
        'summaryForAi': finalTitle.isNotEmpty ? finalTitle : content,
        'isAiIndexed': false,
        'likes': 0,
        'helpfuls': 0,
        'saves': 0,
        'replies': 0,
        'impressions': 0,
        'valueScore': 0.0,
        'likedUsers': [],
        'helpfulUsers': [],
        'savedUsers': [],
        'hiddenUsers': [],
        'reportedUsers': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      final bool savedRecipeMode = _isRecipeMode;

      _runBackgroundModeration(docRef.id, combinedCheckText);
      AiKnowledgeService.enrichPostMetadataInBackground(
        docId: docRef.id,
        mainCategory: finalMainCat,
        subCategory: finalSubCat,
        title: finalTitle,
        content: content,
        isRecipePost: savedRecipeMode,
        recipeCostText: savedRecipeMode ? recipeCost : '',
        recipeTimeText: savedRecipeMode ? recipeTime : '',
        ingredients: ingredientsData,
        recipeSteps: savedRecipeMode ? recipeSteps : '',
        images: imageSnapshot,
      );

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
        _imageBytesList.clear();
        _isRecipeMode = false;
        _isUploading = false;
      });

      showTopToast(context, 'タイムラインに投稿しました');

      if (_onPostSuccess != null) {
        _onPostSuccess!();
      }
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('投稿に失敗しました: $e')));
    }
  }

  bool get _hasDraft =>
      _contentController.text.trim().isNotEmpty ||
      _recipeTitleController.text.trim().isNotEmpty ||
      _recipeStepsController.text.trim().isNotEmpty ||
      _imageBytesList.isNotEmpty;

  Future _closeScreen() async {
    if (_isUploading) return;
    if (!_hasDraft) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('投稿を破棄しますか？'),
        content: const Text('入力した内容は保存されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('編集を続ける'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('破棄', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List currentSubList = List.from(
      _subCategories[_selectedMainCategory] ?? ['指定なし'],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeScreen();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '閉じる',
            onPressed: _closeScreen,
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
                        final nameCtrl =
                            mapRow['name'] as TextEditingController;
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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickMultipleImages,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _imageBytesList.isEmpty
                          ? 'スクショ・画像を選択（複数可）'
                          : '画像をさらに追加（現在${_imageBytesList.length}枚）',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickCameraImage,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('カメラ'),
                  ),
                  if (_imageBytesList.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _imageBytesList.clear();
                        });
                      },
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      label: const Text(
                        'すべてクリア',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              if (_imageBytesList.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...List.generate(_imageBytesList.length, (idx) {
                  final bytes = _imageBytesList[idx] as Uint8List;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14.0),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          height: 220,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: IconButton(
                            icon: const CircleAvatar(
                              radius: 15,
                              backgroundColor: Colors.black87,
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _imageBytesList.removeAt(idx);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
