import 'package:flutter/material.dart';
import 'package:autokaji/screens/home_screen.dart';
import 'package:autokaji/screens/map_screen.dart';
import 'package:autokaji/screens/calendar_screen.dart';
import 'package:autokaji/screens/settings_screen.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';

// [신규] 지도 이동을 위한 데이터 모델
class TargetPlace {
  final String name;
  final double lat;
  final double lng;

  TargetPlace({required this.name, required this.lat, required this.lng});
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  
  // [신규] 홈 화면에서 선택된 장소 정보 저장
  TargetPlace? _targetPlace;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // 탭을 직접 누를 땐 타겟 초기화 (선택사항)
      if (index != 1) _targetPlace = null;
    });
  }

  // [신규] 홈 화면에서 "여기 갈래요"를 눌렀을 때 실행될 함수
  void _onPlaceSelected(String name, double lat, double lng) {
    setState(() {
      _targetPlace = TargetPlace(name: name, lat: lat, lng: lng);
      _selectedIndex = 1; // 지도 탭으로 이동
    });
  }

  @override
  Widget build(BuildContext context) {
    // [수정] 상태 전달을 위해 build 메서드 안으로 이동
    final List<Widget> widgetOptions = <Widget>[
      HomeScreen(onPlaceSelected: _onPlaceSelected), // 콜백 전달
      MapScreen(initialTarget: _targetPlace),        // 데이터 전달
      const CalendarScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: widgetOptions.elementAt(_selectedIndex),
      ),
      extendBody: true,
      bottomNavigationBar: _buildFloatingNavBar(),
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: AppColors.secondary.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, '홈'),
              _buildNavItem(1, Icons.map_rounded, Icons.map_outlined, '지도'),
              _buildNavItem(2, Icons.calendar_month_rounded, Icons.calendar_month_outlined, '캘린더'),
              _buildNavItem(3, Icons.person_rounded, Icons.person_outlined, '마이'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 18 : 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              size: 22,
              color: isSelected ? Colors.white : AppColors.textTertiary,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}