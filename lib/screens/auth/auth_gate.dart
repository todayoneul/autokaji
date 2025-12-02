import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autokaji/screens/main_screen.dart';
import 'package:autokaji/screens/auth/login_screen.dart';
import 'package:autokaji/screens/auth/signup_screen.dart';
// [삭제됨] import 'package:autokaji/screens/auth/mfa_setup_screen.dart';
// [삭제됨] import 'package:autokaji/screens/auth/mfa_verify_screen.dart'; 

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showLoginScreen = true;

  void _toggleScreens() {
    setState(() {
      _showLoginScreen = !_showLoginScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    // [삭제됨] MFA Resolver 관련 로직 모두 삭제

    // Firebase의 인증 상태 스트림을 구독
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // 1. 인증 상태 로딩 중...
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. 로그인된 상태 (사용자 데이터가 있음)
        if (snapshot.hasData) {
          // [수정됨] MFA 확인 로직(FutureBuilder)을 제거하고
          // 1차 로그인 성공 시 즉시 MainScreen 반환
          return const MainScreen();
        }

        // 3. 로그아웃된 상태 (사용자 데이터 없음)
        if (_showLoginScreen) {
          return LoginScreen(
            onSignupScreenTap: _toggleScreens,
            // [삭제됨] onMfaRequired 콜백
          );
        } else {
          return SignupScreen(
            onLoginScreenTap: _toggleScreens,
          );
        }
      },
    );
  }
}