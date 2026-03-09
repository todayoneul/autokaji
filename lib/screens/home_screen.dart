import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autokaji/screens/friend_screen.dart';
import 'package:autokaji/screens/tag_notification_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/providers/location_provider.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';
import 'package:autokaji/services/place_search_service.dart';
import 'package:autokaji/providers/wishlist_provider.dart';
import 'package:autokaji/screens/wishlist_screen.dart';
import 'package:autokaji/screens/course_planner_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Function(String name, double lat, double lng) onPlaceSelected;

  const HomeScreen({super.key, required this.onPlaceSelected});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String get kGoogleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isFoodMode = true;
  bool _isLoading = false;

  double _searchRadius = 500; 
  double _minRating = 0.0;    

  final Set<String> _selectedMainCats = {};
  final Set<String> _selectedSubCats = {};

  List<dynamic> _searchResults = [];

  final Map<String, String> _googlePhotoCache = {};

  final Map<String, List<String>> _foodCategories = {
    '한식': ['밥', '국물', '고기', '면', '분식', '찌개', '백반', '족발', '곱창'],
    '중식': ['면', '밥', '요리', '딤섬', '짜장', '마라', '양꼬치'],
    '일식': ['초밥', '돈까스', '라멘', '덮밥', '회', '우동', '소바', '카츠', '이자카야'],
    '양식': ['파스타', '피자', '스테이크', '버거', '브런치'],
    '아시안': ['쌀국수', '카레', '팟타이', '타코'],
    '디저트': ['카페', '빵', '케이크', '아이스크림', '빙수', '마카롱', '도넛'],
  };

  final Map<String, List<String>> _playCategories = {
    '카페': ['커피', '디저트', '베이커리', '전통차'],
    '실내': ['영화관', '노래방', 'PC방', '보드게임', '방탈출', '전시회'],
    '실외': ['공원', '산책로', '쇼핑', '테마파크'],
  };

  static const Map<String, String> _categoryEmojis = {
    '한식': '🍚', '중식': '🥟', '일식': '🍣', '양식': '🍕',
    '아시안': '🍜', '디저트': '🍰',
    '카페': '☕', '실내': '🎮', '실외': '🌳',
    '밥': '🍚', '국물': '🍲', '고기': '🥩', '면': '🍜', '분식': '🍞',
    '찌개': '🍲', '백반': '🍱', '족발': '🍖', '곱창': '🦠',
    '요리': '🥘', '딤섬': '🥟', '짜장': '🍝', '마라': '🌶️', '양꼬치': '🍖',
    '초밥': '🍣', '돈까스': '🍛', '라멘': '🍜', '덮밥': '🍛',
    '회': '🐟', '우동': '🍜', '소바': '🍜', '카츠': '🍛', '이자카야': '🍶',
    '파스타': '🍝', '피자': '🍕', '스테이크': '🥩', '버거': '🍔', '브런치': '🥐',
    '쌀국수': '🍜', '카레': '🍛', '팟타이': '🍝', '타코': '🌮',
    '빵': '🍞', '케이크': '🍰', '아이스크림': '🍦', '빙수': '🍧', '마카롱': '🍭', '도넛': '🍩',
    '커피': '☕', '베이커리': '🥐', '전통차': '🍵',
    '영화관': '🎬', '노래방': '🎤', 'PC방': '💻', '보드게임': '🎲',
    '방탈출': '🔐', '전시회': '🖼️',
    '공원': '🌳', '산책로': '🚶', '쇼핑': '🛍️', '테마파크': '🎢',
  };

  @override
  void initState() {
    super.initState();
    _checkTagRequests();
    _loadFilterSettings();
  }

  Future<void> _loadFilterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _searchRadius = prefs.getDouble('searchRadius') ?? 500; 
        _minRating = prefs.getDouble('minRating') ?? 0.0;       
      });
    }
  }

  Future<void> _saveFilterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('searchRadius', _searchRadius);
    await prefs.setDouble('minRating', _minRating);
  }

  Stream<int> _getUnreadNotificationCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user.uid)
        .snapshots()
        .map((n) => n.docs.length);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
            title: const Text("새로운 알림 🔔", style: TextStyle(fontWeight: FontWeight.w800)),
            content: Text("${snapshot.docs.length}건의 태그 요청이 도착했습니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기", style: TextStyle(color: AppColors.textSecondary))),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TagNotificationScreen()));
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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

  Future<String?> _fetchGooglePlacePhoto(String storeName, double lat, double lng) async {
    if (_googlePhotoCache.containsKey(storeName)) return _googlePhotoCache[storeName];
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$storeName&inputtype=textquery&fields=photos&locationbias=circle:1000@$lat,$lng&key=$kGoogleApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['candidates'].isNotEmpty) {
          final photos = data['candidates'][0]['photos'];
          if (photos != null && photos.isNotEmpty) {
            final String photoRef = photos[0]['photo_reference'];
            final String photoUrl = 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoRef&key=$kGoogleApiKey';
            _googlePhotoCache[storeName] = photoUrl;
            return photoUrl;
          }
        }
      }
    } catch (e) {
      debugPrint("구글 포토 검색 실패($storeName): $e");
    }
    return null;
  }

  Future<void> _launchNaverMapSearch(String query) async {
    final Uri appUrl = Uri.parse('nmap://search?query=$query&appname=com.gyuhan.autokaji');
    final Uri webUrl = Uri.parse('https://m.map.naver.com/search2/search.naver?query=$query');
    if (await canLaunchUrl(appUrl)) await launchUrl(appUrl);
    else await launchUrl(webUrl);
  }

  Map<String, String> _getGoogleSearchParams() {
    String type = 'restaurant'; 
    String keyword = '';        
    if (_selectedMainCats.contains('카페') || _selectedMainCats.contains('디저트')) {
      type = 'cafe';
    } else if (!_isFoodMode) {
      type = 'point_of_interest'; 
    }
    List<String> keywords = [];
    for (var cat in _selectedMainCats) {
      if (cat != '카페' && cat != '디저트') keywords.add(cat); 
    }
    if (_selectedSubCats.isNotEmpty) keywords.addAll(_selectedSubCats);
    if (keywords.isNotEmpty) keyword = keywords.join(" ");
    return {'type': type, 'keyword': keyword};
  }

  Future<void> _navigateToCoursePlanner() async {
    HapticFeedback.lightImpact();
    debugPrint("AI 코스 플래너 진입 시도");
    try {
      Position position = await ref.read(locationProvider.future);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => CoursePlannerScreen(lat: position.latitude, lng: position.longitude, locationName: '현재 위치')));
      }
    } catch (e) {
      debugPrint("위치 획득 실패: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('위치를 확인할 수 없습니다: $e')));
    }
  }

  Future<void> _searchAndRecommend() async {
    debugPrint("추천 검색 시작: radius=$_searchRadius, minRating=$_minRating");
    setState(() => _isLoading = true);
    try {
      Position position = await ref.read(locationProvider.future);
      final params = _getGoogleSearchParams();
      debugPrint("검색 파라미터: $params");

      final hybridResults = await PlaceSearchService.hybridSearch(
        lat: position.latitude, lng: position.longitude, radius: _searchRadius.toInt(),
        googleType: params['type']!, keyword: params['keyword']!, minRating: _minRating,
      );
      
      _searchResults = hybridResults.map((p) => p.toGoogleFormat()).toList();
      debugPrint("검색 결과 수: ${_searchResults.length}");

      if (_searchResults.isEmpty) {
        _showNaverFallbackDialog(params['keyword']!.isEmpty ? "맛집" : params['keyword']!);
      } else {
        _showSelectionDialog(_searchResults);
      }
    } catch (e) {
      debugPrint("추천 검색 오류: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showHotPlacePreview(Map<String, dynamic> place) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: FutureBuilder<String?>(
                future: _fetchGooglePlacePhoto(place['name'], (place['lat'] as num).toDouble(), (place['lng'] as num).toDouble()),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(height: 200, color: AppColors.surfaceVariant, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)));
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Stack(
                      children: [
                        Image.network(snapshot.data!, height: 200, width: double.infinity, fit: BoxFit.cover),
                        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.3)])))),
                      ],
                    );
                  }
                  return Container(height: 200, color: AppColors.surfaceVariant, child: const Icon(Icons.store_rounded, size: 50, color: AppColors.textTertiary));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(place['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: AppGradientButton(text: "지도에서 위치 보기", icon: Icons.map_rounded, onPressed: () { Navigator.pop(context); widget.onPlaceSelected(place['name'], (place['lat'] as num).toDouble(), (place['lng'] as num).toDouble()); })),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog(List<dynamic> filteredCandidates) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BottomSheetHandle(),
              const SizedBox(height: 16),
              Text("🎉 ${_searchResults.length}곳 이상의 장소를 찾았어요!", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () { Navigator.pop(context); _showResultList(); }, icon: const Icon(Icons.list_rounded), label: const Text("리스트 보기"), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: AppColors.textPrimary, side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg))))),
                  const SizedBox(width: 12),
                  Expanded(child: AppGradientButton(text: "랜덤 뽑기", icon: Icons.casino_rounded, onPressed: () { Navigator.pop(context); final selected = filteredCandidates[Random().nextInt(filteredCandidates.length)]; _showSingleResultDialog(selected); })),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _showResultList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const BottomSheetHandle(),
                Padding(padding: const EdgeInsets.all(16.0), child: Text("추천 리스트 (${_searchResults.length}곳)", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final place = _searchResults[index];
                      return AppCard(onTap: () => _showSingleResultDialog(place, showReroll: false), padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(place['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 4), Text(place['vicinity'] ?? '', style: const TextStyle(color: AppColors.textTertiary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)]))]));
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

  Future<void> _showSingleResultDialog(Map<String, dynamic> place, {bool showReroll = true}) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(place['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(place['vicinity'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: AppGradientButton(text: "여기 갈래요!", icon: Icons.place_rounded, onPressed: () { Navigator.pop(context); widget.onPlaceSelected(place['name'], (place['geometry']['location']['lat'] as num).toDouble(), (place['geometry']['location']['lng'] as num).toDouble()); })),
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
        content: const Text("조건에 맞는 곳이 없어요. 네이버 지도로 찾아볼까요?"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), ElevatedButton(onPressed: () { Navigator.pop(ctx); _launchNaverMapSearch(query); }, child: const Text("네이버로 찾기"))],
      ),
    );
  }

  void _showFilterSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BottomSheetHandle(),
                  const Text("검색 설정", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Slider(value: _searchRadius, min: 100, max: 3000, divisions: 29, label: "${_searchRadius.toInt()}m", onChanged: (val) => setModalState(() => _searchRadius = val), onChangeEnd: (val) { setState(() => _searchRadius = val); _saveFilterSettings(); }),
                  const Text("최소 평점"),
                  Slider(value: _minRating, min: 0.0, max: 5.0, divisions: 10, label: "$_minRating", onChanged: (val) => setModalState(() => _minRating = val), onChangeEnd: (val) { setState(() => _minRating = val); _saveFilterSettings(); }),
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
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(AppTheme.radiusXl)),
      child: Row(children: [_toggleButton("🍽️  뭐 먹지", _isFoodMode, () => setState(() { _isFoodMode = true; _selectedMainCats.clear(); _selectedSubCats.clear(); })), _toggleButton("🎮  뭐 하지", !_isFoodMode, () => setState(() { _isFoodMode = false; _selectedMainCats.clear(); _selectedSubCats.clear(); }))]),
    );
  }

  Widget _toggleButton(String text, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(gradient: isSelected ? AppColors.primaryGradient : null, borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
          child: Center(child: Text(text, style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w700))),
        ),
      ),
    );
  }

  Widget _buildChoiceChip(String label, Set<String> selectionSet, VoidCallback onSelected) {
    final bool isSelected = selectionSet.contains(label);
    final String emoji = _categoryEmojis[label] ?? '✨';
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(gradient: isSelected ? AppColors.primaryGradient : null, color: isSelected ? null : AppColors.surface, borderRadius: BorderRadius.circular(AppTheme.radiusLg), border: Border.all(color: isSelected ? Colors.transparent : AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji), const SizedBox(width: 8), Text(label, style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w700))]),
      ),
    );
  }

  Widget _buildChipGrid(List<String> items, Set<String> selectionSet) {
    return Wrap(spacing: 10, runSpacing: 12, children: items.map((item) => _buildChoiceChip(item, selectionSet, () => setState(() => selectionSet.contains(item) ? selectionSet.remove(item) : selectionSet.add(item)))).toList());
  }

  Widget _buildHotPlaces() {
    final locationAsync = ref.watch(locationProvider);
    if (locationAsync.isLoading) return Column(children: List.generate(3, (i) => const HotPlaceShimmer()));
    if (!locationAsync.hasValue) return const SizedBox();

    final pos = locationAsync.value!;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PlaceSearchService.hybridHotPlaces(
        lat: pos.latitude, lng: pos.longitude, radius: _searchRadius.toInt(),
        isFoodMode: _isFoodMode, 
        selectedCats: _selectedMainCats,
        selectedSubCats: _selectedSubCats,
        minRating: _minRating,
      ).then((list) {
        var mapped = list.map((p) => {'name': p.name, 'lat': p.lat, 'lng': p.lng, 'rating': p.rating, 'category': p.category, 'source': p.source, 'place_result': p}).toList();
        mapped.sort((a, b) {
          try {
            final distA = Geolocator.distanceBetween(pos.latitude, pos.longitude, (a['lat'] as num).toDouble(), (a['lng'] as num).toDouble());
            final distB = Geolocator.distanceBetween(pos.latitude, pos.longitude, (b['lat'] as num).toDouble(), (b['lng'] as num).toDouble());
            return distA.compareTo(distB);
          } catch (e) {
            return 0; // 좌표 오류 시 순서 변경 없음
          }
        });
        return mapped;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Column(children: List.generate(3, (i) => const HotPlaceShimmer()));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("주변에 핫플이 없어요 🥲"));
        return Column(children: snapshot.data!.map((data) => _buildHotPlaceCard(data, pos)).toList());
      },
    );
  }

  Widget _buildHotPlaceCard(Map<String, dynamic> data, Position userPos) {
    String distStr = "거리 정보 없음";
    try {
      final double distance = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, (data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
      distStr = distance >= 1000 ? "${(distance/1000).toStringAsFixed(1)}km" : "${distance.toInt()}m";
    } catch (e) {
      // 거리 계산 실패 시 기본값 유지
    }
    final bool isNaver = data['source'] == 'naver';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      onTap: () => _showHotPlacePreview(data),
      child: Row(
        children: [
          FutureBuilder<String?>(
            future: _fetchGooglePlacePhoto(data['name'], (data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()),
            builder: (context, snapshot) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                child: snapshot.hasData ? Image.network(snapshot.data!, width: 80, height: 80, fit: BoxFit.cover) : Container(width: 80, height: 80, color: AppColors.surfaceVariant, child: const Icon(Icons.store)),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Row(children: [
                _buildSourceBadge(data['source']),
                const SizedBox(width: 6),
                Text(distStr, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                if (!isNaver) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  Text(" ${data['rating']}"),
                ],
              ]),
              const SizedBox(height: 2),
              Flexible(child: Text(data['category'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          _buildHeartButton(data['place_result']),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(String? source) {
    Color color; String label;
    if (source == 'naver') { color = Colors.green; label = 'N'; }
    else if (source == 'kakao') { color = Colors.amber; label = 'K'; }
    else { color = Colors.blue; label = 'G'; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(4)), child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));
  }

  Widget _buildHeartButton(PlaceResult place) {
    final isWishlisted = ref.watch(isWishlistedProvider(place.uniqueId));
    return IconButton(
      icon: Icon(isWishlisted ? Icons.favorite : Icons.favorite_border, color: isWishlisted ? Colors.red : AppColors.textTertiary),
      onPressed: () {
        if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인이 필요합니다.")));
          return;
        }
        if (isWishlisted) ref.read(wishlistToggleProvider)(place, true);
        else showDialog(context: context, builder: (context) => WishlistFolderDialog(place: place));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentCats = _isFoodMode ? _foodCategories : _playCategories;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('오토카지'),
        actions: [
          StreamBuilder<int>(
            stream: _getUnreadNotificationCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(children: [
                _buildAppBarAction(Icons.notifications, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagNotificationScreen()))),
                if (count > 0) Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), constraints: const BoxConstraints(minWidth: 14, minHeight: 14), child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 8), textAlign: TextAlign.center))),
              ]);
            },
          ),
          _buildAppBarAction(Icons.favorite, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen()))),
          _buildAppBarAction(Icons.people, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendScreen()))),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildModeToggle(),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _navigateToCoursePlanner,
                child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)]), borderRadius: BorderRadius.circular(AppTheme.radiusXl)), child: const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFF9C27B0)), SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("어디갈지 고민되시나요?", style: TextStyle(fontSize: 12, color: Color(0xFF7B1FA2))), Text("✨ AI 데이트/약속 코스 짜기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]))])),
              ),
              const SizedBox(height: 32),
              const Text("어떤 종류가 땡기세요?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 20),
              _buildChipGrid(currentCats.keys.toList(), _selectedMainCats),
              if (_selectedMainCats.isNotEmpty) ...[
                const SizedBox(height: 32),
                const Text("세부 메뉴는요?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                Builder(builder: (context) {
                  final List<String> subItems = [];
                  for (var key in _selectedMainCats) { if (currentCats.containsKey(key)) subItems.addAll(currentCats[key]!); }
                  return _buildChipGrid(subItems, _selectedSubCats);
                }),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("🔥 내 주변 핫플레이스", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    GestureDetector(
                      onTap: _showFilterSettings,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(AppTheme.radiusFull), border: Border.all(color: AppColors.borderLight)),
                        child: Row(children: [const Icon(Icons.tune_rounded, size: 14, color: AppColors.textSecondary), const SizedBox(width: 4), Text("${_searchRadius.toInt()}m · ${_minRating}점↑", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildHotPlaces(),
              ],
            ),
          ),
          const SizedBox(height: 120),
        ]),
      ),
      bottomSheet: Container(color: AppColors.background, padding: const EdgeInsets.all(24), child: AppGradientButton(text: '오토카지 추천받기', icon: Icons.auto_awesome, isLoading: _isLoading, onPressed: _isLoading ? null : _searchAndRecommend, height: 60)),
    );
  }

  Widget _buildAppBarAction(IconData icon, VoidCallback onTap) {
    return IconButton(icon: Icon(icon), onPressed: onTap);
  }
}
