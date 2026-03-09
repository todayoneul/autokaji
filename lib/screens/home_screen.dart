import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart'; // iOS 스타일 로딩 인디케이터용
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [신규] 햅틱 피드백용
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
  bool _isFetchingMore = false;

  double _searchRadius = 500; 
  double _minRating = 0.0;    

  final Set<String> _selectedMainCats = {};
  final Set<String> _selectedSubCats = {};

  List<dynamic> _searchResults = [];
  String? _nextPageToken;

  // [신규] 구글 포토 URL 캐싱 (API 호출 절약)
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

  Stream<QuerySnapshot> _getHotPlacesStream() {
    return FirebaseFirestore.instance.collection('hot_places').snapshots();
  }

  Stream<int> _getUnreadNotificationCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return Stream.value(0);

    final notifications = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user.uid)
        .snapshots();

    final tagRequests = FirebaseFirestore.instance
        .collection('tag_requests')
        .where('toUid', isEqualTo: user.uid)
        .snapshots();

    // 두 스트림을 결합하여 총 개수 반환
    return Stream.castFrom(notifications).map((n) {
      final int nCount = n.docs.length;
      return nCount; // 우선 notifications 개수만 반환하거나 Rx.combineLatest 등을 써야 함
      // 간단하게 notifications 개수만 먼저 구현
    });
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

  String? _getPhotoUrl(List<dynamic>? photos) {
    if (photos == null || photos.isEmpty) return null;
    final String photoReference = photos[0]['photo_reference'];
    return 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$kGoogleApiKey';
  }

  // [신규] 가게 이름과 좌표로 구글 포토 URL 가져오기
  Future<String?> _fetchGooglePlacePhoto(String storeName, double lat, double lng) async {
    // 1. 캐시 확인 (이미 찾은 적 있으면 그거 씀)
    if (_googlePhotoCache.containsKey(storeName)) {
      return _googlePhotoCache[storeName];
    }

    try {
      // 2. 구글 장소 검색 (Find Place API 사용 - 비용 효율적)
      final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$storeName&inputtype=textquery&fields=photos&locationbias=circle:1000@$lat,$lng&key=$kGoogleApiKey';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['candidates'].isNotEmpty) {
          final photos = data['candidates'][0]['photos'];
          if (photos != null && photos.isNotEmpty) {
            final String photoRef = photos[0]['photo_reference'];
            final String photoUrl = 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoRef&key=$kGoogleApiKey';
            
            // 캐시에 저장
            _googlePhotoCache[storeName] = photoUrl;
            return photoUrl;
          }
        }
      }
    } catch (e) {
      debugPrint("구글 포토 검색 실패: $e");
    }
    return null; // 실패하면 null 반환 (기본 이미지 뜸)
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

  Future<void> _launchInstagramSearch(String keyword) async {
    final cleanKeyword = keyword.replaceAll(' ', '');
    final Uri url = Uri.parse('https://www.instagram.com/explore/tags/$cleanKeyword/');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("인스타그램을 열 수 없습니다.")));
    }
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

  Future<void> _searchAndRecommend() async {
    setState(() {
      _isLoading = true;
      _searchResults = [];
      _nextPageToken = null;
    });

    try {
      Position position = await ref.read(locationProvider.future);

      final params = _getGoogleSearchParams();
      final String type = params['type']!;
      final String keyword = params['keyword']!;

      // 하이브리드 검색 (네이버 + 카카오 + 구글 병렬)
      final hybridResults = await PlaceSearchService.hybridSearch(
        lat: position.latitude,
        lng: position.longitude,
        radius: _searchRadius.toInt(),
        googleType: type,
        keyword: keyword,
        minRating: _minRating,
      );

      // PlaceResult → 기존 다이얼로그 호환 Map 형식으로 변환
      _searchResults = hybridResults.map((p) => p.toGoogleFormat()).toList();

      if (_searchResults.isEmpty) {
        String fallbackQuery = keyword.isEmpty ? (type == 'restaurant' ? "맛집" : type) : keyword;
        _showNaverFallbackDialog(fallbackQuery);
      } else {
        _showSelectionDialog(_searchResults);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchNextPage() async {
    if (_nextPageToken == null || _isFetchingMore) return;

    setState(() => _isFetchingMore = true);
    await Future.delayed(const Duration(seconds: 2));

    try {
      final String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?pagetoken=$_nextPageToken&key=$kGoogleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'] ?? [];

          final List<dynamic> filteredResults = results.where((place) {
            final double rating = (place['rating'] ?? 0).toDouble();
            final int reviews = place['user_ratings_total'] ?? 0;
            return rating >= _minRating && reviews >= 10;
          }).toList();

          filteredResults.sort((a, b) {
             final double scoreA = (a['rating'] ?? 0).toDouble() * (a['user_ratings_total'] ?? 0);
             final double scoreB = (b['rating'] ?? 0).toDouble() * (b['user_ratings_total'] ?? 0);
             return scoreB.compareTo(scoreA); 
          });

          setState(() {
            _searchResults.addAll(filteredResults);
            _nextPageToken = data['next_page_token'];
          });        } else if (data['status'] == 'INVALID_REQUEST') {
          await Future.delayed(const Duration(seconds: 1));
          _isFetchingMore = false; 
          await _fetchNextPage(); 
          return;
        }
      }
    } catch (e) {
      debugPrint("추가 로딩 오류: $e");
    } finally {
      if (mounted) setState(() => _isFetchingMore = false);
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
                future: _fetchGooglePlacePhoto(place['name'], place['lat'], place['lng']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(height: 200, color: AppColors.surfaceVariant, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)));
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Stack(
                      children: [
                        Image.network(snapshot.data!, height: 200, width: double.infinity, fit: BoxFit.cover),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Container(height: 200, color: AppColors.surfaceVariant, child: Icon(Icons.store_rounded, size: 50, color: AppColors.textTertiary));
                },
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(place['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  
                  if (place['menu'] != null && place['menu'] != "메뉴 정보 없음")
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                      child: Text(place['menu'], style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),

                  const SizedBox(height: 12),
                  
                  SizedBox(
                    width: double.infinity,
                    child: AppGradientButton(
                      text: "지도에서 위치 보기",
                      icon: Icons.map_rounded,
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onPlaceSelected(place['name'], place['lat'], place['lng']);
                      },
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
              Text(
                "🎉 ${_searchResults.length}곳 이상의 장소를 찾았어요!",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  "반경 ${_searchRadius.toInt()}m · 별점 $_minRating↑",
                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showResultList();
                      },
                      icon: const Icon(Icons.list_rounded),
                      label: const Text("리스트 보기"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        boxShadow: AppTheme.shadowPrimary,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (filteredCandidates.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("별점 조건에 맞는 곳이 없어서 랜덤을 돌릴 수 없어요!")));
                            return;
                          }
                          Navigator.pop(context);
                          final random = Random();
                          final selected = filteredCandidates[random.nextInt(filteredCandidates.length)];
                          _showSingleResultDialog(selected); 
                        },
                        icon: const Icon(Icons.casino_rounded),
                        label: const Text("랜덤 뽑기"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
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

  void _showResultList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            
            final ScrollController scrollController = ScrollController();
            scrollController.addListener(() {
              if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
                if (_nextPageToken != null && !_isFetchingMore) {
                  _fetchNextPage().then((_) {
                    setSheetState(() {}); 
                  });
                }
              }
            });

            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, _) {
                return Column(
                  children: [
                    const BottomSheetHandle(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Text("추천 리스트", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                            ),
                            child: Text("${_searchResults.length}곳", style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _searchResults.length + (_nextPageToken != null ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == _searchResults.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                            );
                          }

                          final place = _searchResults[index];
                          final double rating = (place['rating'] ?? 0).toDouble();
                          
                          return AppCard(
                            onTap: () async {
                              final bool? selected = await _showSingleResultDialog(place, showReroll: false);
                              if (selected == true) {
                                Navigator.pop(context); 
                              }
                            },
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(place['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.3)),
                                      const SizedBox(height: 4),
                                      Text(place['vicinity'] ?? '', style: const TextStyle(color: AppColors.textTertiary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSurface,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
                                      const SizedBox(width: 2),
                                      Text("$rating", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.accent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
      },
    );
  }

  Future<bool?> _showSingleResultDialog(Map<String, dynamic> place, {bool showReroll = true}) async {
    final String name = place['name'];
    final String address = place['vicinity'] ?? "주소 정보 없음";
    final double rating = (place['rating'] ?? 0).toDouble();
    final int userRatingsTotal = place['user_ratings_total'] ?? 0;
    final String? photoUrl = _getPhotoUrl(place['photos']);
    
    final geometry = place['geometry']['location'];
    final double lat = geometry['lat'];
    final double lng = geometry['lng'];

    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photoUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Stack(
                  children: [
                    Image.network(
                      photoUrl,
                      height: 180, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Container(height: 150, color: AppColors.surfaceVariant, child: const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary)),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accentSurface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                        const SizedBox(width: 4),
                        Text("$rating", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.accent)),
                        const SizedBox(width: 4),
                        Text("($userRatingsTotal)", style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(address, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 24),
                  
                  // 여기 갈래요 버튼
                  SizedBox(
                    width: double.infinity,
                    child: AppGradientButton(
                      text: "여기 갈래요!",
                      icon: Icons.place_rounded,
                      onPressed: () {
                        Navigator.pop(context, true);
                        widget.onPlaceSelected(name, lat, lng);
                      },
                    ),
                  ),
                  if (showReroll) ...[
                  const SizedBox(height: 10),
                  // 다시 뽑기 버튼
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context, false);
                        if (_searchResults.length > 1) {
                          // 현재 장소 제외하고 다시 랜덤
                          final candidates = _searchResults.where((p) => p['name'] != name).toList();
                          if (candidates.isNotEmpty) {
                            final selected = candidates[Random().nextInt(candidates.length)];
                            _showSingleResultDialog(selected);
                          } else {
                            _showSingleResultDialog(_searchResults[Random().nextInt(_searchResults.length)]);
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('다른 장소가 없어요. 검색 범위를 넓혀보세요!')));
                        }
                      },
                      icon: const Icon(Icons.casino_rounded, size: 20),
                      label: const Text("다시 뽑기"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
                      ),
                    ),
                  ),
                  ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
        title: const Text("결과 없음", style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text("조건($_searchRadius m, $_minRating점↑)에 맞는 곳이 없어요.\n네이버 지도로 찾아볼까요?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _launchNaverMapSearch(query); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.naver, foregroundColor: Colors.white),
            child: const Text("네이버 지도로 찾기"),
          )
        ],
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BottomSheetHandle(),
                  const SizedBox(height: 16),
                  const Text("검색 필터 설정", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("검색 반경", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                        child: Text("${_searchRadius.toInt()}m", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ],
                  ),
                  Slider(
                    value: _searchRadius,
                    min: 100, max: 3000, divisions: 29,
                    label: "${_searchRadius.toInt()}m",
                    onChanged: (val) => setModalState(() => _searchRadius = val),
                    onChangeEnd: (val) {
                      setState(() => _searchRadius = val);
                      _saveFilterSettings(); 
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("최소 평점", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
                            const SizedBox(width: 2),
                            Text("$_minRating", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _minRating,
                    min: 0.0, max: 5.0, divisions: 10,
                    label: "$_minRating",
                    activeColor: AppColors.accent,
                    onChanged: (val) => setModalState(() => _minRating = val),
                    onChangeEnd: (val) {
                      setState(() => _minRating = val);
                      _saveFilterSettings(); 
                    },
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      child: Row(
        children: [
          _toggleButton("🍽️  뭐 먹지", _isFoodMode, () => setState(() { _isFoodMode = true; _selectedMainCats.clear(); _selectedSubCats.clear(); })),
          _toggleButton("🎮  뭐 하지", !_isFoodMode, () => setState(() { _isFoodMode = false; _selectedMainCats.clear(); _selectedSubCats.clear(); })),
        ],
      ),
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
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))] : [],
          ),
          child: Center(
            child: Text(text, style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary, 
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: -0.3,
            )),
          ),
        ),
      ),
    );
  }

  static const Map<String, String> _categoryEmojis = {
    '한식': '🍚', '중식': '🥟', '일식': '🍣', '양식': '🍕',
    '아시안': '🍜', '디저트': '🍰',
    '카페': '☕', '실내': '🎮', '실외': '🌳',
    // sub categories
    '밥': '🍚', '국물': '🍲', '고기': '🥩', '면': '🍜', '분식': '🍞',
    '찌개': '🍲', '백반': '🍱', '족발': '🍖', '곡창': '🦠',
    '요리': '🥘', '딘섬': '🥟', '짜장': '🍝', '마라': '🌶️', '양꼬치': '🍖',
    '초밥': '🍣', '돈까스': '🍛', '라멘': '🍜', '덮밥': '🍛',
    '회': '🐟', '우동': '🍜', '소바': '🍜', '카컠': '🍛', '이자카야': '🍶',
    '파스타': '🍝', '피자': '🍕', '스테이크': '🥩', '버거': '🍔', '브런치': '🥐',
    '쌀국수': '🍜', '카레': '🍛', '팟타이': '🍝', '타코': '🌮',
    '칵테일': '🍸', '와인': '🍷', '맥주': '🍺', '술집': '🍶',
    '호프': '🍻', '요리주점': '🍞',
    '커피': '☕', '베이커리': '🥐', '전통차': '🍵',
    '영화관': '🎬', '노래방': '🎤', 'PC방': '💻', '보드게임': '🎲',
    '방탈출': '🔐', '전시회': '🖼️',
    '공원': '🌳', '산책로': '🚶', '쇼핑': '🛍️', '테마파크': '🎢',
  };

  Widget _buildChoiceChip(String label, Set<String> selectionSet, VoidCallback onSelected) {
    final bool isSelected = selectionSet.contains(label);
    final String emoji = _categoryEmojis[label] ?? '✨';
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppTheme.shadowSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipGrid(List<String> items, Set<String> selectionSet) {
    return Wrap(
      spacing: 10, runSpacing: 12,
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

  // [수정] 핫플레이스 섹션 (구글 API 실시간 검색 기반)
  Widget _buildHotPlaces() {
    final locationAsync = ref.watch(locationProvider);

    if (locationAsync.isLoading) {
      return const SizedBox(height: 230, child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    
    if (locationAsync.hasError || !locationAsync.hasValue) {
      return const SizedBox();
    }

    final pos = locationAsync.value!;

    // 하이브리드 핫플레이스 검색 (네이버 + 카카오 + 구글)
    Future<List<Map<String, dynamic>>> fetchNearbyHotPlaces() async {
      try {
        final hybridResults = await PlaceSearchService.hybridHotPlaces(
          lat: pos.latitude,
          lng: pos.longitude,
          radius: _searchRadius.toInt(),
          isFoodMode: _isFoodMode,
          selectedCats: _selectedMainCats,
        );

        var mappedResults = hybridResults.map((p) => {
          'name': p.name,
          'lat': p.lat,
          'lng': p.lng,
          'rating': p.rating,
          'user_ratings_total': p.reviewCount,
          'category': p.category,
          'place_id': p.placeId ?? '',
          'source': p.source,
          'place_url': p.placeUrl,
          'place_result': p, // 찜하기 전달용
        }).toList();
        
        // 거리순으로 정렬
        mappedResults.sort((a, b) {
          final latA = (a['lat'] as num).toDouble();
          final lngA = (a['lng'] as num).toDouble();
          final latB = (b['lat'] as num).toDouble();
          final lngB = (b['lng'] as num).toDouble();
          
          final distA = Geolocator.distanceBetween(pos.latitude, pos.longitude, latA, lngA);
          final distB = Geolocator.distanceBetween(pos.latitude, pos.longitude, latB, lngB);
          
          return distA.compareTo(distB);
        });
        
        return mappedResults;
      } catch (e) {
        debugPrint('하이브리드 핫플레이스 오류: $e');
        return [];
      }
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchNearbyHotPlaces(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 230, child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: EmptyStateWidget(
              icon: Icons.explore_off_rounded,
              title: "내 주변에 핫플레이스를 찾지 못했어요",
              subtitle: "검색 반경을 늘려보세요!",
            ),
          );
        }

        final places = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 1,
                    color: AppColors.divider,
                  ),
                  const Text("결정이 어렵다면?", style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text("🔥 내 주변 핫플레이스", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                        child: Text("${_searchRadius.toInt()}m", style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 270, 
              child: ListView.separated(
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (ctx, i) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final data = places[index];
                  
                  double distance = Geolocator.distanceBetween(
                    pos.latitude, pos.longitude,
                    data['lat'], data['lng']
                  );

                  String distStr = distance >= 1000 
                    ? "${(distance / 1000).toStringAsFixed(1)}km" 
                    : "${distance.toInt()}m";

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showHotPlacePreview(data);
                    },
                    child: Container(
                      width: 175,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        border: Border.all(color: AppColors.borderLight),
                        boxShadow: AppTheme.shadowMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            child: FutureBuilder<String?>(
                              future: _fetchGooglePlacePhoto(data['name'], data['lat'], data['lng']),
                              builder: (context, photoSnapshot) {
                                if (photoSnapshot.connectionState == ConnectionState.waiting) {
                                  return Container(height: 140, color: AppColors.surfaceVariant, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)));
                                }
                                if (photoSnapshot.hasData && photoSnapshot.data != null) {
                                  return Stack(
                                    children: [
                                      Image.network(photoSnapshot.data!, height: 140, width: double.infinity, fit: BoxFit.cover),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                          ),
                                          child: Text(distStr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: _buildHeartButton(data['place_result']),
                                      ),
                                    ],
                                  );
                                }
                                return Container(height: 140, color: AppColors.surfaceVariant, child: Icon(Icons.storefront_rounded, size: 40, color: AppColors.textTertiary));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // 출처 배지
                                    if (data['source'] != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: data['source'] == 'naver' 
                                              ? const Color(0xFF03C75A).withOpacity(0.15)
                                              : data['source'] == 'kakao'
                                                  ? const Color(0xFFFEE500).withOpacity(0.3)
                                                  : AppColors.primarySurface,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          data['source'] == 'naver' ? 'N' : data['source'] == 'kakao' ? 'K' : 'G',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: data['source'] == 'naver'
                                                ? const Color(0xFF03C75A)
                                                : data['source'] == 'kakao'
                                                    ? const Color(0xFF3C1E1E)
                                                    : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    // 평점 배지
                                    if ((data['rating'] ?? 0) > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentSurface,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
                                            const SizedBox(width: 2),
                                            Text("${data['rating']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                          ],
                                        ),
                                      ),
                                    const Spacer(),
                                    Flexible(child: Text(data['category'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeartButton(PlaceResult place) {
    final isWishlisted = ref.watch(isWishlistedProvider(place.uniqueId));

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인이 필요한 기능입니다.")));
          return;
        }

        if (isWishlisted) {
          // 이미 찜한 경우 바로 삭제
          final toggle = ref.read(wishlistToggleProvider);
          await toggle(place, true);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("찜 목록에서 삭제되었습니다."), duration: Duration(seconds: 1)));
        } else {
          // 처음 찜하는 경우 폴더 선택 다이얼로그
          showDialog(
            context: context,
            builder: (context) => WishlistFolderDialog(place: place),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isWishlisted ? AppColors.primary : Colors.white,
          size: 20,
        ),
      ),
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
          // 알림 아이콘 (뱃지 포함)
          StreamBuilder<int>(
            stream: _getUnreadNotificationCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  _buildAppBarAction(Icons.notifications_rounded, () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TagNotificationScreen()));
                  }),
                  if (count > 0)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          textAlign: Alignment.center.x == 0 ? TextAlign.center : null,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          _buildAppBarAction(Icons.favorite_rounded, () {
            if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인이 필요한 기능입니다.")));
              return;
            }
            Navigator.push(context, MaterialPageRoute(builder: (context) => const WishlistScreen()));
          }),
          _buildAppBarAction(Icons.tune_rounded, _showFilterSettings),
          _buildAppBarAction(Icons.people_alt_rounded, () {
            if (FirebaseAuth.instance.currentUser?.isAnonymous ?? true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인이 필요한 기능입니다.")));
              return;
            }
            Navigator.push(context, MaterialPageRoute(builder: (context) => const FriendScreen()));
          }),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModeToggle(),
                  const SizedBox(height: 40),
                  Text(
                    _isFoodMode ? "어떤 종류가 땡기세요?" : "어디로 갈까요?", 
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 20),
                  _buildChipGrid(currentCats.keys.toList(), _selectedMainCats),

                  if (_selectedMainCats.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    Text(
                      _isFoodMode ? "세부 메뉴는요?" : "활동 종류", 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    Builder(builder: (context) {
                      final List<String> subItems = [];
                      for (var key in _selectedMainCats) {
                        if (currentCats.containsKey(key)) subItems.addAll(currentCats[key]!);
                      }
                      return _buildChipGrid(subItems, _selectedSubCats);
                    }),
                  ],
                ],
              ),
            ),

            // 핫플레이스는 화면 끝까지 스크롤되도록 Padding을 분리
            Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 140.0),
              child: _buildHotPlaces(),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        color: AppColors.background,
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 16),
        child: AppGradientButton(
          text: '오토카지 추천받기',
          icon: Icons.auto_awesome_rounded,
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _searchAndRecommend,
          height: 60,
        ),
      ),
    );
  }

  Widget _buildAppBarAction(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}