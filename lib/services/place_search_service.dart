import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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

  /// 고유 식별자 (ID가 없으면 이름+좌표 조합)
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

  /// 통합 점수 산출: (평점 × log10(리뷰수+1)) + 출처 보너스
  double get score {
    double base = rating * _log10(reviewCount + 1);
    if (source == 'naver') base += 0.5;
    if (source == 'kakao') base += 0.3;
    return base;
  }

  static double _log10(num x) {
    if (x <= 0) return 0;
    return math.log(x.toDouble()) / math.ln10;
  }

  /// Google Places API 형식으로 변환 (기존 다이얼로그와 호환)
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

/// AI 코스 모델
class AICourse {
  final String title;
  final String description;
  final List<PlaceResult> steps; // 유연한 단계 (식당, 놀거리, 카페 등)

  AICourse({
    required this.title,
    required this.description,
    required this.steps,
  });
}

/// 하이브리드 장소 검색 서비스
class PlaceSearchService {
  static String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static String get _naverClientId => dotenv.env['NAVER_CLIENT_ID'] ?? '';
  static String get _naverClientSecret => dotenv.env['NAVER_CLIENT_SECRET'] ?? '';
  static String get _kakaoRestApiKey => dotenv.env['KAKAO_REST_API_KEY'] ?? '';

