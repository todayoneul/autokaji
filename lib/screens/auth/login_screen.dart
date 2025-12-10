import 'dart:convert';
import 'package:crypto/crypto.dart'; // [신규] 비밀번호 생성을 위한 암호화 패키지
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_pkg; 
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
  bool _isAutoLogin = false;

  final google_pkg.GoogleSignIn _googleSignIn = google_pkg.GoogleSignIn();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveAutoLoginSetting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAutoLogin', _isAutoLogin);
  }

  Future<void> _saveUserToFirestore(User user, String type, {String? nickname, String? email, int? kakaoId}) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final data = {
      'uid': user.uid,
      'email': email ?? user.email ?? '',
      'userType': type,
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    if (nickname != null) data['nickname'] = nickname;
    if (kakaoId != null) data['kakaoId'] = kakaoId;

    final docSnapshot = await userRef.get();
    if (!docSnapshot.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      if (data['nickname'] == null) data['nickname'] = '사용자';
    }
    await userRef.set(data, SetOptions(merge: true));
  }

  // [신규] 카카오 ID 기반 비밀번호 생성기 (보안용 Salt 사용)
  String _generateSecurePassword(String kakaoId) {
    // 앱만의 비밀키 (외부 유출 금지)
    const String salt = "AUTOKAJI_SECURE_SALT_v1"; 
    final bytes = utf8.encode(kakaoId + salt);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 20); // 20자리 비밀번호 생성
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    TextInput.finishAutofillContext(shouldSave: true); 

    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (credential.user != null) {
        await _saveUserToFirestore(credential.user!, 'email');
      }
      await _saveAutoLoginSetting();
      await Future.delayed(const Duration(milliseconds: 500));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found') {
        _errorMessage = '이메일 또는 비밀번호가 일치하지 않습니다.';
      } else {
        _errorMessage = '오류가 발생했습니다: ${e.message}';
      }
    } catch (e) {
      _errorMessage = '알 수 없는 오류가 발생했습니다.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final google_pkg.GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) { setState(() { _isLoading = false; }); return; }

      final google_pkg.GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      if (userCredential.user != null) {
        await _saveUserToFirestore(
          userCredential.user!, 'google',
          email: googleUser.email,
          nickname: googleUser.displayName,
        );
      }
      await _saveAutoLoginSetting();
    } catch (e) {
      setState(() { _errorMessage = '구글 로그인 실패: $e'; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // [핵심 수정] 카카오 로그인 -> 이메일/비번 방식으로 변환
  Future<void> _handleKakaoLogin() async {
    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      kakao.OAuthToken token;
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      kakao.User kakaoUser = await kakao.UserApi.instance.me();
      
      // 1. 카카오 정보 추출
      // 이메일이 없으면 가짜 이메일 생성 (ID 기반)
      final String email = kakaoUser.kakaoAccount?.email ?? 'kakao_${kakaoUser.id}@autokaji.com';
      final String password = _generateSecurePassword(kakaoUser.id.toString());
      final String nickname = kakaoUser.kakaoAccount?.profile?.nickname ?? '카카오 사용자';

      UserCredential? userCredential;

      // 2. Firebase 로그인 시도
      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // 3. 계정이 없으면 회원가입 시도
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          throw e; // 다른 오류는 던짐
        }
      }

      // 4. 성공 처리
      if (userCredential != null && userCredential.user != null) {
        User firebaseUser = userCredential.user!;
        
        // 프로필 이름 업데이트
        if (firebaseUser.displayName != nickname) {
          await firebaseUser.updateDisplayName(nickname);
          await firebaseUser.reload();
        }

        // DB 저장
        await _saveUserToFirestore(
          firebaseUser, 'kakao',
          email: email,
          nickname: nickname,
          kakaoId: kakaoUser.id,
        );
      }
      
      await _saveAutoLoginSetting();

    } catch (e) {
      setState(() { _errorMessage = '카카오 로그인 실패: $e'; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await _saveAutoLoginSetting();
    } catch (e) {
      setState(() { _errorMessage = '비회원 로그인 실패: $e'; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('로그인'), backgroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                TextFormField(
                  controller: _emailController,
                  autofillHints: const [AutofillHints.email], 
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '이메일', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => (v == null || !v.contains('@')) ? '올바른 이메일 입력' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  autofillHints: const [AutofillHints.password], 
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: _handleLogin,
                  decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => (v == null || v.isEmpty) ? '비밀번호 입력' : null,
                ),
                Row(children: [
                  Checkbox(value: _isAutoLogin, activeColor: Colors.black, onChanged: (v) => setState(() => _isAutoLogin = v ?? false)),
                  const Text("자동 로그인"),
                ]),
                const SizedBox(height: 16),
                if (_errorMessage.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
                ElevatedButton(onPressed: _isLoading ? null : _handleLogin, style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: _isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('로그인', style: TextStyle(fontSize: 16))),
                const SizedBox(height: 20),
                const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("또는", style: TextStyle(color: Colors.grey))), Expanded(child: Divider())]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _socialButton(onTap: _handleGoogleLogin, color: Colors.white, borderColor: Colors.grey[300]!, child: const Text("G", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue))),
                  const SizedBox(width: 16),
                  _socialButton(onTap: _handleKakaoLogin, color: const Color(0xFFFEE500), borderColor: const Color(0xFFFEE500), child: const Icon(Icons.chat_bubble, color: Colors.black, size: 24)),
                ]),
                const SizedBox(height: 40),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('계정이 없으신가요?'), TextButton(onPressed: widget.onSignupScreenTap, child: const Text('회원가입하기', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))]),
                const SizedBox(height: 20), const Divider(), const SizedBox(height: 10),
                TextButton(onPressed: _isLoading ? null : _handleGuestLogin, child: const Text('로그인 없이 둘러보기', style: TextStyle(color: Colors.grey, fontSize: 16, decoration: TextDecoration.underline))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({required VoidCallback onTap, required Color color, required Color borderColor, required Widget child}) {
    return InkWell(onTap: _isLoading ? null : onTap, child: Container(width: 50, height: 50, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]), child: Center(child: child)));
  }
}