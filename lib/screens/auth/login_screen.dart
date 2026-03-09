import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_pkg; 
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

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
      data['nicknameSet'] = false;
      if (data['nickname'] == null) data['nickname'] = '사용자';
    }
    await userRef.set(data, SetOptions(merge: true));
  }

  String _generateSnsSecurePassword(String snsId) {
    const String salt = "AUTOKAJI_SECURE_SALT_v1"; 
    final bytes = utf8.encode(snsId + salt);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 20);
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

  Future<void> _handleKakaoLogin() async {
    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      kakao.User kakaoUser = await kakao.UserApi.instance.me();
      
      final String email = kakaoUser.kakaoAccount?.email ?? 'kakao_${kakaoUser.id}@autokaji.com';
      final String password = _generateSnsSecurePassword(kakaoUser.id.toString());
      final String nickname = kakaoUser.kakaoAccount?.profile?.nickname ?? '카카오 사용자';

      UserCredential? userCredential;

      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          throw e;
        }
      }

      if (userCredential != null && userCredential.user != null) {
        User firebaseUser = userCredential.user!;
        
        if (firebaseUser.displayName != nickname) {
          await firebaseUser.updateDisplayName(nickname);
          await firebaseUser.reload();
        }

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

  Future<void> _handleNaverLogin() async {
    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      final res = await FlutterNaverLogin.logIn();
      if (res.account == null) {
        setState(() { _isLoading = false; });
        return;
      }

      final String email = (res.account!.email != null && res.account!.email!.isNotEmpty) 
          ? res.account!.email! 
          : 'naver_${res.account!.id}@autokaji.com';
      final String password = _generateSnsSecurePassword(res.account!.id!);
      final String nickname = (res.account!.nickname != null && res.account!.nickname!.isNotEmpty) 
          ? res.account!.nickname! 
          : ((res.account!.name != null && res.account!.name!.isNotEmpty) 
              ? res.account!.name! 
              : '네이버 사용자');

      UserCredential? userCredential;

      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          throw e;
        }
      }

      if (userCredential != null && userCredential.user != null) {
        User firebaseUser = userCredential.user!;
        
        if (firebaseUser.displayName != nickname) {
          await firebaseUser.updateDisplayName(nickname);
          await firebaseUser.reload();
        }

        await _saveUserToFirestore(
          firebaseUser, 'naver',
          email: email,
          nickname: nickname,
        );
      }
      
      await _saveAutoLoginSetting();

    } catch (e) {
      setState(() { _errorMessage = '네이버 로그인 실패: $e'; });
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  
                  // 로고 영역
                  Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                          boxShadow: AppTheme.shadowPrimary,
                        ),
                        child: const Center(
                          child: Text("🍽️", style: TextStyle(fontSize: 40)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("오토카지", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      const Text("오늘의 맛집, 자동으로 카지!", style: TextStyle(fontSize: 15, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  
                  const SizedBox(height: 48),
                  
                  TextFormField(
                    controller: _emailController,
                    autofillHints: const [AutofillHints.email], 
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '이메일',
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? '올바른 이메일 입력' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    autofillHints: const [AutofillHints.password], 
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onEditingComplete: _handleLogin,
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? '비밀번호 입력' : null,
                  ),
                  
                  Row(children: [
                    Checkbox(
                      value: _isAutoLogin, 
                      activeColor: AppColors.primary, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) => setState(() => _isAutoLogin = v ?? false),
                    ),
                    const Text("자동 로그인", style: TextStyle(color: AppColors.textSecondary)),
                  ]),
                  
                  const SizedBox(height: 8),
                  
                  if (_errorMessage.isNotEmpty) 
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                        ],
                      ),
                    ),
                  
                  AppGradientButton(
                    text: '로그인',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _handleLogin,
                  ),
                  
                  const SizedBox(height: 28),
                  const Row(children: [
                    Expanded(child: Divider(color: AppColors.border)),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("간편 로그인", style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500))),
                    Expanded(child: Divider(color: AppColors.border)),
                  ]),
                  const SizedBox(height: 24),
                  
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _socialButton(
                      onTap: _handleGoogleLogin, 
                      color: Colors.white, 
                      borderColor: AppColors.border, 
                      child: const Text("G", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.google)),
                      label: "Google",
                    ),
                    const SizedBox(width: 20),
                    _socialButton(
                      onTap: _handleNaverLogin, 
                      color: AppColors.naver, 
                      borderColor: AppColors.naver, 
                      child: const Text("N", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                      label: "네이버",
                    ),
                    const SizedBox(width: 20),
                    _socialButton(
                      onTap: _handleKakaoLogin, 
                      color: AppColors.kakao, 
                      borderColor: AppColors.kakao, 
                      child: const Icon(Icons.chat_bubble_rounded, color: AppColors.kakaoText, size: 22),
                      label: "카카오",
                    ),
                  ]),
                  
                  const SizedBox(height: 36),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('계정이 없으신가요?', style: TextStyle(color: AppColors.textSecondary)),
                    TextButton(
                      onPressed: widget.onSignupScreenTap, 
                      child: const Text('회원가입하기', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : _handleGuestLogin, 
                      child: const Text('로그인 없이 둘러보기', style: TextStyle(color: AppColors.textTertiary, fontSize: 14, decoration: TextDecoration.underline, decorationColor: AppColors.textTertiary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({required VoidCallback onTap, required Color color, required Color borderColor, required Widget child, required String label}) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap, 
      child: Column(
        children: [
          Container(
            width: 56, 
            height: 56, 
            decoration: BoxDecoration(
              color: color, 
              shape: BoxShape.circle, 
              border: Border.all(color: borderColor, width: 1.5), 
              boxShadow: AppTheme.shadowSm,
            ), 
            child: Center(child: child),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}