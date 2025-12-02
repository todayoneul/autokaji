import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [신규]

class LoginScreen extends StatefulWidget {
  final VoidCallback onSignupScreenTap;

  const LoginScreen({
    super.key,
    required this.onSignupScreenTap,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _errorMessage = '';
  
  // [신규] 자동 로그인 체크 상태 (기본값 false)
  bool _isAutoLogin = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // [설정 저장 함수]
  Future<void> _saveAutoLoginSetting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAutoLogin', _isAutoLogin);
  }

  // 이메일 로그인 로직
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      // [신규] 로그인 성공 시 자동 로그인 설정 저장
      await _saveAutoLoginSetting();

    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found') {
        _errorMessage = '이메일 또는 비밀번호가 일치하지 않습니다.';
      } else {
        _errorMessage = '오류가 발생했습니다: ${e.message}';
      }
    } catch (e) {
      _errorMessage = '알 수 없는 오류가 발생했습니다.';
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 비회원 로그인 로직
  Future<void> _handleGuestLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.signInAnonymously();
      // [신규] 비회원도 자동 로그인 설정 저장 (원하면 유지되도록)
      await _saveAutoLoginSetting();
    } catch (e) {
      setState(() {
        _errorMessage = '비회원 로그인 실패: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('로그인'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // 이메일
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return '올바른 이메일을 입력하세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 비밀번호
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력하세요.';
                  }
                  return null;
                },
              ),
              
              // [신규] 자동 로그인 체크박스
              Row(
                children: [
                  Checkbox(
                    value: _isAutoLogin,
                    activeColor: Colors.black,
                    onChanged: (value) {
                      setState(() {
                        _isAutoLogin = value ?? false;
                      });
                    },
                  ),
                  const Text("자동 로그인"),
                ],
              ),

              const SizedBox(height: 16),

              // 에러 메시지
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              // 로그인 버튼
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('로그인', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 20),
              
              // 회원가입 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('계정이 없으신가요?'),
                  TextButton(
                    onPressed: widget.onSignupScreenTap,
                    child: const Text(
                      '회원가입하기',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
              const Divider(),
              const SizedBox(height: 20),

              // 비회원 로그인 버튼
              TextButton(
                onPressed: _isLoading ? null : _handleGuestLogin,
                child: const Text(
                  '로그인 없이 둘러보기',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}