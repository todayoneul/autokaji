import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_pkg;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:autokaji/screens/auth/auth_gate.dart';

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

  // [신규] 닉네임 변경 다이얼로그
  void _showEditNicknameDialog() {
    final TextEditingController controller = TextEditingController(text: _userData?['nickname'] ?? "");
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("닉네임 변경"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "새 닉네임",
            border: OutlineInputBorder(),
          ),
          maxLength: 10,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _updateNickname(controller.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  // [신규] 닉네임 업데이트 로직 (Auth + Firestore)
  Future<void> _updateNickname(String newName) async {
    if (_currentUser == null) return;

    setState(() => _isLoading = true);
    try {
      // 1. Firebase Auth 프로필 업데이트
      await _currentUser!.updateDisplayName(newName);
      await _currentUser!.reload(); // 정보 갱신
      _currentUser = FirebaseAuth.instance.currentUser; // 갱신된 객체 다시 가져오기

      // 2. Firestore DB 업데이트
      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
        'nickname': newName,
      });

      // 3. 로컬 상태 업데이트
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
        title: const Text("회원 탈퇴"),
        content: const Text("정말로 탈퇴하시겠습니까?\n저장된 모든 맛집 기록과 친구 정보가 삭제됩니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("탈퇴하기", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    String displayName = "비회원 게스트";
    String email = "로그인이 필요합니다";
    String userType = "guest";
    Color typeColor = Colors.grey;

    if (!_isGuest) {
      displayName = _userData?['nickname'] ?? _currentUser?.displayName ?? "사용자";
      email = _userData?['email'] ?? _currentUser?.email ?? "";
      userType = _userData?['userType'] ?? "email";
      
      if (userType == 'kakao') typeColor = const Color(0xFFFEE500);
      else if (userType == 'google') typeColor = Colors.blue;
      else typeColor = Colors.black;
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          
          // [프로필 카드]
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.grey[100],
                  child: Icon(Icons.person, size: 36, color: Colors.grey[400]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // [수정] 닉네임 + 수정 버튼 행
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName, 
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isGuest) // 비회원이 아닐 때만 수정 버튼 노출
                            GestureDetector(
                              onTap: _showEditNicknameDialog,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Icon(Icons.edit, size: 18, color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (email.isNotEmpty) Text(email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 8),
                      
                      if (!_isGuest)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: typeColor.withOpacity(0.5), width: 0.5),
                          ),
                          child: Text(
                            userType == 'kakao' ? '카카오 로그인' : (userType == 'google' ? '구글 로그인' : '이메일 로그인'),
                            style: TextStyle(fontSize: 11, color: typeColor == const Color(0xFFFEE500) ? Colors.brown : typeColor, fontWeight: FontWeight.bold),
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
               icon: Icons.login, 
               text: "로그인 / 회원가입", 
               color: Colors.blue,
               onTap: _handleLogout
             ),

          if (!_isGuest) ...[
            _buildMenuTile(
              icon: Icons.logout, 
              text: "로그아웃", 
              color: Colors.black,
              onTap: _handleLogout
            ),
            _buildMenuTile(
              icon: Icons.person_off_outlined, 
              text: "회원 탈퇴", 
              color: Colors.red[300]!,
              onTap: _handleDeleteAccount
            ),
          ],
          
          const SizedBox(height: 20),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("앱 정보", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          _buildMenuTile(icon: Icons.info_outline, text: "버전 정보", trailing: "1.0.0"),
          _buildMenuTile(icon: Icons.description_outlined, text: "오픈소스 라이선스"),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String text, Color color = Colors.black, VoidCallback? onTap, String? trailing}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      trailing: trailing != null 
          ? Text(trailing, style: const TextStyle(color: Colors.grey)) 
          : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      onTap: onTap,
    );
  }
}