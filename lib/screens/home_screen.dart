import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autokaji/screens/friend_screen.dart';
import 'package:autokaji/screens/tag_notification_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(String name, double lat, double lng) onPlaceSelected;

  const HomeScreen({super.key, required this.onPlaceSelected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String get kGoogleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isFoodMode = true; // True: 먹지, False: 하지
  bool _isLoading = false;
  Position? _currentPosition;

  // 필터 설정값 (기본값: 반경 500m, 평점 0.0 이상)
  double _searchRadius = 500; 
  double _minRating = 0.0;    

  final Set<String> _selectedMainCats = {};
  final Set<String> _selectedSubCats = {};

  // 카테고리 데이터 정의
  final Map<String, List<String>> _foodCategories = {
    '한식': ['밥', '국물', '고기', '면', '분식'],
    '중식': ['면', '밥', '요리', '딤섬'],
    '일식': ['초밥', '돈까스', '라멘', '덮밥', '회'],
    '양식': ['파스타', '피자', '스테이크', '버거'],
    '아시안': ['쌀국수', '카레', '팟타이', '타코'],
    '카페': ['커피', '디저트', '베이커리', '전통차'],
    '바': ['칵테일', '와인', '맥주', '이자카야'],
  };

  final Map<String, List<String>> _playCategories = {
    '실내': ['영화관', '노래방', 'PC방', '보드게임', '방탈출', '전시회'],
    '실외': ['공원', '산책로', '쇼핑', '테마파크'],
  };

  @override
  void initState() {
    super.initState();
    _initCurrentLocation();
    _checkTagRequests();
  }

  Future<void> _checkTagRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tag_requests')
          .where('toUid', isEqualTo: user.uid)
          .get();
      if (snapshot.docs.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("새로운 알림 🔔"),
            content: Text("${snapshot.docs.length}건의 태그 요청이 도착했습니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기")),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TagNotificationScreen()));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text("확인"),
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
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint("초기 위치 탐색 실패: $e");
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('위치 서비스 꺼짐');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw Exception('권한 거부');
    }
    if (permission == LocationPermission.deniedForever) throw Exception('영구 거부');
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("지도 실행 오류: $e")));
    }
  }

  // [신규] 앱의 카테고리를 구글 Places API (Nearby Search) 파라미터로 변환
  Map<String, String> _getGoogleSearchParams() {
    String type = 'restaurant'; // 기본값: 음식점
    String keyword = '';        // 보조 키워드

    // 1. 메인 카테고리 분석 (type 설정)
    if (_selectedMainCats.contains('카페')) {
      type = 'cafe';
    } else if (_selectedMainCats.contains('바')) {
      type = 'bar';
    } else if (!_isFoodMode) {
      // 놀거리 모드
      type = 'point_of_interest'; 
    }

    // 2. 키워드 조합 (한식, 중식, 면, 고기 등)
    List<String> keywords = [];
    
    // '카페', '바'가 아닌 나머지 메인 카테고리(한식, 중식 등)는 키워드로 추가
    for (var cat in _selectedMainCats) {
      if (cat != '카페' && cat != '바') {
        keywords.add(cat); 
      }
    }
    
    // 서브 카테고리 추가
    if (_selectedSubCats.isNotEmpty) {
      keywords.addAll(_selectedSubCats);
    }

    if (keywords.isNotEmpty) {
      keyword = keywords.join(" ");
    }

    return {'type': type, 'keyword': keyword};
  }

  // [핵심 수정] Nearby Search API를 이용한 정밀 추천 로직
  Future<void> _searchAndRecommend() async {
    setState(() => _isLoading = true);

    try {
      Position position = _currentPosition ?? await _determinePosition();
      _currentPosition = position;

      // 1. 파라미터 준비
      final params = _getGoogleSearchParams();
      final String type = params['type']!;
      final String keyword = params['keyword']!;

      // 2. Nearby Search API URL 생성
      String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${position.latitude},${position.longitude}&radius=$_searchRadius&type=$type&language=ko&key=$kGoogleApiKey';

      if (keyword.isNotEmpty) {
        url += '&keyword=$keyword'; // 키워드가 있을 때만 추가
      }

      // 3. API 호출
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final List<dynamic> results = data['results'];

          // 4. 클라이언트 필터링 (평점)
          // (Nearby Search는 반경 내 결과만 주므로 거리 계산은 생략해도 되지만, 정확성을 위해 유지해도 됨)
          final List<dynamic> candidates = results.where((place) {
            final double rating = (place['rating'] ?? 0).toDouble();
            return rating >= _minRating;
          }).toList();

          if (candidates.isEmpty) {
            String msg = "조건(평점 $_minRating↑)에 맞는 곳이 없어요 😭";
            if (data['status'] == 'ZERO_RESULTS') msg = "반경 내에 해당 카테고리 장소가 없어요.";
            
            // 네이버 지도 검색어 (키워드가 없으면 타입으로 검색)
            String fallbackQuery = keyword.isEmpty ? (type == 'restaurant' ? "맛집" : type) : keyword;
            _showNaverFallbackDialog(fallbackQuery);
          } else {
            _showSelectionDialog(candidates);
          }
        } else {
          throw Exception("API Error: ${data['status']} - ${data['error_message']}");
        }
      } else {
        throw Exception("서버 통신 오류 (${response.statusCode})");
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSelectionDialog(List<dynamic> candidates) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "🎉 ${candidates.length}곳의 장소를 찾았어요!",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "반경 ${_searchRadius.toInt()}m 이내, 별점 $_minRating점 이상",
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showResultList(candidates);
                      },
                      icon: const Icon(Icons.list),
                      label: const Text("리스트 보기"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        final random = Random();
                        final selected = candidates[random.nextInt(candidates.length)];
                        _showSingleResultDialog(selected);
                      },
                      icon: const Icon(Icons.casino),
                      label: const Text("랜덤 뽑기"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _showResultList(List<dynamic> candidates) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("추천 리스트", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = candidates[index];
                      final double rating = (place['rating'] ?? 0).toDouble();
                      return ListTile(
                        title: Text(place['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(place['vicinity'] ?? ''), // Nearby Search는 formatted_address 대신 vicinity 사용
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 16, color: Colors.amber),
                            Text(" $rating"),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showSingleResultDialog(place);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSingleResultDialog(Map<String, dynamic> place) {
    final String name = place['name'];
    final String address = place['vicinity'] ?? "주소 정보 없음"; // Nearby Search는 vicinity
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
                  height: 180, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(height: 150, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      Text(" $rating ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("($userRatingsTotal)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(address, style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(context); widget.onPlaceSelected(name, lat, lng); },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text("여기 갈래요!", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNaverFallbackDialog(String query) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("결과 없음"),
        content: Text("조건($_searchRadius m, $_minRating점↑)에 맞는 곳이 없어요.\n네이버 지도로 찾아볼까요?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _launchNaverMapSearch(query); },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF03C75A), foregroundColor: Colors.white),
            child: const Text("네이버 지도로 찾기"),
          )
        ],
      ),
    );
  }

  void _showFilterSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("검색 필터 설정", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Text("검색 반경: ${_searchRadius.toInt()}m"),
                  Slider(
                    value: _searchRadius,
                    min: 100, max: 3000, divisions: 29,
                    label: "${_searchRadius.toInt()}m",
                    activeColor: Colors.black,
                    onChanged: (val) => setModalState(() => _searchRadius = val),
                    onChangeEnd: (val) => setState(() => _searchRadius = val),
                  ),
                  const SizedBox(height: 10),
                  Text("최소 평점: $_minRating점 이상"),
                  Slider(
                    value: _minRating,
                    min: 0.0, max: 5.0, divisions: 10,
                    label: "$_minRating",
                    activeColor: Colors.amber,
                    onChanged: (val) => setModalState(() => _minRating = val),
                    onChangeEnd: (val) => setState(() => _minRating = val),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _toggleButton("오늘 뭐 먹지", _isFoodMode, () => setState(() { _isFoodMode = true; _selectedMainCats.clear(); _selectedSubCats.clear(); })),
          _toggleButton("오늘 뭐 하지", !_isFoodMode, () => setState(() { _isFoodMode = false; _selectedMainCats.clear(); _selectedSubCats.clear(); })),
        ],
      ),
    );
  }

  Widget _toggleButton(String text, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : [],
          ),
          child: Center(
            child: Text(text, style: TextStyle(color: isSelected ? Colors.black : Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip(String label, Set<String> selectionSet, VoidCallback onSelected) {
    final bool isSelected = selectionSet.contains(label);
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? Colors.black : Colors.grey[300]!),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildChipGrid(List<String> items, Set<String> selectionSet) {
    return Wrap(
      spacing: 8, runSpacing: 12,
      children: items.map((item) => _buildChoiceChip(item, selectionSet, () {
        setState(() {
          if (selectionSet.contains(item)) {
            selectionSet.remove(item);
          } else {
            selectionSet.add(item);
          }
        });
      })).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentCats = _isFoodMode ? _foodCategories : _playCategories;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('오늘은 오토카지', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.black),
            onPressed: _showFilterSettings,
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
            onPressed: () {
              if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인이 필요한 기능입니다.")));
                return;
              }
              Navigator.push(context, MaterialPageRoute(builder: (context) => const FriendScreen()));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModeToggle(),
            const SizedBox(height: 32),
            
            Text(_isFoodMode ? "어떤 종류가 땡기세요?" : "어디로 갈까요?", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildChipGrid(currentCats.keys.toList(), _selectedMainCats),
            
            if (_selectedMainCats.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(_isFoodMode ? "세부 메뉴는요?" : "활동 종류", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              Builder(builder: (context) {
                final List<String> subItems = [];
                for (var key in _selectedMainCats) {
                  if (currentCats.containsKey(key)) subItems.addAll(currentCats[key]!);
                }
                return _buildChipGrid(subItems, _selectedSubCats);
              }),
            ],

            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _searchAndRecommend,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading 
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('오토카지 추천받기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}