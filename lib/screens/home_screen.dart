import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart'; // iOS 스타일 로딩 인디케이터용
import 'package:flutter/material.dart';
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
    '바': ['칵테일', '와인', '맥주', '이자카야', '술집', '호프', '요리주점'],
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
      // textquery: 가게 이름, locationbias: 내 위치 근처 우선
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

    if (_selectedMainCats.contains('카페')) {
      type = 'cafe';
    } else if (_selectedMainCats.contains('바')) {
      type = 'bar';
    } else if (!_isFoodMode) {
      type = 'point_of_interest'; 
    }

    List<String> keywords = [];
    for (var cat in _selectedMainCats) {
      if (cat != '카페' && cat != '바') keywords.add(cat); 
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

      String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${position.latitude},${position.longitude}&radius=$_searchRadius&type=$type&language=ko&key=$kGoogleApiKey';

      if (keyword.isNotEmpty) {
        url += '&keyword=$keyword';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final List<dynamic> results = data['results'];
          
          final List<dynamic> filteredResults = results.where((place) {
            final double rating = (place['rating'] ?? 0).toDouble();
            return rating >= _minRating;
          }).toList();

          _searchResults = filteredResults;
          _nextPageToken = data['next_page_token'];

          if (_searchResults.isEmpty) {
            String fallbackQuery = keyword.isEmpty ? (type == 'restaurant' ? "맛집" : type) : keyword;
            _showNaverFallbackDialog(fallbackQuery);
          } else {
            _showSelectionDialog(_searchResults);
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
          final List<dynamic> results = data['results'];
          
          final List<dynamic> filteredResults = results.where((place) {
            final double rating = (place['rating'] ?? 0).toDouble();
            return rating >= _minRating;
          }).toList();

          setState(() {
            _searchResults.addAll(filteredResults);
            _nextPageToken = data['next_page_token'];
          });
        } else if (data['status'] == 'INVALID_REQUEST') {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // [수정] 미리보기에서도 구글 사진 로딩
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: FutureBuilder<String?>(
                future: _fetchGooglePlacePhoto(place['name'], place['lat'], place['lng']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(height: 200, color: Colors.grey[100], child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)));
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.network(snapshot.data!, height: 200, width: double.infinity, fit: BoxFit.cover);
                  }
                  // 실패시 기본 이미지
                  return Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.store, size: 50, color: Colors.grey));
                },
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text(place['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  
                  if (place['menu'] != null && place['menu'] != "메뉴 정보 없음")
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                      child: Text(place['menu'], style: const TextStyle(fontSize: 13, color: Colors.black87), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),

                  const Text("인스타그램에서 이 핫플 구경하기", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _launchInstagramSearch(place['name']),
                      icon: const Icon(Icons.camera_alt, color: Colors.purple),
                      label: const Text("Instagram 구경가기", style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.purple),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onPlaceSelected(place['name'], place['lat'], place['lng']);
                      },
                      icon: const Icon(Icons.map),
                      label: const Text("지도에서 위치 보기"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "🎉 ${_searchResults.length}곳 이상의 장소를 찾았어요!",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "반경 ${_searchRadius.toInt()}m 이내, 별점 $_minRating↑",
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showResultList();
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
                        if (filteredCandidates.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("별점 조건에 맞는 곳이 없어서 랜덤을 돌릴 수 없어요!")));
                          return;
                        }
                        Navigator.pop(context);
                        final random = Random();
                        final selected = filteredCandidates[random.nextInt(filteredCandidates.length)];
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

  void _showResultList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("추천 리스트 (무한 스크롤)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: _searchResults.length + (_nextPageToken != null ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _searchResults.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
                            );
                          }

                          final place = _searchResults[index];
                          final double rating = (place['rating'] ?? 0).toDouble();
                          
                          return ListTile(
                            title: Text(place['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                            subtitle: Text(place['vicinity'] ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                Text(" $rating", style: const TextStyle(color: Colors.black)),
                              ],
                            ),
                            onTap: () async {
                              final bool? selected = await _showSingleResultDialog(place);
                              if (selected == true) {
                                Navigator.pop(context); 
                              }
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
      },
    );
  }

  Future<bool?> _showSingleResultDialog(Map<String, dynamic> place) async {
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
                      onPressed: () { 
                        Navigator.pop(context, true); 
                        widget.onPlaceSelected(name, lat, lng); 
                      },
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
                    onChangeEnd: (val) {
                      setState(() => _searchRadius = val);
                      _saveFilterSettings(); 
                    },
                  ),
                  const SizedBox(height: 10),
                  Text("최소 평점: $_minRating점 이상"),
                  Slider(
                    value: _minRating,
                    min: 0.0, max: 5.0, divisions: 10,
                    label: "$_minRating",
                    activeColor: Colors.amber,
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

  // [수정] 핫플레이스 섹션 (사진 로딩 적용)
  Widget _buildHotPlaces() {
    final locationAsync = ref.watch(locationProvider);

    return StreamBuilder<QuerySnapshot>(
      stream: _getHotPlacesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();

        List<Map<String, dynamic>> places = [];
        
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final String category = data['category'] ?? '기타';

          if (_isFoodMode) {
            if (!_foodCategories.containsKey(category) && category != '기타') continue;
          } else {
            if (!_playCategories.containsKey(category) && category != '기타') continue;
          }

          double distance = 0.0;
          if (locationAsync.hasValue && locationAsync.value != null && data['lat'] != null && data['lng'] != null) {
            distance = Geolocator.distanceBetween(
              locationAsync.value!.latitude, locationAsync.value!.longitude,
              data['lat'], data['lng']
            );
          }

          if (distance > _searchRadius) continue; // [수정] 5000 -> _searchRadius
          
          double rating = (data['rating'] ?? 0).toDouble();
          if (rating < _minRating) continue; // [신규] 평점 필터 적용

          data['distance'] = distance;
          places.add(data);
        }

        places.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

        if (places.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
              child: Text("🔥 내 주변 핫플레이스 (${_searchRadius.toInt()}m)", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 230, 
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final data = places[index];
                  
                  String distStr = "";
                  double dist = data['distance'];
                  if (dist >= 1000) {
                    distStr = "${(dist / 1000).toStringAsFixed(1)}km";
                  } else {
                    distStr = "${dist.toInt()}m";
                  }

                  return GestureDetector(
                    onTap: () {
                      _showHotPlacePreview(data);
                    },
                    child: Container(
                      width: 160,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // [핵심] FutureBuilder로 구글 이미지 로딩
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: FutureBuilder<String?>(
                              future: _fetchGooglePlacePhoto(data['name'], data['lat'], data['lng']),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Container(height: 120, color: Colors.grey[100], child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)));
                                }
                                if (snapshot.hasData && snapshot.data != null) {
                                  return Image.network(snapshot.data!, height: 120, width: double.infinity, fit: BoxFit.cover);
                                }
                                // 실패시 Firestore 이미지 또는 기본 아이콘
                                return Image.network(
                                  data['imageUrl'] ?? '',
                                  height: 120, 
                                  width: double.infinity, 
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) => Container(height: 120, color: Colors.grey[200], child: const Icon(Icons.store, color: Colors.grey)),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star, size: 14, color: Colors.amber),
                                    Text(" ${data['rating'] ?? '-'}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    Text(distStr, style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(data['category'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          IconButton(icon: const Icon(Icons.tune, color: Colors.black), onPressed: _showFilterSettings),
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
            const SizedBox(height: 24),
            _buildHotPlaces(), 
            const SizedBox(height: 24),
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