import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autokaji/screens/auth/auth_gate.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  // 온보딩 완료 시 실행되는 함수
  void _onIntroEnd(context) async {
    // 1. '첫 실행 아님'으로 표시 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstRun', false);

    // 2. 로그인 화면(AuthGate)으로 이동 (뒤로가기 방지)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 공통 스타일 정의
    const bodyStyle = TextStyle(fontSize: 19.0);
    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28.0, fontWeight: FontWeight.w700),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      pageColor: Colors.white,
      imagePadding: EdgeInsets.zero,
    );

    return IntroductionScreen(
      globalBackgroundColor: Colors.white,
      allowImplicitScrolling: true,
      autoScrollDuration: 3000, // 3초마다 자동 슬라이드 (선택사항)
      
      // [페이지 구성]
      pages: [
        // 1페이지: 메뉴 추천
        PageViewModel(
          title: "오늘 뭐 먹지?",
          body: "결정하기 힘든 식사 메뉴,\n원하는 조건만 고르면 딱! 정해드려요.",
          image: const Icon(Icons.restaurant_menu, size: 100, color: Colors.orange),
          decoration: pageDecoration,
        ),
        // 2페이지: 맛집 지도
        PageViewModel(
          title: "내 주변 맛집 탐색",
          body: "현재 위치 450m 반경의\n검증된 맛집을 지도로 확인하세요.",
          image: const Icon(Icons.map_outlined, size: 100, color: Colors.blue),
          decoration: pageDecoration,
        ),
        // 3페이지: 캘린더 기록
        PageViewModel(
          title: "나만의 미식 기록",
          body: "방문한 맛집을 캘린더에 저장하고,\n나만의 별점과 메모를 남겨보세요.",
          image: const Icon(Icons.calendar_today_rounded, size: 100, color: Colors.purple),
          decoration: pageDecoration,
        ),
      ],
      
      // [버튼 설정]
      onDone: () => _onIntroEnd(context),
      onSkip: () => _onIntroEnd(context), // 건너뛰기 눌러도 이동
      showSkipButton: true,
      skipOrBackFlex: 0,
      nextFlex: 0,
      showBackButton: false,
      
      // [버튼 스타일]
      skip: const Text('건너뛰기', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
      next: const Icon(Icons.arrow_forward, color: Colors.black),
      done: const Text('시작하기', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
      
      // [인디케이터 스타일]
      dotsDecorator: const DotsDecorator(
        size: Size(10.0, 10.0),
        color: Color(0xFFBDBDBD),
        activeSize: Size(22.0, 10.0),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(25.0)),
        ),
        activeColor: Colors.black,
      ),
    );
  }
}