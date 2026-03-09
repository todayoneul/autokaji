import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autokaji/screens/auth/auth_gate.dart';
import 'package:autokaji/theme/app_colors.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _onIntroEnd(context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstRun', false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 17.0, color: AppColors.textSecondary, height: 1.6);
    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28.0, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 20.0),
      pageColor: AppColors.background,
      imagePadding: EdgeInsets.zero,
    );

    Widget _buildIcon(String emoji, Color bgColor) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 56))),
      );
    }

    return IntroductionScreen(
      globalBackgroundColor: AppColors.background,
      allowImplicitScrolling: true,
      autoScrollDuration: 4000,
      
      pages: [
        PageViewModel(
          title: "오늘 뭐 먹지?",
          body: "결정하기 힘든 식사 메뉴,\n원하는 조건만 고르면 딱! 정해드려요.",
          image: _buildIcon("🍽️", AppColors.primary),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "내 주변 핫플 탐색",
          body: "현재 위치 기반으로\n검증된 맛집을 지도로 확인하세요.",
          image: _buildIcon("🗺️", AppColors.info),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "나만의 미식 기록",
          body: "방문한 맛집을 캘린더에 저장하고,\n나만의 별점과 메모를 남겨보세요.",
          image: _buildIcon("📸", AppColors.accent),
          decoration: pageDecoration,
        ),
      ],
      
      onDone: () => _onIntroEnd(context),
      onSkip: () => _onIntroEnd(context),
      showSkipButton: true,
      skipOrBackFlex: 0,
      nextFlex: 0,
      showBackButton: false,
      
      skip: const Text('건너뛰기', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
      next: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
      ),
      done: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Text('시작하기', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16)),
      ),
      
      dotsDecorator: DotsDecorator(
        size: const Size(10.0, 10.0),
        color: AppColors.border,
        activeSize: const Size(28.0, 10.0),
        activeShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(25.0)),
        ),
        activeColor: AppColors.primary,
      ),
    );
  }
}