import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/screens/main_screen.dart';
import 'package:autokaji/screens/auth/login_screen.dart';
import 'package:autokaji/screens/auth/signup_screen.dart';
import 'package:autokaji/providers/auth_provider.dart';

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
    // Riverpod을 통해 인증 상태 스트림을 구독
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        // 1. 로그인된 상태 (사용자 데이터가 있음)
        if (user != null) {
          return const MainScreen();
        }
        // 2. 로그아웃된 상태 (사용자 데이터 없음)
        if (_showLoginScreen) {
          return LoginScreen(
            onSignupScreenTap: _toggleScreens,
          );
        } else {
          return SignupScreen(
            onLoginScreenTap: _toggleScreens,
          );
        }
      },
      // 3. 인증 상태 로딩 중
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // 4. 오류 발생 시
      error: (e, trace) => Scaffold(body: Center(child: Text('인증 오류 발생: $e'))),
    );
  }
}