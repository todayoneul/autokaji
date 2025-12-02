import 'package:flutter/material.dart';
import 'package:autokaji/screens/home_screen.dart';
import 'package:autokaji/screens/map_screen.dart';
import 'package:autokaji/screens/calendar_screen.dart';
import 'package:autokaji/screens/settings_screen.dart';

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
        // IndexedStack을 사용하면 탭 전환 시 상태가 유지됩니다 (지도가 다시 로딩되지 않음)
        // 하지만 여기서는 데이터 전달 시 갱신을 위해 일단 단순 전환 유지
        // 데이터 갱신을 위해 key를 주거나, MapScreen 내부에서 didUpdateWidget 처리 필요
        child: widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: '지도',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: '캘린더',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey[500],
        selectedFontSize: 12,
        unselectedFontSize: 12,
        showUnselectedLabels: true,
        elevation: 1,
      ),
    );
  }
}