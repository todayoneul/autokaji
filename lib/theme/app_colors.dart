import 'package:flutter/material.dart';

/// autokaji 앱 전용 컬러 팔레트
/// Warm Coral + Deep Navy 컬러 시스템
class AppColors {
  AppColors._();

  // ─── Primary ───
  static const Color primary = Color(0xFFFF6B6B);       // Warm Coral
  static const Color primaryLight = Color(0xFFFF8E8E);
  static const Color primaryDark = Color(0xFFE55555);
  static const Color primarySurface = Color(0xFFFFF0F0);  // 매우 연한 코랄

  // ─── Secondary ───
  static const Color secondary = Color(0xFF2C3E50);      // Deep Navy
  static const Color secondaryLight = Color(0xFF3D566E);
  static const Color secondaryDark = Color(0xFF1A252F);

  // ─── Accent ───
  static const Color accent = Color(0xFFF39C12);          // Golden Amber (별점 등)
  static const Color accentLight = Color(0xFFFFD93D);
  static const Color accentSurface = Color(0xFFFFF8E1);

  // ─── Surface / Background ───
  static const Color background = Color(0xFFFFF8F0);      // Soft Cream
  static const Color surface = Color(0xFFFFFFFF);          // Pure White
  static const Color surfaceVariant = Color(0xFFF5F1EB);   // 약간 어두운 크림
  static const Color cardBackground = Color(0xFFFFFFFF);

  // ─── Text ───
  static const Color textPrimary = Color(0xFF1A1A2E);     // Dark Charcoal
  static const Color textSecondary = Color(0xFF6C7B8A);   // Medium Gray
  static const Color textTertiary = Color(0xFFB0BEC5);    // Light Gray
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnSecondary = Color(0xFFFFFFFF);

  // ─── Border / Divider ───
  static const Color border = Color(0xFFE8E0D8);
  static const Color borderLight = Color(0xFFF0EAE2);
  static const Color divider = Color(0xFFF0EAE2);

  // ─── Semantic ───
  static const Color success = Color(0xFF27AE60);
  static const Color error = Color(0xFFE74C3C);
  static const Color warning = Color(0xFFF39C12);
  static const Color info = Color(0xFF3498DB);

  // ─── Social ───
  static const Color kakao = Color(0xFFFEE500);
  static const Color kakaoText = Color(0xFF3C1E1E);
  static const Color google = Color(0xFF4285F4);
  static const Color naver = Color(0xFF03C75A);

  // ─── Gradients ───
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2C3E50), Color(0xFF3D566E)],
  );

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6B), Color(0xFFF39C12)],
  );

  static const LinearGradient statsGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2C3E50), Color(0xFF4A6741)],
  );

  // ─── Shimmer ───
  static const Color shimmerBase = Color(0xFFF0EAE2);
  static const Color shimmerHighlight = Color(0xFFFFF8F0);
}
