import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _SlidePoint {
  final IconData icon;
  final String text;

  const _SlidePoint({required this.icon, required this.text});
}

class _SlideData {
  final String badge;
  final String title;
  final String description;
  final IconData icon;
  final IconData subIcon;
  final Color primaryColor;
  final Color bgColor;
  final List<_SlidePoint> points;

  const _SlideData({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    required this.subIcon,
    required this.primaryColor,
    required this.bgColor,
    required this.points,
  });
}

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool isReplay;

  const OnboardingScreen({super.key, this.onComplete, this.isReplay = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  static const _slides = [
    _SlideData(
      badge: 'ようこそ',
      title: '一人暮らしの毎日を\nこれ1つでラクに',
      description: '自炊・家計簿・暮らしの知恵・AI相談がぜんぶ連携。毎日の「今日どうしよう」をサクッと解決します。',
      icon: Icons.home_rounded,
      subIcon: Icons.auto_awesome,
      primaryColor: Color(0xFF1976D2),
      bgColor: Color(0xFFE3F2FD),
      points: [
        _SlidePoint(icon: Icons.restaurant_menu, text: '自炊レシピ提案＆人数自動計算'),
        _SlidePoint(icon: Icons.receipt_long, text: 'レシート撮影＆AI家計簿'),
        _SlidePoint(icon: Icons.forum_outlined, text: '実体験が集まる安心SNS'),
      ],
    ),
    _SlideData(
      badge: 'AIレシピ ＆ アレルギー対応',
      title: 'ない家電もアレルギーも\n自動でよけて即提案',
      description: '気分を選ぶだけで1人分からレシピ提案。アレルギー食材や家にない調理家電を除外し、代用案もAIにすぐ聞けます。',
      icon: Icons.restaurant_rounded,
      subIcon: Icons.no_food_outlined,
      primaryColor: Color(0xFFE65100),
      bgColor: Color(0xFFFFF3E0),
      points: [
        _SlidePoint(icon: Icons.tune, text: '1〜6人分の分量と費用を自動計算'),
        _SlidePoint(icon: Icons.swap_horiz, text: '足りない食材を1タップでAI代用提案'),
        _SlidePoint(icon: Icons.shield_outlined, text: 'アレルギー食材を2段階でブロック'),
      ],
    ),
    _SlideData(
      badge: 'OCR ＆ AI家計簿',
      title: '撮るだけ・話すだけで\n貯金ペースが見える',
      description: 'レシートを撮ればAIがカテゴリ別に自動仕分け。給料日までの残り予算から、そのままAIに節約献立を相談できます。',
      icon: Icons.savings_rounded,
      subIcon: Icons.camera_alt_outlined,
      primaryColor: Color(0xFF00796B),
      bgColor: Color(0xFFE0F2F1),
      points: [
        _SlidePoint(
          icon: Icons.document_scanner_outlined,
          text: 'レシート画像から自動で品目仕分け',
        ),
        _SlidePoint(icon: Icons.edit_note, text: 'タグ追加・文章入力でまとめて記録'),
        _SlidePoint(icon: Icons.analytics_outlined, text: '使いすぎ診断と貯蓄ノートで計画管理'),
      ],
    ),
    _SlideData(
      badge: '安心SNS ＆ ハッシュタグ',
      title: 'みんなの知恵を探せて\nAI審査で安心して投稿',
      description: '料理・掃除・収納のリアルな知恵をハッシュタグで簡単検索。投稿前はAIが個人情報や不適切な内容を自動チェックします。',
      icon: Icons.verified_user_rounded,
      subIcon: Icons.tag,
      primaryColor: Color(0xFF3949AB),
      bgColor: Color(0xFFE8EAF6),
      points: [
        _SlidePoint(icon: Icons.tag, text: '固定カテゴリ×ハッシュタグで探しやすい'),
        _SlidePoint(icon: Icons.bookmark_border, text: '気になる投稿やAIレシピをまとめて保存'),
        _SlidePoint(icon: Icons.security, text: '3層の安全審査で個人情報の映り込みを防止'),
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;
    setState(() {
      _isFinishing = true;
    });

    if (!widget.isReplay) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'hasSeenOnboarding': true,
          }, SetOptions(merge: true));
        } catch (e) {}
      }
    }

    if (!mounted) return;
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  void _goNextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _goPrevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildSlide(_SlideData slide) {
    final points = slide.points;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 156,
                    height: 156,
                    decoration: BoxDecoration(
                      color: slide.bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      slide.icon,
                      size: 74,
                      color: slide.primaryColor,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        slide.subIcon,
                        size: 24,
                        color: slide.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: slide.bgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  slide.badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: slide.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                slide.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < points.length; i++) ...[
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: slide.bgColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              points[i].icon,
                              size: 18,
                              color: slide.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              points[i].text,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (i < points.length - 1) const SizedBox(height: 10),
                    ],
                  ],
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
    final bool isLastPage = _currentPage == _slides.length - 1;
    final Color activeColor = _slides[_currentPage].primaryColor;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton.icon(
                      onPressed: _isFinishing ? null : _goPrevPage,
                      icon: const Icon(Icons.chevron_left, size: 20),
                      label: const Text('戻る'),
                    )
                  else
                    const SizedBox(width: 72),
                  Text(
                    '${_currentPage + 1} / ${_slides.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (!isLastPage)
                    TextButton(
                      onPressed: _isFinishing ? null : _finishOnboarding,
                      child: Text(
                        widget.isReplay ? '閉じる' : 'スキップ',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                  else
                    const SizedBox(width: 72),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return _buildSlide(_slides[index]);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_slides.length, (index) {
                          final bool selected = index == _currentPage;
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: selected ? 26 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: selected
                                    ? activeColor
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isFinishing ? null : _goNextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isFinishing
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isLastPage
                                          ? (widget.isReplay
                                                ? 'アプリに戻る'
                                                : 'アプリをはじめる')
                                          : '次へ',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      isLastPage
                                          ? Icons.check_circle_outline
                                          : Icons.arrow_forward,
                                      size: 20,
                                    ),
                                  ],
                                ),
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
  }
}