  /// ─── 네이버 지역 검색 ───
  static Future<List<PlaceResult>> searchNaver({
    required String query,
    int display = 5,
    String sort = 'comment',
  }) async {
    if (_naverClientId.isEmpty || _naverClientSecret.isEmpty) return [];

    try {
      final uri = Uri.parse(
        'https://openapi.naver.com/v1/search/local.json'
        '?query=${Uri.encodeComponent(query)}'
        '&display=$display'
        '&sort=$sort'
      );

      final response = await http.get(uri, headers: {
        'X-Naver-Client-Id': _naverClientId,
        'X-Naver-Client-Secret': _naverClientSecret,
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['items'] ?? [];

        return items.map((item) {
          final String title = _cleanHtml(item['title'] ?? '');
          final String address = item['roadAddress'] ?? item['address'] ?? '';
          final String category = item['category'] ?? '기타';
          
          double lat = 0, lng = 0;
          final rawMapx = item['mapx'];
          final rawMapy = item['mapy'];
          if (rawMapx != null && rawMapy != null) {
            lng = double.parse(rawMapx.toString()) / 10000000.0;
            lat = double.parse(rawMapy.toString()) / 10000000.0;
          }

          return PlaceResult(
            name: title,
            address: address,
            lat: lat,
            lng: lng,
            category: category,
            source: 'naver',
            placeUrl: item['link'],
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('네이버 검색 예외: $e');
    }
    return [];
  }

  /// ─── 카카오 장소 검색 ───
  static Future<List<PlaceResult>> searchKakao({
    required String query,
    required double lat,
    required double lng,
    int radius = 1000,
    String? categoryGroupCode,
    int size = 10,
  }) async {
    if (_kakaoRestApiKey.isEmpty) return [];

    try {
      final url = 'https://dapi.kakao.com/v2/local/search/keyword.json'
          '?query=${Uri.encodeComponent(query)}'
          '&x=$lng&y=$lat&radius=$radius&size=$size'
          '${categoryGroupCode != null ? "&category_group_code=$categoryGroupCode" : ""}';

      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'KakaoAK $_kakaoRestApiKey',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> docs = data['documents'] ?? [];

        return docs.map((doc) {
          return PlaceResult(
            name: doc['place_name'] ?? '',
            address: doc['road_address_name'] ?? doc['address_name'] ?? '',
            lat: double.tryParse(doc['y'] ?? '0') ?? 0,
            lng: double.tryParse(doc['x'] ?? '0') ?? 0,
            category: doc['category_name'] ?? '기타',
            source: 'kakao',
            placeUrl: doc['place_url'],
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('카카오 검색 예외: $e');
    }
    return [];
  }

  /// ─── 구글 Places API ───
  static Future<List<PlaceResult>> searchGoogle({
    required double lat,
    required double lng,
    required int radius,
    required String type,
    String keyword = '',
  }) async {
    if (_googleApiKey.isEmpty) return [];

    try {
      String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=$lat,$lng'
          '&radius=$radius'
          '&type=$type'
          '&language=ko'
          '&key=$_googleApiKey';

      if (keyword.isNotEmpty) {
        url += '&keyword=${Uri.encodeComponent(keyword)}';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'] ?? [];

          return results.map((place) {
            final geo = place['geometry']['location'];
            String? photoUrl;
            if (place['photos'] != null && (place['photos'] as List).isNotEmpty) {
              final photoRef = place['photos'][0]['photo_reference'];
              photoUrl = 'https://maps.googleapis.com/maps/api/place/photo'
                  '?maxwidth=400&photoreference=$photoRef&key=$_googleApiKey';
            }

            return PlaceResult(
              name: place['name'] ?? '',
              address: place['vicinity'] ?? '',
              lat: (geo['lat'] as num).toDouble(),
              lng: (geo['lng'] as num).toDouble(),
              rating: (place['rating'] ?? 0).toDouble(),
              reviewCount: place['user_ratings_total'] ?? 0,
              category: (place['types'] != null && (place['types'] as List).isNotEmpty)
                  ? place['types'][0]
                  : '기타',
              source: 'google',
              photoUrl: photoUrl,
              placeId: place['place_id'],
              rawData: Map<String, dynamic>.from(place),
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('구글 검색 오류: $e');
    }
    return [];
  }

  /// ─── 하이브리드 검색 ───
  static Future<List<PlaceResult>> hybridSearch({
    required double lat,
    required double lng,
    required int radius,
    required String googleType,
    required String keyword,
    double minRating = 0.0,
  }) async {
    String? kakaoCategoryCode;
    if (googleType == 'restaurant') kakaoCategoryCode = 'FD6';
    if (googleType == 'cafe') kakaoCategoryCode = 'CE7';

    String searchQuery = keyword.isNotEmpty ? keyword : '맛집';
    if (googleType == 'cafe') searchQuery = '카페';

    final stations = await _getNearbyStations(lat, lng);
    final stationQuery = '${stations.first} $searchQuery';

    final results = await Future.wait([
      searchGoogle(lat: lat, lng: lng, radius: radius, type: googleType, keyword: keyword),
      searchKakao(query: searchQuery, lat: lat, lng: lng, radius: radius, categoryGroupCode: kakaoCategoryCode),
      searchNaver(query: stationQuery, display: 5, sort: 'comment'),
    ]);

    final merged = _mergeAndDeduplicate(results[0], results[1], results[2]);
    final filtered = merged.where((p) {
      if (p.source != 'google') return true;
      return p.rating >= minRating;
    }).toList();

    filtered.sort((a, b) => b.score.compareTo(a.score));
    return filtered;
  }

  /// ─── AI 약속/데이트 코스 생성 (유연한 로직) ───
  static Future<List<AICourse>> generateAICourses({
    required double lat,
    required double lng,
  }) async {
    final int searchRadius = 1500;
    
    final results = await Future.wait([
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'restaurant', keyword: '맛집', minRating: 3.5),
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'point_of_interest', keyword: '핫플 볼거리 방탈출 영화관 보드게임', minRating: 3.5),
      hybridSearch(lat: lat, lng: lng, radius: searchRadius, googleType: 'cafe', keyword: '분위기 좋은 카페 디저트', minRating: 3.5),
    ]);

    final List<PlaceResult> restaurants = results[0]..shuffle();
    final List<PlaceResult> activities = results[1]..shuffle();
    final List<PlaceResult> cafes = results[2]..shuffle();

    // 하나도 없으면 실패
    if (restaurants.isEmpty && activities.isEmpty && cafes.isEmpty) return [];

    final List<AICourse> courses = [];
    final titles = ['🍽️ 오감만족 완벽한 하루', '💕 분위기 깡패 로맨틱 코스', '🚶 뚜벅이 힐링 가성비 코스'];
    final descriptions = [
      '검증된 맛집과 즐거운 활동으로 꽉 채운 코스입니다!',
      '특별한 날에 어울리는 감성 가득한 조합입니다.',
      '부담 없이 가볍게 즐기기 좋은 편안한 루트예요.'
    ];

    for (int i = 0; i < 3; i++) {
      final List<PlaceResult> steps = [];
      if (restaurants.length > i) steps.add(restaurants[i]);
      if (activities.length > i) steps.add(activities[i]);
      if (cafes.length > i) steps.add(cafes[i]);

      if (steps.length >= 2) { // 최소 2곳 이상일 때만 코스로 인정
        courses.add(AICourse(
          title: titles[i],
          description: descriptions[i],
          steps: steps,
        ));
      }
    }

    return courses;
  }

  /// ─── 핫플레이스 전용 하이브리드 검색 ───
  static Future<List<PlaceResult>> hybridHotPlaces({
    required double lat,
    required double lng,
    required int radius,
    required bool isFoodMode,
    Set<String> selectedCats = const {},
    int limit = 35,
  }) async {
    final String googleType = isFoodMode ? 'restaurant' : 'point_of_interest';
    String? kakaoCategory = isFoodMode ? 'FD6' : null;

    final stations = await _getNearbyStations(lat, lng);
    
    List<String> naverQueries = [];
    if (selectedCats.isNotEmpty) {
      for (var station in stations) {
        for (var cat in selectedCats) {
          naverQueries.add('$station $cat 맛집');
        }
      }
    } else {
      for (var station in stations) {
        if (isFoodMode) {
          naverQueries.add('$station 맛집');
        } else {
          naverQueries.add('$station 핫플');
          naverQueries.add('$station 카페');
        }
      }
    }

    String googleKeyword = selectedCats.join(' ');
    String kakaoQuery = selectedCats.isNotEmpty ? selectedCats.first : (isFoodMode ? '맛집' : '핫플');

    final naverFutures = naverQueries.map((q) => searchNaver(query: q, display: 5, sort: 'comment')).toList();

    final allFutures = await Future.wait([
      searchGoogle(lat: lat, lng: lng, radius: radius, type: googleType, keyword: googleKeyword),
      searchKakao(query: kakaoQuery, lat: lat, lng: lng, radius: radius, categoryGroupCode: kakaoCategory, size: 15),
      ...naverFutures,
    ]);

    final googleResults = allFutures[0] as List<PlaceResult>;
    final kakaoResults = allFutures[1] as List<PlaceResult>;
    final List<PlaceResult> allNaverResults = [];
    for (int i = 2; i < allFutures.length; i++) {
      allNaverResults.addAll(allFutures[i] as List<PlaceResult>);
    }

    final merged = _mergeAndDeduplicate(googleResults, kakaoResults, allNaverResults);

    final filtered = merged.where((p) {
      if (p.source == 'google') return p.rating >= 3.5 && p.reviewCount >= 5;
      return true;
    }).toList();

    filtered.shuffle();
    return filtered.take(limit).toList();
  }

  static List<PlaceResult> _mergeAndDeduplicate(
      List<PlaceResult> google, List<PlaceResult> kakao, List<PlaceResult> naver) {
    final Map<String, PlaceResult> seen = {};
    for (var p in google) { seen[_normalizeKey(p.name)] = p; }
    for (var p in kakao) {
      final key = _normalizeKey(p.name);
      if (!seen.containsKey(key)) seen[key] = p;
    }
    for (var p in naver) {
      final key = _normalizeKey(p.name);
      if (!seen.containsKey(key)) seen[key] = p;
    }
    return seen.values.toList();
  }

  static String _normalizeKey(String name) {
    return name.replaceAll(RegExp(r'<[^>]*>|\s+|[^\w가-힣]'), '').toLowerCase();
  }

  static String _cleanHtml(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  static Future<List<String>> _getNearbyStations(double lat, double lng) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=2000&type=subway_station&language=ko&key=$_googleApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'] ?? [];
          final stationNames = <String>[];
          for (var place in results) {
            String name = place['name'] ?? '';
            name = name.replaceAll(RegExp(r'\s+\d+호선.*|\s+\(.*\)'), '').trim();
            if (!name.endsWith('역')) name = '$name역';
            if (name.length <= 5 && !stationNames.contains(name)) stationNames.add(name);
            if (stationNames.length >= 3) break;
          }
          if (stationNames.isNotEmpty) return stationNames;
        }
      }
    } catch (_) {}
    return ['주변'];
  }
}
