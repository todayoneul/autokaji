import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_pkg;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:autokaji/screens/auth/auth_gate.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    _currentUser = FirebaseAuth.instance.currentUser;

    if (_currentUser != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get();
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
          });
        }
      } catch (e) {
        debugPrint("유저 정보 로드 실패: $e");
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool get _isGuest {
    if (_currentUser == null) return true;
    if (_currentUser!.isAnonymous && _currentUser!.displayName == null) return true;
    return false;
  }

  void _showEditNicknameDialog() {
    final TextEditingController controller = TextEditingController(text: _userData?['nickname'] ?? "");
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        title: const Text("닉네임 변경", style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "새 닉네임",
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: BorderSide.none),
          ),
          maxLength: 10,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _updateNickname(controller.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateNickname(String newName) async {
    if (_currentUser == null) return;

    setState(() => _isLoading = true);
    try {
      await _currentUser!.updateDisplayName(newName);
      await _currentUser!.reload();
      _currentUser = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
        'nickname': newName,
      });

      setState(() {
        if (_userData != null) {
          _userData!['nickname'] = newName;
        }
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("닉네임이 변경되었습니다.")));

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("변경 실패: $e")));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoading = true);
    try {
      if (_userData?['userType'] == 'google') {
        await google_pkg.GoogleSignIn().signOut();
      } else if (_userData?['userType'] == 'kakao') {
        try {
          await kakao.UserApi.instance.logout();
        } catch (e) {
          debugPrint("카카오 로그아웃 오류 (무시): $e");
        }
      }

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("로그아웃 실패: $e")));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        title: const Text("회원 탈퇴", style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("정말로 탈퇴하시겠습니까?\n저장된 모든 맛집 기록과 친구 정보가 삭제됩니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소", style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("탈퇴하기", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      if (_currentUser != null) {
        await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).delete();
      }
      await _currentUser?.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("탈퇴 실패. 다시 로그인 후 시도해주세요.")));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));

    String displayName = "비회원 게스트";
    String email = "로그인이 필요합니다";
    String userType = "guest";
    Color typeColor = AppColors.textTertiary;
    IconData typeIcon = Icons.person_outline_rounded;

    if (!_isGuest) {
      displayName = _userData?['nickname'] ?? _currentUser?.displayName ?? "사용자";
      email = _userData?['email'] ?? _currentUser?.email ?? "";
      userType = _userData?['userType'] ?? "email";
      
      if (userType == 'kakao') { typeColor = AppColors.kakao; typeIcon = Icons.chat_bubble_rounded; }
      else if (userType == 'google') { typeColor = AppColors.google; typeIcon = Icons.g_mobiledata_rounded; }
      else { typeColor = AppColors.primary; typeIcon = Icons.email_rounded; }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("마이페이지"),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          
          // [프로필 카드]
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.secondaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              boxShadow: AppTheme.shadowLg,
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(Icons.person_rounded, size: 32, color: Colors.white70),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName, 
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isGuest)
                            GestureDetector(
                              onTap: _showEditNicknameDialog,
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8.0),
                                child: Icon(Icons.edit_rounded, size: 18, color: Colors.white60),
                              ),
                            ),
                        ],
                      ),
                      if (email.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(email, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ),
                      const SizedBox(height: 10),
                      
                      if (!_isGuest)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(typeIcon, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                userType == 'kakao' ? '카카오 로그인' : (userType == 'google' ? '구글 로그인' : '이메일 로그인'),
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          if (_isGuest)
             _buildMenuTile(
               icon: Icons.login_rounded, 
               text: "로그인 / 회원가입", 
               color: AppColors.primary,
               iconBg: AppColors.primarySurface,
               onTap: _handleLogout
             ),

          if (!_isGuest) ...[
            _buildMenuTile(
              icon: Icons.logout_rounded, 
              text: "로그아웃", 
              color: AppColors.textPrimary,
              iconBg: AppColors.surfaceVariant,
              onTap: _handleLogout
            ),
            _buildMenuTile(
              icon: Icons.person_off_outlined, 
              text: "회원 탈퇴", 
              color: AppColors.error,
              iconBg: AppColors.error.withOpacity(0.1),
              onTap: _handleDeleteAccount
            ),
          ],
          
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            color: AppColors.divider,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text("앱 정보", style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          _buildMenuTile(icon: Icons.info_outline_rounded, text: "버전 정보", iconBg: AppColors.surfaceVariant, trailing: "1.0.0"),
          _buildMenuTile(icon: Icons.description_outlined, text: "오픈소스 라이선스", iconBg: AppColors.surfaceVariant),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String text, Color color = AppColors.textPrimary, Color iconBg = AppColors.surfaceVariant, VoidCallback? onTap, String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
        trailing: trailing != null 
            ? Text(trailing, style: const TextStyle(color: AppColors.textTertiary, fontSize: 14)) 
            : const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        onTap: onTap,
      ),
    );
  }
}