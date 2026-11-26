import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/top_toast.dart' show showTopToast;

class AccountSettingsScreen extends StatefulWidget {
  final VoidCallback? onOpenProfileEdit;

  const AccountSettingsScreen({super.key, this.onOpenProfileEdit});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final String _uid = _auth.currentUser?.uid ?? '';
  late final Stream<DocumentSnapshot>? _userStream = _uid.isNotEmpty
      ? FirebaseFirestore.instance.collection('users').doc(_uid).snapshots()
      : null;

  bool _isReloadingUser = false;

  @override
  void initState() {
    super.initState();
    _syncCurrentUserEmail();
  }

  Future<void> _syncCurrentUserEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.reload();
      final refreshed = _auth.currentUser;
      final authEmail = refreshed?.email?.trim() ?? '';
      if (authEmail.isNotEmpty && _uid.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .get();
        final storedEmail = doc.data()?['email']?.toString().trim() ?? '';
        if (storedEmail != authEmail) {
          await FirebaseFirestore.instance.collection('users').doc(_uid).set({
            'email': authEmail,
          }, SetOptions(merge: true));
        }
      }
      if (mounted) setState(() {});
    } catch (e) {}
  }

  String _formatCreationDate(DateTime? dt) {
    if (dt == null) return '不明';
    final local = dt.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return '現在のパスワードが正しくありません';
      case 'invalid-email':
        return 'メールアドレスの形式が正しくありません';
      case 'email-already-in-use':
        return 'このメールアドレスはすでに別のアカウントで使用されています';
      case 'weak-password':
        return '新しいパスワードは6文字以上にしてください';
      case 'requires-recent-login':
        return 'セキュリティ保護のため、一度ログアウトして再ログインしてからお試しください';
      case 'too-many-requests':
        return '操作回数が多すぎます。しばらく時間をおいてお試しください';
      case 'operation-not-allowed':
        return 'この操作は現在許可されていません（Firebase設定をご確認ください）';
      default:
        return '処理に失敗しました（${e.code}）';
    }
  }

  Future<void> _reauthenticate(User user, String currentPassword) async {
    final currentEmail = user.email?.trim() ?? '';
    if (currentEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'メールアドレスが取得できませんでした',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: currentEmail,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> _sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() => _isReloadingUser = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      showTopToast(context, '確認メールを送信しました。メール内のリンクを開いてください');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_mapAuthError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isReloadingUser = false);
    }
  }

  Future<void> _showChangeEmailDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final currentPasswordCtrl = TextEditingController();
    final newEmailCtrl = TextEditingController();
    bool obscure = true;
    bool isSubmitting = false;
    String errorText = '';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            'メールアドレスを変更',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '現在: ${user.email ?? "未設定"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: currentPasswordCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '現在のパスワード（本人確認）',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() => obscure = !obscure);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '新しいメールアドレス',
                    hintText: 'example@mail.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '新しいメールアドレスへ確認リンクを送信します。リンクを開くと変更が完了します。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final pw = currentPasswordCtrl.text.trim();
                      final newEmail = newEmailCtrl.text.trim();

                      if (pw.isEmpty) {
                        setDialogState(() => errorText = '現在のパスワードを入力してください');
                        return;
                      }
                      if (newEmail.isEmpty || !newEmail.contains('@')) {
                        setDialogState(() => errorText = '正しいメールアドレスを入力してください');
                        return;
                      }
                      if (newEmail == (user.email ?? '').trim()) {
                        setDialogState(() => errorText = '現在と同じメールアドレスです');
                        return;
                      }

                      setDialogState(() {
                        isSubmitting = true;
                        errorText = '';
                      });

                      try {
                        await _reauthenticate(user, pw);
                        await user.verifyBeforeUpdateEmail(newEmail);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        showTopToast(
                          context,
                          '$newEmail 宛に確認メールを送信しました。リンクを開くと変更が完了します',
                        );
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = _mapAuthError(e);
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = 'エラーが発生しました: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('確認メールを送信'),
            ),
          ],
        ),
      ),
    );

    currentPasswordCtrl.dispose();
    newEmailCtrl.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool isSubmitting = false;
    String errorText = '';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            'パスワードを変更',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: currentPasswordCtrl,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: '現在のパスワード',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() => obscureCurrent = !obscureCurrent);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: '新しいパスワード（6文字以上）',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() => obscureNew = !obscureNew);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordCtrl,
                  obscureText: obscureNew,
                  decoration: const InputDecoration(
                    labelText: '新しいパスワード（確認用）',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final currentPw = currentPasswordCtrl.text.trim();
                      final newPw = newPasswordCtrl.text.trim();
                      final confirmPw = confirmPasswordCtrl.text.trim();

                      if (currentPw.isEmpty) {
                        setDialogState(() => errorText = '現在のパスワードを入力してください');
                        return;
                      }
                      if (newPw.length < 6) {
                        setDialogState(
                          () => errorText = '新しいパスワードは6文字以上で入力してください',
                        );
                        return;
                      }
                      if (newPw != confirmPw) {
                        setDialogState(() => errorText = '確認用パスワードが一致しません');
                        return;
                      }
                      if (currentPw == newPw) {
                        setDialogState(
                          () => errorText = '現在とは別のパスワードを設定してください',
                        );
                        return;
                      }

                      setDialogState(() {
                        isSubmitting = true;
                        errorText = '';
                      });

                      try {
                        await _reauthenticate(user, currentPw);
                        await user.updatePassword(newPw);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        showTopToast(context, 'パスワードを変更しました');
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = _mapAuthError(e);
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = 'エラーが発生しました: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('変更する'),
            ),
          ],
        ),
      ),
    );

    currentPasswordCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _auth.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('パスワード再設定メールを送信'),
        content: Text('$email 宛にパスワード再設定用のリンクを送信します。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('送信する'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      showTopToast(context, '$email 宛にパスワード再設定メールを送信しました');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_mapAuthError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool isDeleting = false;
    String errorText = '';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'アカウントを削除（退会）',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'アカウントを削除するとプロフィールや設定が失われ、元に戻すことはできません。続行するには現在のパスワードを入力してください。',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '現在のパスワード',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() => obscure = !obscure);
                      },
                    ),
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      final pw = passwordCtrl.text.trim();
                      if (pw.isEmpty) {
                        setDialogState(() => errorText = '現在のパスワードを入力してください');
                        return;
                      }

                      setDialogState(() {
                        isDeleting = true;
                        errorText = '';
                      });

                      try {
                        await _reauthenticate(user, pw);
                        if (_uid.isNotEmpty) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(_uid)
                                .delete();
                          } catch (e) {}
                        }
                        await user.delete();
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          isDeleting = false;
                          errorText = _mapAuthError(e);
                        });
                      } catch (e) {
                        setDialogState(() {
                          isDeleting = false;
                          errorText = '削除に失敗しました: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('完全に削除する'),
            ),
          ],
        ),
      ),
    );

    passwordCtrl.dispose();
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _auth.signOut();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 56, color: Colors.grey.shade200),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final currentEmail = user?.email ?? '未設定';
    final isEmailVerified = user?.emailVerified == true;
    final createdStr = _formatCreationDate(user?.metadata.creationTime);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'アカウント設定',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: '最新の状態に更新',
            onPressed: _isReloadingUser ? null : _syncCurrentUserEmail,
            icon: _isReloadingUser
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userStream,
        builder: (context, snapshot) {
          Map userData = {};
          if (snapshot.hasData && snapshot.data != null) {
            final doc = snapshot.data!;
            if (doc.exists && doc.data() != null) {
              userData = Map.from(doc.data() as Map);
            }
          }

          final userName = userData['userName']?.toString().isNotEmpty == true
              ? userData['userName'].toString()
              : (user?.displayName ?? '未設定');
          final List blockedUsers = userData['blockedUsers'] is List
              ? List.from(userData['blockedUsers'])
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : [];
          final List lessInterestedTopics =
              userData['lessInterestedTopics'] is List
              ? List.from(userData['lessInterestedTopics'])
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : [];

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  _buildSectionHeader('アカウント情報'),
                  _buildSectionCard([
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('ユーザー名'),
                      subtitle: Text(userName),
                      trailing: widget.onOpenProfileEdit != null
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: widget.onOpenProfileEdit,
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('メールアドレス'),
                      subtitle: Row(
                        children: [
                          Flexible(
                            child: Text(
                              currentEmail,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isEmailVerified
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isEmailVerified ? '認証済み' : '未認証',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isEmailVerified
                                    ? Colors.green.shade800
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showChangeEmailDialog,
                    ),
                    if (!isEmailVerified)
                      ListTile(
                        leading: const Icon(
                          Icons.mark_email_unread_outlined,
                          color: Colors.orange,
                        ),
                        title: const Text('メールアドレスの確認メールを再送'),
                        subtitle: const Text(
                          '受信メールのリンクを開くと認証済みになります',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _sendEmailVerification,
                      ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('アカウント作成日'),
                      subtitle: Text(createdStr),
                    ),
                  ]),
                  _buildSectionHeader('セキュリティ・パスワード'),
                  _buildSectionCard([
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('パスワードを変更する'),
                      subtitle: const Text(
                        '現在のパスワードを確認して変更します',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showChangePasswordDialog,
                    ),
                    ListTile(
                      leading: const Icon(Icons.mail_lock_outlined),
                      title: const Text('パスワード再設定メールを送る'),
                      subtitle: const Text(
                        '現在のパスワードを忘れた場合',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _sendPasswordResetEmail,
                    ),
                  ]),
                  _buildSectionHeader('プライバシーと安全'),
                  _buildSectionCard([
                    ListTile(
                      leading: const Icon(Icons.block_outlined),
                      title: const Text('ブロックしたアカウント'),
                      subtitle: Text(
                        blockedUsers.isEmpty
                            ? 'ブロック中のユーザーはいません'
                            : '${blockedUsers.length}件をブロック中',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                _BlockedUsersManageScreen(uid: _uid),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.visibility_off_outlined),
                      title: const Text('表示を減らしている話題'),
                      subtitle: Text(
                        lessInterestedTopics.isEmpty
                            ? '制限中の話題はありません'
                            : '${lessInterestedTopics.length}件の話題を制限中',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _MutedTopicsManageScreen(uid: _uid),
                          ),
                        );
                      },
                    ),
                  ]),
                  _buildSectionHeader('アカウント操作'),
                  _buildSectionCard([
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.orange),
                      title: const Text('ログアウト'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _confirmLogout,
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever_outlined,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'アカウントを削除（退会）',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'アカウントを完全に削除します（復元不可）',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.red,
                      ),
                      onTap: _showDeleteAccountDialog,
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BlockedUsersManageScreen extends StatelessWidget {
  final String uid;

  const _BlockedUsersManageScreen({required this.uid});

  Future<void> _unblock(BuildContext context, String targetKey) async {
    if (uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'blockedUsers': FieldValue.arrayRemove([targetKey]),
    }, SetOptions(merge: true));
    if (context.mounted) {
      showTopToast(context, 'ブロックを解除しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ブロックしたアカウント',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('ログインが必要です'))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data?.data() as Map?;
                final List blocked = data?['blockedUsers'] is List
                    ? List.from(data!['blockedUsers'])
                          .map((e) => e.toString().trim())
                          .where((e) => e.isNotEmpty)
                          .toList()
                    : [];

                if (blocked.isEmpty) {
                  return const Center(
                    child: Text(
                      'ブロックしているアカウントはありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: blocked.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final targetKey = blocked[index].toString();
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(targetKey)
                          .get(),
                      builder: (context, userSnap) {
                        String displayName = targetKey;
                        if (userSnap.hasData &&
                            userSnap.data != null &&
                            userSnap.data!.exists) {
                          final uData = userSnap.data!.data() as Map?;
                          final name = uData?['userName']?.toString().trim();
                          if (name != null && name.isNotEmpty) {
                            displayName = name;
                          }
                        }

                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_off_outlined),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: OutlinedButton(
                              onPressed: () => _unblock(context, targetKey),
                              child: const Text('解除'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _MutedTopicsManageScreen extends StatelessWidget {
  final String uid;

  const _MutedTopicsManageScreen({required this.uid});

  Future<void> _removeTopic(BuildContext context, String topicKey) async {
    if (uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lessInterestedTopics': FieldValue.arrayRemove([topicKey]),
    }, SetOptions(merge: true));
    if (context.mounted) {
      showTopToast(context, '「$topicKey」の制限を解除しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '表示を減らしている話題',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('ログインが必要です'))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data?.data() as Map?;
                final List topics = data?['lessInterestedTopics'] is List
                    ? List.from(data!['lessInterestedTopics'])
                          .map((e) => e.toString().trim())
                          .where((e) => e.isNotEmpty)
                          .toList()
                    : [];

                if (topics.isEmpty) {
                  return const Center(
                    child: Text(
                      '表示を減らしている話題はありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: topics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final topic = topics[index].toString();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(topic),
                        trailing: OutlinedButton(
                          onPressed: () => _removeTopic(context, topic),
                          child: const Text('解除'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
