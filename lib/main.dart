import 'package:flutter/material.dart';
import 'package:autokaji/screens/auth/auth_gate.dart';
import 'package:autokaji/screens/onboarding_screen.dart'; // [신규]
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting(); 
  
  KakaoSdk.init(
      nativeAppKey: dotenv.env['KAKAO_NATIVE_APP_KEY'],
    );


  final prefs = await SharedPreferences.getInstance();
  
  // [신규] 첫 실행 여부 확인 (기본값 true)
  final bool isFirstRun = prefs.getBool('isFirstRun') ?? true;
  
  // 자동 로그인 설정 확인 (기본값 false)
  final bool isAutoLogin = prefs.getBool('isAutoLogin') ?? false;

  // 자동 로그인이 꺼져 있으면 강제 로그아웃
  if (!isAutoLogin) {
    await FirebaseAuth.instance.signOut();
  }

  // MyApp에 첫 실행 여부 전달
  runApp(MyApp(isFirstRun: isFirstRun));
}

class MyApp extends StatelessWidget {
  final bool isFirstRun;

  const MyApp({super.key, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'autokaji',
      theme: ThemeData(
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Pretendard',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
      ),
      // [핵심] 첫 실행이면 온보딩, 아니면 인증 게이트로 이동
      home: isFirstRun ? const OnboardingScreen() : const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}