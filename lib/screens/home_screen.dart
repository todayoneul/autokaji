import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart'; // [신규]
import 'package:cloud_firestore/cloud_firestore.dart'; // [신규]
import 'package:autokaji/screens/friend_screen.dart'; // 친구 관리 화면
import 'package:autokaji/screens/tag_notification_screen.dart'; // [신규] 알림 화면

class HomeScreen extends StatefulWidget {
  final Function(String name, double lat, double lng) onPlaceSelected;

  const HomeScreen({super.key, required this.onPlaceSelected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String get kGoogleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isFoodMode = true;
  bool _isLoading = false;
  Position? _currentPosition;

  final Set<String> _selectedFoodTypes = {};
  final Set<String> _selectedMenuTypes = {};

  @override
  void initState() {
    super.initState();
    _initCurrentLocation();
    _checkTagRequests(); // [신규] 앱 실행 시 알림 체크
  }

  // [신규] 안 읽은 태그 요청 확인 및 팝업
  Future<void> _checkTagRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tag_requests')
          .where('toUid', isEqualTo: user.uid)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        // 알림 팝업 띄우기
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("새로운 알림 🔔"),
            content: Text("${snapshot.docs.length}건의 태그 요청이 도착했습니다.\n확인하시겠습니까?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("나중에", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // 알림 화면으로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TagNotificationScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text("확인하기"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("알림 체크 오류: $e");
    }
  }

  Future<void> _initCurrentLocation() async {
    try {
      Position position = await _determinePosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      debugPrint("초기 위치 탐색 실패: $e");
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('위치 서비스가 꺼져 있습니다.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('위치 권한이 거부되었습니다.');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception('위치 권한이 영구적으로 거부되었습니다.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  String? _getPhotoUrl(List<dynamic>? photos) {
    if (photos == null || photos.isEmpty) return null;
    final String photoReference = photos[0]['photo_reference'];
    return 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$kGoogleApiKey';
  }

  Future<void> _launchNaverMapSearch(String query) async {
    final Uri appUrl = Uri.parse('nmap://search?query=$query&appname=com.gyuhan.autokaji');
    final Uri webUrl = Uri.parse('https://m.map.naver.com/search2/search.naver?query=$query');

    try {
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl);
      } else {
        await launchUrl(webUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("네이버 지도 실행 중 오류: $e")),
        );
      }
    }
  }

  Future<void> _recommendRealRestaurant() async {
    String queryTerms = "";
    if (_selectedFoodTypes.isNotEmpty) queryTerms += "${_selectedFoodTypes.join(" ")} ";
    if (_selectedMenuTypes.isNotEmpty) queryTerms += "${_selectedMenuTypes.join(" ")} ";
    
    String finalQuery = queryTerms.trim().isEmpty ? "맛집" : "$queryTerms 맛집";

    setState(() {
      _isLoading = true;
    });

    try {
      Position position;
      if (_currentPosition != null) {
        position = _currentPosition!;
      } else {
        position = await _determinePosition();
        _currentPosition = position;
      }

      final String url =
          'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$finalQuery&location=${position.latitude},${position.longitude}&radius=300&language=ko&key=$kGoogleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'];

          final List<dynamic> candidates = results.where((place) {
            final double rating = (place['rating'] ?? 0).toDouble();
            final geometry = place['geometry']['location'];
            final double placeLat = geometry['lat'];
            final double placeLng = geometry['lng'];

            final double distanceInMeters = Geolocator.distanceBetween(
              position.latitude, position.longitude, placeLat, placeLng
            );

            return rating >= 3.2 && distanceInMeters <= 300;
          }).toList();

          if (candidates.isEmpty) {
            _showNaverFallbackDialog(finalQuery);
          } else {
            final random = Random();
            final selectedPlace = candidates[random.nextInt(candidates.length)];
            _showResultDialog(selectedPlace);
          }
        } else {
          _showNaverFallbackDialog(finalQuery);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("서버 통신 오류가 발생했습니다.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류 발생: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showNaverFallbackDialog(String query) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("주변에 맛집이 없어요 😭"),
        content: const Text("300m 이내에 조건에 맞는 가게를 찾지 못했습니다.\n네이버 지도로 더 자세히 찾아볼까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchNaverMapSearch(query);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF03C75A),
              foregroundColor: Colors.white,
            ),
            child: const Text("네이버 지도로 찾기"),
          )
        ],
      ),
    );
  }

  void _showResultDialog(Map<String, dynamic>? place, {String? msg}) {
    if (place == null) return;

    final String name = place['name'];
    final String address = place['formatted_address'] ?? "주소 정보 없음";
    final double rating = (place['rating'] ?? 0).toDouble();
    final int userRatingsTotal = place['user_ratings_total'] ?? 0;
    final String? photoUrl = _getPhotoUrl(place['photos']);
    
    final geometry = place['geometry']['location'];
    final double lat = geometry['lat'];
    final double lng = geometry['lng'];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photoUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  photoUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 150, color: Colors.grey[200], 
                    child: const Center(child: Icon(Icons.restaurant, size: 50, color: Colors.grey)),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: const Center(child: Icon(Icons.store, size: 60, color: Colors.grey)),
              ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Text("오늘의 추천 맛집! 🍖", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      Text(" $rating ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("($userRatingsTotal reviews)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    address,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 30),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); 
                        widget.onPlaceSelected(name, lat, lng);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("여기 갈래요!", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _recommendRealRestaurant();
                    },
                    child: const Text("다른 곳 추천받기", style: TextStyle(color: Colors.grey)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isFoodMode = true),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: _isFoodMode ? const Color(0xFF030213) : const Color(0xFFECECF0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text('오늘 뭐 먹지', style: TextStyle(color: _isFoodMode ? Colors.white : const Color(0xFF717182), fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isFoodMode = false),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: !_isFoodMode ? const Color(0xFF030213) : const Color(0xFFECECF0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text('오늘 뭐 하지', style: TextStyle(color: !_isFoodMode ? Colors.white : const Color(0xFF717182), fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Color(0xFF0A0A0A), fontSize: 16, fontWeight: FontWeight.w400));
  }

  Widget _buildChoiceChip(String label, Set<String> selectionSet, VoidCallback onSelected) {
    final bool isSelected = selectionSet.contains(label);
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[200] : const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.black : Colors.transparent, width: 1),
        ),
        child: Center(child: Text(label, style: const TextStyle(color: Color(0xFF0A0A0A), fontSize: 14, fontWeight: FontWeight.w500))),
      ),
    );
  }

  Widget _buildChipGrid(List<String> items, Set<String> selectionSet) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildChoiceChip(items[0], selectionSet, () { setState(() { selectionSet.contains(items[0]) ? selectionSet.remove(items[0]) : selectionSet.add(items[0]); }); })),
            const SizedBox(width: 12),
            Expanded(child: _buildChoiceChip(items[1], selectionSet, () { setState(() { selectionSet.contains(items[1]) ? selectionSet.remove(items[1]) : selectionSet.add(items[1]); }); })),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildChoiceChip(items[2], selectionSet, () { setState(() { selectionSet.contains(items[2]) ? selectionSet.remove(items[2]) : selectionSet.add(items[2]); }); })),
            const SizedBox(width: 12),
            Expanded(child: _buildChoiceChip(items[3], selectionSet, () { setState(() { selectionSet.contains(items[3]) ? selectionSet.remove(items[3]) : selectionSet.add(items[3]); }); })),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('오늘은 오토카지', style: TextStyle(color: Color(0xFF0A0A0A), fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        // [신규] 우측 상단 아이콘들
        actions: [
          // 1. 알림 아이콘 (종)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.black),
                onPressed: () {
                  if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("로그인이 필요한 기능입니다.")),
                    );
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const TagNotificationScreen()));
                },
              ),
              // 알림 개수 배지 (빨간 점)
              Positioned(
                right: 12, top: 12,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseAuth.instance.currentUser == null 
                      ? null 
                      : FirebaseFirestore.instance
                          .collection('tag_requests')
                          .where('toUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();
                    return Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle));
                  },
                ),
              )
            ],
          ),
          // 2. 친구 관리 아이콘 (사람)
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
            onPressed: () {
              if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("로그인이 필요한 기능입니다.")),
                );
                return;
              }
              Navigator.push(context, MaterialPageRoute(builder: (context) => const FriendScreen()));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildModeToggle(),
            const SizedBox(height: 32),

            if (_isFoodMode) ...[
              _buildSectionTitle('음식 종류를 선택하세요'),
              const SizedBox(height: 16),
              _buildChipGrid(['한식', '중식', '일식', '양식'], _selectedFoodTypes),
              const SizedBox(height: 32),
              _buildSectionTitle('메뉴 타입을 선택하세요'),
              const SizedBox(height: 16),
              _buildChipGrid(['밥', '빵', '면', '고기'], _selectedMenuTypes),
              const SizedBox(height: 32),
            ],

            if (!_isFoodMode) ...[
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 50),
                child: Text("'오늘 뭐 하지' UI가 여기에 표시됩니다.", style: TextStyle(color: Colors.grey[600])),
              ),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Opacity(
          opacity: 1.0, 
          child: ElevatedButton(
            onPressed: () {
              if (_isLoading) return;

              if (_isFoodMode) {
                _recommendRealRestaurant();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("준비 중인 기능입니다!")));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF030213),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isLoading 
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('오늘 오토카지?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}