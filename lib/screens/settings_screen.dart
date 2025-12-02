import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart'; // [신규] 버전 정보
import 'package:autokaji/screens/edit_profile_screen.dart'; // [신규] 프로필 수정 화면

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isNotificationEnabled = true;
  bool _isLocationServiceEnabled = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  Future<void> _handleAuthAction() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  // [신규] 앱 버전 정보 다이얼로그
  Future<void> _showAppVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("앱 정보"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("앱 이름: ${packageInfo.appName}"),
            Text("버전: ${packageInfo.version}"),
            Text("빌드 번호: ${packageInfo.buildNumber}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, left: 16.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
    );
  }

  final Widget _divider = const Divider(height: 1, indent: 16, endIndent: 16);

  @override
  Widget build(BuildContext context) {
    final bool isGuest = _currentUser == null || _currentUser!.isAnonymous;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          // 1. 사용자 프로필 섹션 (StreamBuilder로 실시간 데이터 반영)
          StreamBuilder<DocumentSnapshot>(
            stream: isGuest 
                ? null // 게스트면 스트림 없음
                : FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).snapshots(),
            builder: (context, snapshot) {
              String nickname = "사용자";
              String email = _currentUser?.email ?? "";

              if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                nickname = data['nickname'] ?? "닉네임을 설정해주세요";
              }

              // 게스트일 때 덮어쓰기
              if (isGuest) {
                nickname = "비회원";
                email = "로그인이 필요합니다";
              }

              return ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: isGuest ? Colors.grey[300] : const Color(0xFF030213),
                  child: Icon(
                    Icons.person,
                    color: isGuest ? Colors.grey[600] : Colors.white,
                  ),
                ),
                title: Text(
                  nickname,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(email),
                // 게스트가 아닐 때만 프로필 수정 화면으로 이동
                trailing: isGuest ? null : const Icon(Icons.edit, size: 16),
                onTap: () {
                  if (!isGuest) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditProfileScreen(
                          // 현재 닉네임이 "닉네임을..." 이면 빈칸으로 보냄
                          currentNickname: nickname == "닉네임을 설정해주세요" ? "" : nickname,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          ),

          _buildSectionHeader('계정'),
          
          ListTile(
            leading: Icon(
              isGuest ? Icons.login : Icons.logout,
              color: isGuest ? Colors.blue : Colors.red,
            ),
            title: Text(
              isGuest ? '로그인 / 회원가입' : '로그아웃',
              style: TextStyle(
                color: isGuest ? Colors.blue : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: _handleAuthAction,
          ),
          
          if (!isGuest) ...[
            _divider,
            // [수정됨] 프로필 관리 버튼도 활성화
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('프로필 관리'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                 // 프로필 수정 화면으로 이동 (닉네임 데이터는 다시 로드됨)
                 // 간편하게 빈 문자열로 보내도 내부에서 처리하거나,
                 // 위쪽 StreamBuilder 데이터를 전달받는 구조가 좋지만
                 // 여기서는 심플하게 이동만 시킵니다.
                 Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EditProfileScreen(currentNickname: ""),
                    ),
                  );
              },
            ),
            _divider,
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('개인정보 보호'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {},
            ),
          ],

          _buildSectionHeader('앱 설정'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('알림'),
            value: _isNotificationEnabled,
            onChanged: (bool value) {
              setState(() {
                _isNotificationEnabled = value;
              });
            },
            activeColor: Colors.black,
          ),
          _divider,
          SwitchListTile(
            secondary: const Icon(Icons.location_on_outlined),
            title: const Text('위치 서비스'),
            value: _isLocationServiceEnabled,
            onChanged: (bool value) {
              setState(() {
                _isLocationServiceEnabled = value;
              });
            },
            activeColor: Colors.black,
          ),

          _buildSectionHeader('지원'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('도움말'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          _divider,
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 정보'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            // [수정됨] 앱 버전 다이얼로그 띄우기
            onTap: _showAppVersion,
          ),
        ],
      ),
    );
  }
}