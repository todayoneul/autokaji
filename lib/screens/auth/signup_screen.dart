import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // [추가됨] DB 패키지

class SignupScreen extends StatefulWidget {
  // LoginScreen에서 SignupScreen으로 전환할 때 사용할 함수
  final VoidCallback onLoginScreenTap;

  const SignupScreen({super.key, required this.onLoginScreenTap});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    // 1. 폼 유효성 검사
    if (!_formKey.currentState!.validate()) return;

    // 2. 로딩 상태 시작
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 3. Firebase Auth에 이메일/비밀번호로 계정 생성
      final UserCredential userCredential = 
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 4. [추가됨] Firestore 데이터베이스에 사용자 정보 저장
      if (userCredential.user != null) {
        await FirebaseFirestore.instance
            .collection('users') // 'users'라는 폴더에
            .doc(userCredential.user!.uid) // 유저의 고유 ID(UID)로 문서를 만듦
            .set({
          'email': _emailController.text.trim(),
          'uid': userCredential.user!.uid,
          'createdAt': FieldValue.serverTimestamp(), // 가입 시간 (서버 기준)
          'userType': 'member', // 회원 구분 (나중에 관리자 등 확장을 위해)
        });
      }

      // 5. 회원가입 및 DB 저장 성공 (AuthGate가 감지하여 자동 이동)
      
    } on FirebaseAuthException catch (e) {
      // 에러 처리
      if (e.code == 'weak-password') {
        _errorMessage = '비밀번호가 너무 약합니다.';
      } else if (e.code == 'email-already-in-use') {
        _errorMessage = '이미 사용 중인 이메일입니다.';
      } else {
        _errorMessage = '오류가 발생했습니다: ${e.message}';
      }
    } catch (e) {
      _errorMessage = '알 수 없는 오류가 발생했습니다.';
    }

    // 6. 로딩 상태 종료
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('회원가입'),
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
              // 이메일 입력 필드
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
              // 비밀번호 입력 필드
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return '비밀번호는 6자리 이상이어야 합니다.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 비밀번호 확인 필드
              TextFormField(
                controller: _passwordConfirmController,
                decoration: const InputDecoration(
                  labelText: '비밀번호 확인',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value != _passwordController.text) {
                    return '비밀번호가 일치하지 않습니다.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // 오류 메시지 표시
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              // 회원가입 버튼
              ElevatedButton(
                onPressed: _isLoading ? null : _handleSignup,
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
                    : const Text(
                        '회원가입',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
              
              const SizedBox(height: 20),
              // 로그인 화면으로 돌아가기 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('이미 계정이 있으신가요?'),
                  TextButton(
                    onPressed: widget.onLoginScreenTap,
                    child: const Text(
                      '로그인하기',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}