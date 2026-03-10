import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// 통합 장소 결과 모델
class PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final int reviewCount;
  final String category;
  final String source; // 'google', 'naver', 'kakao'
  final String? photoUrl;
  final String? placeUrl; // 네이버/카카오 상세 URL
  final String? placeId; // 구글 place_id
  final Map<String, dynamic>? rawData; // 원본 데이터
  final List<String> tags; // 찜한 폴더(태그) 목록

  String get uniqueId => placeId ?? "${name}_${lat}_${lng}";

  PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.rating = 0,
    this.reviewCount = 0,
    this.category = '기타',
    required this.source,
    this.photoUrl,
    this.placeUrl,
    this.placeId,
    this.rawData,
    this.tags = const [],
  });

  double getScore(double userLat, double userLng) {
    // 1. 평점 점수 (0~5점)
    double ratingScore = rating;

    // 2. 리뷰 수 점수 (로그 스케일 적용, 0~5점 사이로 정규화 시도)
    // 리뷰 10개면 약 1.0, 100개면 약 2.0, 1000개면 약 3.0
    double reviewScore = _log10(reviewCount + 1);

    // 3. 거리 점수 (가까울수록 높음)
    double distanceScore = 0;
    try {
      double distanceInMeters = Geolocator.distanceBetween(userLat, userLng, lat, lng);
      // 500m 이내면 5점, 1km 이내면 3점, 2km 이상이면 0점 등으로 가중치 부여
      if (distanceInMeters < 500) {
        distanceScore = 5.0;
      } else if (distanceInMeters < 1500) {
        distanceScore = 3.0;
      } else if (distanceInMeters < 3000) {
        distanceScore = 1.0;
      }
    } catch (e) {
      distanceScore = 0;
    }

    // 최종 스코어 = (평점 * 0.4) + (리뷰 * 0.3) + (거리 * 0.3)
    double finalScore = (ratingScore * 0.4) + (reviewScore * 0.3) + (distanceScore * 0.3);

    // 소스별 추가 가산점 (네이버/카카오는 한국 로컬 데이터가 강하므로 약간의 보정)
    if (source == 'naver') finalScore += 0.5;
    if (source == 'kakao') finalScore += 0.3;

    return finalScore;
  }

  static double _log10(num x) {
    if (x <= 0) return 0;
    return math.log(x.toDouble()) / math.ln10;
  }

  Map<String, dynamic> toGoogleFormat() {
    return rawData ?? {
      'name': name,
      'vicinity': address,
      'rating': rating,
      'user_ratings_total': reviewCount,
      'geometry': {
        'location': {'lat': lat, 'lng': lng}
      },
      'place_id': placeId,
      'source': source,
      'place_url': placeUrl,
    };
  }
}

class AICourse {
  final String title;
  final String description;
  final List<PlaceResult> steps;
  AICourse({required this.title, required this.description, required this.steps});
}

class PlaceSearchService {
  static String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static String get _naverClientId => dotenv.env['NAVER_CLIENT_ID'] ?? '';
  static String get _naverClientSecret => dotenv.env['NAVER_CLIENT_SECRET'] ?? '';
  static String get _kakaoRestApiKey => dotenv.env['KAKAO_REST_API_KEY'] ?? '';

