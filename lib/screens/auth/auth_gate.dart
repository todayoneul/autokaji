import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autokaji/screens/main_screen.dart';
import 'package:autokaji/screens/auth/login_screen.dart';
import 'package:autokaji/screens/auth/signup_screen.dart';
import 'package:autokaji/screens/auth/nickname_setup_screen.dart';
import 'package:autokaji/providers/auth_provider.dart';
import 'package:autokaji/theme/app_colors.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _showLoginScreen = true;

  void _toggleScreens() {
    setState(() {
      _showLoginScreen = !_showLoginScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        // 1. 로그인된 상태
        if (user != null) {
          // 비회원(게스트)은 바로 메인으로
          if (user.isAnonymous && user.displayName == null) {
            return const MainScreen();
          }

          // 로그인 사용자: Firestore에서 nicknameSet 확인
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: AppColors.background,
                  body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                );
              }

              if (snapshot.hasData && snapshot.data!.exists) {
                final userData = snapshot.data!.data() as Map<String, dynamic>;
                final bool nicknameSet = userData['nicknameSet'] ?? false;

                if (!nicknameSet) {
                  // 닉네임 미설정 → 닉네임 설정 화면
                  return NicknameSetupScreen(
                    suggestedNickname: userData['nickname'] ?? user.displayName,
                  );
                }
              }

              // 닉네임 설정 완료 → 메인 화면
              return const MainScreen();
            },
          );
        }

        // 2. 로그아웃된 상태
        if (_showLoginScreen) {
          return LoginScreen(onSignupScreenTap: _toggleScreens);
        } else {
          return SignupScreen(onLoginScreenTap: _toggleScreens);
        }
      },
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, trace) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('인증 오류 발생: $e')),
      ),
    );
  }
}