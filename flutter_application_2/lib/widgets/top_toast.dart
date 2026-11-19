import 'package:flutter/material.dart';

/// 使い方:
///   showTopToast(context, 'タイムラインに投稿しました');
///   showTopToast(context, '投稿に失敗しました', isError: true);
///   showReactionToast(context, 'likedUsers', added: true);
OverlayEntry? _currentToast;

/// いいね・参考になった・保存 を押したときの通知
/// [listField] は Firestore のフィールド名（likedUsers / helpfulUsers / savedUsers）
/// [added] は「押してONになった」なら true、「取り消した」なら false
void showReactionToast(
  BuildContext context,
  String listField, {
  required bool added,
}) {
  const offColor = Color(0xFF5F6368); // 取り消し時はグレー

  switch (listField) {
    case 'likedUsers':
      showTopToast(
        context,
        added ? 'いいねしました' : 'いいねを取り消しました',
        icon: added ? Icons.favorite : Icons.favorite_border,
        color: added ? const Color(0xFFE0245E) : offColor,
      );
      break;
    case 'helpfulUsers':
      showTopToast(
        context,
        added ? '参考になりました！' : '「参考になった」を取り消しました',
        icon: added ? Icons.lightbulb : Icons.lightbulb_outline,
        color: added ? const Color(0xFFF5A623) : offColor,
      );
      break;
    case 'savedUsers':
      showTopToast(
        context,
        added ? '保存フォルダに追加しました' : '保存を解除しました',
        icon: added ? Icons.bookmark : Icons.bookmark_border,
        color: added ? const Color(0xFF2F80ED) : offColor,
      );
      break;
  }
}

void showTopToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
  bool isError = false,
  Color? color,
  Duration duration = const Duration(milliseconds: 2500),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  // 前の通知が残っていたら消してから出す
  _currentToast?.remove();
  _currentToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopToast(
      message: message,
      icon: isError ? Icons.error_outline : icon,
      backgroundColor: isError
          ? const Color(0xFFE5484D)
          : (color ?? const Color(0xFF2F80ED)),
      duration: duration,
      onDismissed: () {
        if (_currentToast == entry) {
          entry.remove();
          _currentToast = null;
        }
      },
    ),
  );

  _currentToast = entry;
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TopToast({
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    Future.delayed(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Center(
                child: GestureDetector(
                  onTap: _close, // タップで閉じる
                  onVerticalDragEnd: (d) {
                    // 上にスワイプで閉じる
                    if ((d.primaryVelocity ?? 0) < 0) _close();
                  },
                  child: Material(
                    color: widget.backgroundColor,
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