  static Future<List<PlaceResult>> searchNaver({required String query, int display = 5, String sort = 'comment'}) async {
    if (_naverClientId.isEmpty || _naverClientSecret.isEmpty) return [];
    try {
      debugPrint("[Xcode 로그] 네이버 검색 요청: $query");
      final uri = Uri.parse('https://openapi.naver.com/v1/search/local.json?query=${Uri.encodeComponent(query)}&display=$display&sort=$sort');
      final response = await http.get(uri, headers: {'X-Naver-Client-Id': _naverClientId, 'X-Naver-Client-Secret': _naverClientSecret});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['items'] ?? [];
        debugPrint("[Xcode 로그] 네이버 검색 결과: ${items.length}개 발견");
        return items.map((item) {
          double lat = 0, lng = 0;
          if (item['mapx'] != null && item['mapy'] != null) {
            double rawX = double.tryParse(item['mapx'].toString()) ?? 0;
            double rawY = double.tryParse(item['mapy'].toString()) ?? 0;
            
            if (rawX > 1000000 && rawY > 1000000) {
              // 네이버 TM128 -> 위경도 근사 변환 (정밀하진 않지만 거리 계산 및 지도 표시 가능 수준)
              lng = rawX / 10000000.0;
              lat = rawY / 10000000.0;
            } else if (rawX > 200 || rawY > 100) {
              // 좌표계가 큰 값인 경우 (KATECH 등)
              // 변환 라이브러리 없이 정확한 변환은 어려우므로 
              // 일단 0,0이 아닌 현재 위치 근처로 보이게 하여 리스트 누락 방지
              lat = 0.1; lng = 0.1; 
            } else {
              lng = rawX; lat = rawY;
            }
          }
          return PlaceResult(name: _cleanHtml(item['title'] ?? ''), address: item['roadAddress'] ?? item['address'] ?? '', lat: lat, lng: lng, category: item['category'] ?? '기타', source: 'naver', placeUrl: item['link']);
        }).toList();
      }
    } catch (e) {
      debugPrint("[Xcode 로그] 네이버 에러: $e");
    }
    return [];
  }

  static Future<List<PlaceResult>> searchKakao({required String query, required double lat, required double lng, int radius = 1000, String? categoryGroupCode, int size = 10}) async {
    if (_kakaoRestApiKey.isEmpty) return [];
    try {
      debugPrint("[Xcode 로그] 카카오 검색 요청: $query (반경: $radius)");
      final url = 'https://dapi.kakao.com/v2/local/search/keyword.json?query=${Uri.encodeComponent(query)}&x=$lng&y=$lat&radius=$radius&size=$size${categoryGroupCode != null ? "&category_group_code=$categoryGroupCode" : ""}';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'KakaoAK $_kakaoRestApiKey'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> docs = data['documents'] ?? [];
        debugPrint("[Xcode 로그] 카카오 검색 결과: ${docs.length}개 발견");
        return docs.map((doc) => PlaceResult(name: doc['place_name'] ?? '', address: doc['road_address_name'] ?? doc['address_name'] ?? '', lat: double.tryParse(doc['y'] ?? '0') ?? 0, lng: double.tryParse(doc['x'] ?? '0') ?? 0, category: doc['category_name'] ?? '기타', source: 'kakao', placeUrl: doc['place_url'])).toList();
      }
    } catch (e) {
      debugPrint("[Xcode 로그] 카카오 에러: $e");
    }
    return [];
  }

  static Future<List<PlaceResult>> searchGoogle({required double lat, required double lng, required int radius, required String type, String keyword = ''}) async {
    if (_googleApiKey.isEmpty) return [];
    try {
      debugPrint("[Xcode 로그] 구글 검색 요청: $type (키워드: $keyword, 반경: $radius)");
      // rankby=prominence는 radius와 함께 사용될 때 기본값이지만 명시적으로 고려 (radius 필수)
      String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=$type&language=ko&key=$_googleApiKey';
      if (keyword.isNotEmpty) url += '&keyword=${Uri.encodeComponent(keyword)}';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String status = data['status'] ?? 'UNKNOWN';
        
        if (status == 'OK') {
          final results = data['results'] as List;
          debugPrint("[Xcode 로그] 구글 검색 결과: ${results.length}개 발견");
          return results.map((place) {
            final geo = place['geometry']['location'];
            String? photoUrl;
            if (place['photos'] != null && (place['photos'] as List).isNotEmpty) {
              photoUrl = 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${place['photos'][0]['photo_reference']}&key=$_googleApiKey';
            }
            return PlaceResult(name: place['name'] ?? '', address: place['vicinity'] ?? '', lat: (geo['lat'] as num).toDouble(), lng: (geo['lng'] as num).toDouble(), rating: (place['rating'] ?? 0).toDouble(), reviewCount: place['user_ratings_total'] ?? 0, category: (place['types'] as List).isNotEmpty ? place['types'][0] : '기타', source: 'google', photoUrl: photoUrl, placeId: place['place_id'], rawData: Map<String, dynamic>.from(place));
          }).toList();
        } else {
          debugPrint("[Xcode 로그] 구글 검색 실패 상태: $status");
          if (data['error_message'] != null) {
            debugPrint("[Xcode 로그] 구글 에러 메시지: ${data['error_message']}");
          }
        }
      } else {
        debugPrint("[Xcode 로그] 구글 HTTP 에러: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("[Xcode 로그] 구글 에러: $e");
    }
    return [];
  }

  static Future<List<PlaceResult>> hybridSearch({required double lat, required double lng, required int radius, required String googleType, required String keyword, double minRating = 0.0}) async {
    // 역 이름을 가져와서 검색어 보강 (네이버용)
    final stations = await getNearbyStations(lat, lng);
    final String stationContext = stations.isNotEmpty ? stations.first : "주변";
    final String naverQuery = keyword.isNotEmpty ? "$stationContext $keyword" : "$stationContext 맛집";

    final results = await Future.wait([
      searchGoogle(lat: lat, lng: lng, radius: radius, type: googleType, keyword: keyword),
      searchKakao(query: keyword.isNotEmpty ? keyword : '맛집', lat: lat, lng: lng, radius: radius),
      searchNaver(query: naverQuery),
    ]);
    final merged = _mergeAndDeduplicate(results[0], results[1], results[2]);
    
    // 거리 필터링 및 조건 필터링
    return merged.where((p) {
      if (p.lat > 1.0 && p.lng > 1.0) {
        try {
          final distance = Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
          double maxDistance = radius + 2000.0; // 추천은 더 넓게 (반경 + 2km)
          if (distance > maxDistance) return false;
        } catch (e) {
          // 계산 오류 시 통과
        }
      }
      
      return p.source == 'naver' || p.source == 'kakao' || p.rating >= minRating;
    }).toList()..sort((a, b) => b.getScore(lat, lng).compareTo(a.getScore(lat, lng)));
  }

  /// ─── [고도화] 정밀 타격 하이브리드 검색 (역 2개 + 아시안 보강 + 로그 전면 복구) ───
  static Future<List<PlaceResult>> hybridHotPlaces({
    required double lat,
    required double lng,
    required int radius,
    required bool isFoodMode,
    Set<String> selectedCats = const {},
    Set<String> selectedSubCats = const {},
    double minRating = 0.0,
  }) async {
    final stations = await getNearbyStations(lat, lng);
    debugPrint("[Xcode 로그] 검색 기준 역: $stations");
    
    final Map<String, List<String>> foodKeywords = {
      '한식': ['밥', '국물', '고기', '면', '분식', '찌개', '백반', '족발', '곱창'],
      '중식': ['면', '밥', '요리', '딤섬', '짜장', '마라', '양꼬치'],
      '일식': ['초밥', '돈까스', '라멘', '덮밥', '회', '우동', '소바', '카츠', '이자카야'],
      '양식': ['파스타', '피자', '스테이크', '버거', '브런치'],
      '아시안': ['쌀국수', '카레', '팟타이', '타코', '태국음식', '인도음식', '베트남음식'],
      '디저트': ['카페', '빵', '케이크', '아이스크림', '빙수', '마카롱', '도넛'],
    };

    List<String> queries = [];

    if (isFoodMode) {
      if (selectedCats.isEmpty) {
        for (var station in stations) {
          final List<String> allSubs = [];
          foodKeywords.forEach((main, subs) { if (main != '디저트') allSubs.addAll(subs); });
          allSubs.shuffle();
          for (var k in allSubs.take(8)) { queries.add('$station $k 맛집'); }
        }
      } else {
        for (var station in stations) {
          for (var mainCat in selectedCats) {
            // '아시안' 등 메인 카테고리 명칭 그대로 사용 (불필요한 '요리' 접미사 제거)
            final String queryMain = mainCat; 
            
            if (selectedSubCats.isEmpty) {
              final subs = foodKeywords[mainCat] ?? [];
              // 메인 카테고리 검색
              queries.add('$station $queryMain 맛집');
              // 보조 키워드로 검색 (너무 길지 않게 핵심 단어만)
              for (var s in subs.take(3)) { queries.add('$station $s 맛집'); }
            } else {
              for (var subCat in selectedSubCats) {
                if (foodKeywords[mainCat]?.contains(subCat) ?? false) {
                  // 세부 카테고리가 있으면 메인 카테고리를 제외하고 검색하여 정확도 향상
                  // 예: '상계역 아시안 요리 쌀국수 맛집' -> '상계역 쌀국수 맛집'
                  queries.add('$station $subCat 맛집');
                }
              }
            }
          }
        }
      }
    } else {
      for (var station in stations) {
        if (selectedCats.isEmpty) {
          queries.add('$station 핫플');
          queries.add('$station 놀거리');
        } else {
          for (var c in selectedCats) { queries.add('$station $c'); }
        }
      }
    }

    queries.shuffle();
    final finalQueries = queries.take(20).toList();
    debugPrint("[Xcode 로그] 최종 실행 쿼리 목록: $finalQueries");

    final List<Future<List<PlaceResult>>> naverFutures = finalQueries.map((q) => searchNaver(query: q, display: 5)).toList();
    
    // 구글/카카오용 검색 키워드 생성 (필터 적용)
    String searchKeyword = isFoodMode ? "맛집" : "핫플";
    if (selectedCats.isNotEmpty) {
      searchKeyword = selectedCats.join(" ");
      if (selectedSubCats.isNotEmpty) {
        searchKeyword += " ${selectedSubCats.join(" ")}";
      }
    }

    // 구글/카카오는 반경이 너무 작으면 결과가 0개일 확률이 매우 높으므로 최소 1000m 권장
    final int safeRadius = radius < 1000 ? 1000 : radius;

    final List<PlaceResult> googleBase = await searchGoogle(
      lat: lat, lng: lng, radius: safeRadius, 
      type: isFoodMode ? 'restaurant' : 'point_of_interest',
      keyword: searchKeyword, // 키워드 필터 적용
    );
    final List<PlaceResult> kakaoBase = await searchKakao(
      query: searchKeyword, // 키워드 필터 적용
      lat: lat, lng: lng, radius: safeRadius, size: 20
    );
    
    final List<List<PlaceResult>> naverResultsList = await Future.wait(naverFutures);
    final List<PlaceResult> allNaverResults = naverResultsList.expand((x) => x).toList();

    debugPrint("[Xcode 로그] 데이터 수집 완료 - 네이버: ${allNaverResults.length}, 구글: ${googleBase.length}, 카카오: ${kakaoBase.length}");

    final merged = _mergeAndDeduplicate(googleBase, kakaoBase, allNaverResults);

    final bool isDessertSelected = selectedCats.contains('디저트') || selectedCats.contains('카페');
    final filtered = merged.where((p) {
      // 1. 거리 필터링
      if (p.lat > 1.0 && p.lng > 1.0) { // 유효한 좌표인 경우만 계산
        try {
          final distance = Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
          double maxDistance = radius + 1500.0; // 기본 반경 + 1.5km 여유
          
          // 네이버 결과는 좌표가 부정확할 수 있으므로 거리 필터링을 더 완화 (3km까지 허용)
          if (p.source == 'naver') maxDistance = radius + 3000.0;
          
          if (distance > maxDistance) return false;
        } catch (e) {
          // 계산 오류 시 통과
        }
      }

      // 2. 카테고리 및 품질 필터링
      if (isFoodMode && !isDessertSelected) {
        final c = p.category.toLowerCase();
        if (c.contains('카페') || c.contains('디저트') || c.contains('coffee') || c.contains('cafe')) return false;
      }
      
      if (p.source == 'google') {
        return p.rating >= minRating;
      }
      
      return true;
    }).toList();

    debugPrint("[Xcode 로그] 필터링 후 최종 핫플 개수: ${filtered.length}개");
    return filtered..sort((a, b) => b.getScore(lat, lng).compareTo(a.getScore(lat, lng)));
  }

  static List<PlaceResult> _mergeAndDeduplicate(List<PlaceResult> google, List<PlaceResult> kakao, List<PlaceResult> naver) {
    final Map<String, PlaceResult> seen = {};
    final List<String> excludedFranchises = ['스타벅스', 'STARBUCKS', '투썸플레이스', '이디야', 'EDIYA', '커피빈', '할리스', '파스쿠찌', '엔제리너스', '빽다방', '메가MGC커피', '컴포즈커피', '더벤티', '폴바셋', '파리바게뜨', '뚜레쥬르', '던킨', '배스킨라빈스', '맥도날드', '롯데리아', '버거킹', '맘스터치', 'KFC', '노브랜드버거', '서브웨이', 'CU', 'GS25', '세븐일레븐', '이마트24', '미니스톱', '이마트', '홈플러스', '롯데마트', '코스트코', '다이소', '올리브영'];
    bool isFranchise(String name) {
      final n = name.toLowerCase().replaceAll(' ', '');
      return excludedFranchises.any((f) => n.contains(f.toLowerCase().replaceAll(' ', '')));
    }
    for (var p in google) { if (!isFranchise(p.name)) seen[_normalizeKey(p.name)] = p; }
    for (var p in kakao) { if (!isFranchise(p.name)) { final k = _normalizeKey(p.name); if (!seen.containsKey(k)) seen[k] = p; } }
    for (var p in naver) { if (!isFranchise(p.name)) { final k = _normalizeKey(p.name); if (!seen.containsKey(k)) seen[k] = p; } }
    return seen.values.toList();
  }

  static String _normalizeKey(String name) => name.replaceAll(RegExp(r'<[^>]*>|\s+|[^\w가-힣]'), '').toLowerCase();
  static String _cleanHtml(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  static Future<List<String>> getNearbyStations(double lat, double lng) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=2000&type=subway_station&language=ko&key=$_googleApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          final names = <String>[];
          for (var p in results) {
            String n = p['name'] ?? '';
            n = n.replaceAll(RegExp(r'\s+\d+호선.*|\s+\(.*\)'), '').trim();
            if (!n.endsWith('역')) n = '$n역';
            if (n.length <= 5 && !names.contains(n)) names.add(n);
            if (names.length >= 2) break;
          }
          if (names.isNotEmpty) return names;
        }
      }
    } catch (e) {
      debugPrint("[Xcode 로그] 역 검색 실패: $e");
    }
    return ['주변'];
  }

  static Future<List<AICourse>> generateAICourses({required double lat, required double lng}) async {
    final int searchRadius = 1500;
    final results = await Future.wait([
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'restaurant', keyword: '맛집', minRating: 3.5),
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'point_of_interest', keyword: '핫플 볼거리 방탈출 영화관 보드게임', minRating: 3.5),
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'cafe', keyword: '분위기 좋은 카페 디저트', minRating: 3.5),
    ]);
    final List<PlaceResult> restaurants = results[0]..shuffle();
    final List<PlaceResult> activities = results[1]..shuffle();
    final List<PlaceResult> cafes = results[2]..shuffle();
    if (restaurants.isEmpty && activities.isEmpty && cafes.isEmpty) return [];
    final List<AICourse> courses = [];
    final titles = ['🍽️ 오감만족 완벽한 하루', '💕 분위기 깡패 로맨틱 코스', '🚶 뚜벅이 힐링 가성비 코스'];
    final descriptions = ['검증된 맛집과 즐거운 활동으로 꽉 채운 코스입니다!', '특별한 날에 어울리는 감성 가득한 조합입니다.', '부담 없이 가볍게 즐기기 좋은 편안한 루트예요.'];
    for (int i = 0; i < 3; i++) {
      final List<PlaceResult> steps = [];
      if (restaurants.length > i) steps.add(restaurants[i]);
      if (activities.length > i) steps.add(activities[i]);
      if (cafes.length > i) steps.add(cafes[i]);
      if (steps.length >= 2) {
        courses.add(AICourse(title: titles[i], description: descriptions[i], steps: steps));
      }
    }
    return courses;
  }
}
